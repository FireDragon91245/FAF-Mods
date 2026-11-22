#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "native_runtime.hpp"
#include "MinHook.h"
extern "C" {
#include "../third_party/minhook/src/hde/hde32.h"
}
#include <algorithm>
#include <atomic>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>

namespace fd::native {
namespace {
struct CallbackLifetime {
    void* userdata{};
    void(FD_CALL* release)(void*){};

    ~CallbackLifetime() {
        if (release) {
            release(userdata);
        }
    }
};

int FD_CALL readMemory(uintptr_t address, void* result, uint32_t size) {
    SIZE_T copied{};
    return address && result &&
                   ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
                                     result, size, &copied) &&
                   copied == size
               ? FD_SUCCESS
               : FD_FAILURE;
}

struct Subscription {
    const FDModContext* owner;
    FDPatchLocation location;
    FDPatchType type;
    FDHookCallback callback;
    void* userdata;
    std::shared_ptr<std::atomic<bool>> active;
    std::shared_ptr<CallbackLifetime> lifetime;
};

struct Router {
    const Symbol* symbol;
    uintptr_t address;
    size_t span;
    void* stub = nullptr;
    void* trampoline = nullptr;
    bool detour = false;
    bool backendCreated = false;
    std::vector<unsigned char> installed;
    std::vector<bool> boundaries;
    std::atomic<std::shared_ptr<const std::vector<Subscription>>> subscribers{
        std::make_shared<const std::vector<Subscription>>()};

    ~Router() {
        if (stub)
            VirtualFree(stub, 0, MEM_RELEASE);
    }
};

struct Request {
    const Symbol* symbol;
    uint32_t offset;
    FDPatchSpec spec;
    std::shared_ptr<CallbackLifetime> lifetime;
};

struct ReturnFrame {
    Router* router;
    uintptr_t destination, entryStack;
    std::shared_ptr<const std::vector<Subscription>> subscribers;
};

std::mutex registryMutex;
std::map<uintptr_t, std::unique_ptr<Router>> routers;
using PatchSpans = std::vector<std::pair<uintptr_t, size_t>>;
std::atomic<std::shared_ptr<const PatchSpans>> patchSpans{std::make_shared<const PatchSpans>()};
void* returnStub = nullptr;
thread_local const FDModContext* registering = nullptr;
thread_local std::vector<Request> pending;
thread_local std::vector<std::string> definedSymbols;
thread_local bool invalidEntry = false;
thread_local std::string error;
thread_local std::vector<ReturnFrame> returns;

int fail(const std::string& message) {
    error = message;
    invalidEntry = true;
    return FD_FAILURE;
}

unsigned decode(const Symbol& symbol, uint32_t offset, hde32s& instruction) {
    if (offset >= symbol.size)
        return 0;
    unsigned char buffer[16]{};
    std::memcpy(buffer, symbol.original.data() + offset,
                std::min<size_t>(sizeof(buffer), symbol.size - offset));
    hde32_disasm(buffer, &instruction);
    return instruction.flags & F_ERROR || instruction.len > symbol.size - offset ? 0
                                                                                 : instruction.len;
}

bool boundary(const Symbol& symbol, uint32_t offset) {
    uint32_t current = 0;
    hde32s instruction{};
    while (current < offset) {
        auto length = decode(symbol, current, instruction);
        if (!length)
            return false;
        current += length;
    }
    return current == offset && offset < symbol.size;
}

size_t overwriteSpan(const Symbol& symbol, uint32_t offset) {
    size_t span = 0;
    hde32s instruction{};
    while (span < 5) {
        auto length = decode(symbol, offset + uint32_t(span), instruction);
        if (!length || (instruction.opcode & 0xfe) == 0xc2)
            throw std::runtime_error("patch site has no complete five-byte instruction span");
        span += length;
    }
    // Branches entering the middle of stolen instructions would bypass the hook.
    for (uint32_t current = 0; current < symbol.size;) {
        auto length = decode(symbol, current, instruction);
        if (!length)
            throw std::runtime_error("invalid instruction in symbol");
        bool branch = false;
        intptr_t displacement = 0;
        if (instruction.opcode == 0xe8 || instruction.opcode == 0xe9 ||
            (instruction.opcode == 0x0f && (instruction.opcode2 & 0xf0) == 0x80)) {
            branch = true;
            displacement = int32_t(instruction.imm.imm32);
        } else if (instruction.opcode == 0xeb || (instruction.opcode & 0xf0) == 0x70 ||
                   (instruction.opcode & 0xfc) == 0xe0) {
            branch = true;
            displacement = int8_t(instruction.imm.imm8);
        }
        const intptr_t destination = intptr_t(current) + intptr_t(length) + displacement;
        if (branch && (current < offset || current >= offset + span) &&
            destination > intptr_t(offset) && destination < intptr_t(offset + span))
            throw std::runtime_error("another branch enters the middle of the patch site");
        current += length;
    }
    return span;
}

FDHookResult invoke(const Subscription& subscription, FDHookContext& context) noexcept {
    try {
        return subscription.callback(&context, subscription.userdata);
    } catch (...) {
        if (subscription.owner->log)
            subscription.owner->log(
                FD_LOG_ERROR,
                "Native patch callback threw across its C ABI; continuing original code");
        return FD_HOOK_CONTINUE;
    }
}

uintptr_t __attribute__((force_align_arg_pointer)) FD_CALL dispatch(Router* router,
                                                                    FDRegisters* state) noexcept {
    // pushad's saved ESP slot is ignored by popad. Publish the actual incoming
    // stack pointer to callbacks; the stub later uses that slot for its jump.
    state->esp = reinterpret_cast<uintptr_t>(state) + sizeof(FDRegisters);
    auto continuation = router ? reinterpret_cast<uintptr_t>(router->trampoline) : uintptr_t{};
    try {
        if (!router) {
            if (returns.empty())
                std::terminate();
            auto frame = std::move(returns.back());
            returns.pop_back();
            continuation = frame.destination;
            const auto& symbol = *frame.router->symbol;
            FDHookContext context{
                sizeof(context), symbol.name.c_str(), state, engineApi(), frame.router->address,
                symbol.address,  symbol.size,         0,     readMemory};
            for (auto& subscriber : *frame.subscribers)
                if (subscriber.location == FD_PATCH_END && subscriber.active->load())
                    invoke(subscriber, context);
            return frame.destination;
        }
        auto subscribers = router->subscribers.load();
        const auto& symbol = *router->symbol;
        FDHookContext context{sizeof(context), symbol.name.c_str(), state,       engineApi(),
                              router->address, symbol.address,      symbol.size, 0,
                              readMemory};
        const bool needsReturn =
            std::any_of(subscribers->begin(), subscribers->end(), [](const auto& subscriber) {
                return subscriber.location == FD_PATCH_END && subscriber.active->load();
            });
        for (const auto& subscriber : *subscribers) {
            if (!subscriber.active->load() || subscriber.location == FD_PATCH_END) {
                continue;
            }
            context.resumeOffset = 0;
            if (invoke(subscriber, context) != FD_HOOK_REDIRECT) {
                continue;
            }
            const auto destination = context.resumeOffset;
            if (destination >= router->boundaries.size() || !router->boundaries[destination]) {
                if (subscriber.owner->log) {
                    subscriber.owner->log(FD_LOG_ERROR,
                                          "Hook redirect is not an instruction boundary");
                }
                continue;
            }
            const auto address = symbol.address + destination;
            const auto spans = patchSpans.load();
            const bool insidePatch =
                std::any_of(spans->begin(), spans->end(), [address](auto span) {
                    return address > span.first && address < span.first + span.second;
                });
            if (insidePatch) {
                if (subscriber.owner->log) {
                    subscriber.owner->log(FD_LOG_ERROR,
                                          "Hook redirect enters displaced instructions");
                }
                continue;
            }
            continuation = address;
            break;
        }
        if (needsReturn) {
            // Discard abandoned frames after a non-local unwind. Each thread has
            // its own LIFO stack, so recursive calls retain their own arguments.
            while (!returns.empty() && state->esp >= returns.back().entryStack)
                returns.pop_back();
            auto address = reinterpret_cast<uintptr_t*>(state->esp);
            returns.push_back({router, *address, state->esp, std::move(subscribers)});
            *address = reinterpret_cast<uintptr_t>(returnStub);
        }
    } catch (...) {
        // Allocation failure must never escape into an engine frame.
    }
    return continuation;
}

void* makeStub(Router* router) {
    std::vector<unsigned char> code;
    auto bytes = [&](std::initializer_list<unsigned char> values) {
        code.insert(code.end(), values);
    };
    auto word = [&](uintptr_t value) {
        for (unsigned i = 0; i < 4; ++i)
            code.push_back(static_cast<unsigned char>(value >> (i * 8)));
    };
    bytes({0x9c, 0x60, 0x89, 0xe3}); // pushfd; pushad; mov ebx,esp
    bytes({0x81, 0xec});
    word(544);                                         // reserve FXSAVE area and alignment slack
    bytes({0x83, 0xe4, 0xf0, 0x0f, 0xae, 0x04, 0x24}); // align esp; fxsave [esp]
    bytes({0x89, 0xe7, 0xdb, 0xe3}); // mov edi,esp; fninit (callback gets an empty x87 stack)
    bytes({0x68});
    word(0x1f80);
    bytes(
        {0x0f, 0xae, 0x14, 0x24, 0x83, 0xc4, 0x04}); // default MXCSR; original restored by fxrstor
    bytes({0xfc, 0x83, 0xec, 0x08, 0x53});           // cld; align call; push frame
    bytes({0x68});
    word(reinterpret_cast<uintptr_t>(router));
    bytes({0xb8});
    word(reinterpret_cast<uintptr_t>(&dispatch));
    bytes({0xff, 0xd0, 0x89, 0x43, 0x0c}); // call eax; save destination in ignored ESP slot
    bytes({0x0f, 0xae, 0x0f, 0x89, 0xdc, 0x61, 0x9d}); // fxrstor [edi]; mov esp,ebx; popad; popfd
    bytes({0xff, 0x64, 0x24, 0xe8}); // jmp [esp-24], preserving every register and flag
    auto memory = VirtualAlloc(nullptr, code.size(), MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!memory)
        throw std::runtime_error("cannot allocate injection stub");
    std::memcpy(memory, code.data(), code.size());
    DWORD prior;
    if (!VirtualProtect(memory, code.size(), PAGE_EXECUTE_READ, &prior)) {
        VirtualFree(memory, 0, MEM_RELEASE);
        throw std::runtime_error("cannot protect injection stub");
    }
    FlushInstructionCache(GetCurrentProcess(), memory, code.size());
    return memory;
}

bool integrity(const Symbol& symbol) {
    for (uint32_t i = 0; i < symbol.size; ++i) {
        const auto address = symbol.address + i;
        unsigned char expected = symbol.original[i];
        auto it = routers.upper_bound(address);
        if (it != routers.begin()) {
            --it;
            auto& router = *it->second;
            if (address >= router.address && address < router.address + router.installed.size())
                expected = router.installed[address - router.address];
        }
        if (*reinterpret_cast<const unsigned char*>(address) != expected)
            return false;
    }
    return true;
}

std::vector<uint32_t> selectOffsets(const Symbol& symbol, const FDPatchSpec& spec) {
    if (spec.location == FD_PATCH_START || spec.location == FD_PATCH_END) {
        return {0};
    }
    if (spec.location == FD_PATCH_OFFSET) {
        return {spec.offset};
    }
    std::vector<uint32_t> matches;
    if (spec.location == FD_PATCH_FILTER) {
        if (!spec.filter) {
            throw std::runtime_error("FILTER requires a scan callback");
        }
        for (uint32_t offset = 0; offset < symbol.size; ++offset) {
            const FDPatchScan scan{sizeof(scan),           symbol.name.c_str(), symbol.address,
                                   symbol.original.data(), symbol.size,         offset};
            if (spec.filter(&scan, spec.filterUserdata)) {
                matches.push_back(offset);
            }
        }
    } else if (spec.location == FD_PATCH_CALL) {
        const auto* called = find(spec.calledSymbol);
        if (!called) {
            throw std::runtime_error("CALL target symbol was not found");
        }
        for (uint32_t offset = 0; offset < symbol.size;) {
            hde32s instruction{};
            const auto length = decode(symbol, offset, instruction);
            if (!length) {
                throw std::runtime_error("cannot decode CALL search range");
            }
            uintptr_t destination = 0;
            if (instruction.opcode == 0xe8 && !(instruction.flags & F_PREFIX_66)) {
                destination = symbol.address + offset + length + int32_t(instruction.imm.imm32);
            } else if (instruction.opcode == 0xff && instruction.modrm == 0x15) {
                // Absolute indirect call through an import-address-table slot.
                const auto slot = reinterpret_cast<const void*>(instruction.disp.disp32);
                SIZE_T read{};
                if (!ReadProcessMemory(GetCurrentProcess(), slot, &destination, sizeof(destination),
                                       &read) ||
                    read != sizeof(destination)) {
                    destination = 0;
                }
            }
            if (destination && destination == called->address) {
                matches.push_back(offset);
            }
            offset += length;
        }
    } else {
        throw std::runtime_error("unknown patch selector");
    }
    if (matches.empty() || (spec.expectedMatches && matches.size() != spec.expectedMatches)) {
        throw std::runtime_error("patch selector matched " + std::to_string(matches.size()) +
                                 " locations; expected " + std::to_string(spec.expectedMatches));
    }
    return matches;
}

int FD_CALL registerPatch(const FDModContext* owner, const FDPatchSpec* spec) {
    try {
        if (!owner || owner != registering || !spec || spec->structSize != sizeof(FDPatchSpec)) {
            return fail("patches may only be declared during their owner's FDEntry");
        }
        const auto* symbol = find(spec->symbol);
        if (!symbol) {
            return fail("symbol not found through export/PDB lookup or consumer definitions");
        }
        if (!symbol->size) {
            return fail("symbol has no function extent; provide a verified DefineSymbol signature");
        }
        if (spec->type == FD_PATCH_DETOUR) {
            if (spec->location != FD_PATCH_START || !spec->detour || !spec->original) {
                return fail("detours require Start, replacement, and original output");
            }
        } else if (spec->type != FD_PATCH_INJECT || !spec->callback) {
            return fail("missing callback or unsupported patch type");
        }
        if (bool(spec->retainUserdata) != bool(spec->releaseUserdata)) {
            return fail("userdata retain/release callbacks must be paired");
        }
        const auto offsets = selectOffsets(*symbol, *spec);
        for (auto offset : offsets) {
            if (!boundary(*symbol, offset)) {
                return fail("selected offset must be an instruction boundary inside the symbol");
            }
        }
        std::shared_ptr<CallbackLifetime> lifetime;
        if (spec->retainUserdata) {
            lifetime = std::make_shared<CallbackLifetime>();
            spec->retainUserdata(spec->userdata);
            lifetime->userdata = spec->userdata;
            lifetime->release = spec->releaseUserdata;
        }
        for (auto offset : offsets) {
            pending.push_back({symbol, offset, *spec, lifetime});
        }
        return FD_SUCCESS;
    } catch (const std::exception& e) {
        return fail(e.what());
    } catch (...) {
        return fail("patch selector threw during registration");
    }
}

int FD_CALL defineSymbol(const FDModContext* owner, const FDSymbolPattern* spec) {
    try {
        if (!owner || owner != registering || !spec || spec->structSize != sizeof(*spec)) {
            return fail("symbols may only be defined during their owner's FDEntry");
        }
        bool inserted{};
        definePattern(*spec, inserted);
        if (inserted) {
            definedSymbols.emplace_back(spec->name);
        }
        return FD_SUCCESS;
    } catch (const std::exception& e) {
        return fail(e.what());
    } catch (...) {
        return fail("cannot define symbol");
    }
}

int FD_CALL findSymbol(const char* name, FDSymbolInfo* output) {
    try {
        const auto* symbol = find(name);
        if (!symbol || !output || output->structSize != sizeof(FDSymbolInfo)) {
            return FD_FAILURE;
        }
        *output = {sizeof(*output), symbol->name.c_str(), symbol->address, symbol->size};
        return FD_SUCCESS;
    } catch (const std::exception& exception) {
        error = exception.what();
        return FD_FAILURE;
    } catch (...) {
        error = "symbol lookup failed";
        return FD_FAILURE;
    }
}

uint32_t FD_CALL countSymbols() {
    return symbolCount();
}

int FD_CALL getSymbol(uint32_t index, FDSymbolInfo* output) {
    auto symbol = symbolAt(index);
    return symbol ? findSymbol(symbol->name.c_str(), output) : FD_FAILURE;
}

const FDPatchRegistry patchApi{
    sizeof(patchApi), FD_NATIVE_API_VERSION, registerPatch, findSymbol,
    lastError,        countSymbols,          getSymbol,     defineSymbol};
const FDNativeApi nativeApi{sizeof(nativeApi), FD_NATIVE_API_VERSION, engineApi(), &patchApi};
} // namespace

const FDNativeApi* api() {
    return &nativeApi;
}

const char* lastError() {
    return error.c_str();
}

void beginEntry(const FDModContext* context) {
    registering = context;
    pending.clear();
    definedSymbols.clear();
    invalidEntry = false;
    error.clear();
}

bool endEntry(bool success) {
    const auto owner = registering;
    registering = nullptr;
    if (!success || invalidEntry) {
        if (owner && owner->log && !error.empty()) {
            owner->log(FD_LOG_ERROR, error.c_str());
        }
        pending.clear();
        for (const auto& name : definedSymbols) {
            eraseSymbol(name);
        }
        definedSymbols.clear();
        return false;
    }
    std::lock_guard<std::mutex> lock(registryMutex);
    std::map<uintptr_t, std::unique_ptr<Router>> created;
    std::map<Router*, std::shared_ptr<std::vector<Subscription>>> updated;

    struct Output {
        void** location;
        void* value;
        void* previous;
    };

    std::vector<Output> outputs;
    auto activation = std::make_shared<std::atomic<bool>>(false);
    const auto previousSpans = patchSpans.load();
    try {
        auto status = MH_Initialize();
        if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED)
            throw std::runtime_error("cannot initialize patch backend");
        if (!returnStub && std::any_of(pending.begin(), pending.end(), [](auto& request) {
                return request.spec.location == FD_PATCH_END;
            }))
            returnStub = makeStub(nullptr);
        for (auto& request : pending) {
            if (!integrity(*request.symbol))
                throw std::runtime_error(
                    "engine symbol was modified outside the loader patch registry");
            auto address = request.symbol->address + request.offset;
            Router* router = nullptr;
            if (auto found = routers.find(address); found != routers.end())
                router = found->second.get();
            if (auto found = created.find(address); found != created.end())
                router = found->second.get();
            const bool detour = request.spec.type == FD_PATCH_DETOUR;
            if (router && (router->detour || detour))
                throw std::runtime_error("detour conflicts with another patch at this location");
            if (!router) {
                auto span = overwriteSpan(*request.symbol, request.offset);
                auto overlap = [&](const auto& entries) {
                    for (auto& pair : entries)
                        if (address < pair.first + pair.second->span && pair.first < address + span)
                            return true;
                    return false;
                };
                if (overlap(routers) || overlap(created))
                    throw std::runtime_error("patch overlaps an existing instruction span");
                auto node = std::make_unique<Router>();
                node->symbol = request.symbol;
                node->address = address;
                node->span = span;
                node->boundaries.resize(request.symbol->size);
                for (uint32_t offset = 0; offset < request.symbol->size;) {
                    node->boundaries[offset] = true;
                    hde32s instruction{};
                    auto length = decode(*request.symbol, offset, instruction);
                    if (!length) {
                        throw std::runtime_error("invalid function instruction");
                    }
                    offset += length;
                }
                node->detour = detour;
                router = node.get();
                if (!detour)
                    node->stub = makeStub(router);
                auto replacement = detour ? request.spec.detour : node->stub;
                created.emplace(address, std::move(node));
                status = MH_CreateHook(reinterpret_cast<void*>(address), replacement,
                                       &router->trampoline);
                if (status != MH_OK)
                    throw std::runtime_error(std::string("instruction relocation failed: ") +
                                             MH_StatusToString(status));
                router->backendCreated = true;
            }
            if (detour)
                outputs.push_back(
                    {request.spec.original, router->trampoline, *request.spec.original});
            else {
                auto& list = updated[router];
                if (!list)
                    list = std::make_shared<std::vector<Subscription>>(*router->subscribers.load());
                list->push_back({owner, request.spec.location, request.spec.type,
                                 request.spec.callback, request.spec.userdata, activation,
                                 request.lifetime});
            }
        }
        for (auto& change : updated)
            if (created.count(change.first->address)) {
                std::shared_ptr<const std::vector<Subscription>> list = change.second;
                change.first->subscribers.store(std::move(list));
            }
        for (auto& pair : created) {
            pair.second->installed.resize(pair.second->span);
            if (MH_QueueEnableHook(reinterpret_cast<void*>(pair.first)) != MH_OK)
                throw std::runtime_error("cannot queue patch activation");
        }
        auto nextSpans = std::make_shared<PatchSpans>(*previousSpans);
        for (const auto& pair : created) {
            nextSpans->emplace_back(pair.first, pair.second->span);
        }
        patchSpans.store(nextSpans);
        // Detours may run as soon as MinHook resumes other threads.
        for (auto& output : outputs)
            *output.location = output.value;
        if (!created.empty() && MH_ApplyQueued() != MH_OK)
            throw std::runtime_error("cannot activate patch transaction");
        for (auto& pair : created) {
            auto bytes = reinterpret_cast<const unsigned char*>(pair.first);
            std::memcpy(pair.second->installed.data(), bytes, pair.second->span);
        }
        for (auto& change : updated) {
            std::shared_ptr<const std::vector<Subscription>> list = change.second;
            change.first->subscribers.store(std::move(list));
        }
        routers.merge(created);
        activation->store(true);
        pending.clear();
        definedSymbols.clear();
        return true;
    } catch (const std::exception& e) {
        error = e.what();
    } catch (...) {
        error = "patch transaction failed";
    }
    for (auto& pair : created)
        if (pair.second->backendCreated) {
            MH_DisableHook(reinterpret_cast<void*>(pair.first));
            MH_RemoveHook(reinterpret_cast<void*>(pair.first));
        }
    patchSpans.store(previousSpans);
    for (auto& output : outputs)
        *output.location = output.previous;
    pending.clear();
    for (const auto& name : definedSymbols) {
        eraseSymbol(name);
    }
    definedSymbols.clear();
    if (owner && owner->log)
        owner->log(FD_LOG_ERROR, error.c_str());
    return false;
}
#ifdef FD_NATIVE_TESTING
void removeTestPatches() {
    std::lock_guard<std::mutex> lock(registryMutex);
    for (auto& pair : routers)
        MH_DisableHook(reinterpret_cast<void*>(pair.first));
    for (auto& pair : routers)
        MH_RemoveHook(reinterpret_cast<void*>(pair.first));
    routers.clear();
    patchSpans.store(std::make_shared<const PatchSpans>());
    returns.clear();
}
#endif
} // namespace fd::native
