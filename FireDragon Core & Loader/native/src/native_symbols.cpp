#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dbghelp.h>
#include "native_runtime.hpp"
#include <algorithm>
#include <charconv>
#include <filesystem>
#include <map>
#include <mutex>
#include <optional>
#include <sstream>
#include <span>
#include <stdexcept>

namespace fd::native {
namespace {
std::recursive_mutex symbolsMutex;
std::map<std::string, Symbol> symbols;

uint32_t fingerprint(std::span<const unsigned char> bytes) {
    uint32_t result = 2166136261u;
    for (auto byte : bytes) {
        result = (result ^ byte) * 16777619u;
    }
    return result;
}

bool executableRange(uintptr_t address, size_t size) {
    if (!address || address + size < address) {
        return false;
    }
    const auto end = address + std::max<size_t>(size, 1);
    while (address < end) {
        MEMORY_BASIC_INFORMATION region{};
        if (!VirtualQuery(reinterpret_cast<void*>(address), &region, sizeof(region)) ||
            region.State != MEM_COMMIT || (region.Protect & PAGE_GUARD) ||
            !(region.Protect &
              (PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY))) {
            return false;
        }
        address = reinterpret_cast<uintptr_t>(region.BaseAddress) + region.RegionSize;
    }
    return true;
}

Symbol* remember(const std::string& name, uintptr_t address, uint32_t size) {
    if (!executableRange(address, size)) {
        throw std::runtime_error("symbol does not describe readable executable memory");
    }
    Symbol value{name, address, size, {}};
    auto bytes = reinterpret_cast<const unsigned char*>(address);
    value.original.assign(bytes, bytes + size);
    return &symbols.emplace(name, std::move(value)).first->second;
}

// A private symbol-handler session avoids borrowing a game's/crash reporter's
// session. All calls are serialized; DbgHelp is not thread safe.
class DebugSymbols {
    HMODULE library_{};
    HANDLE process_{};
    decltype(&SymInitialize) initialize_{};
    decltype(&SymLoadModuleEx) load_{};
    decltype(&SymFromName) find_{};
    std::map<HMODULE, bool> loaded_;

  public:
    DebugSymbols() {
        wchar_t directory[MAX_PATH]{};
        if (!GetSystemDirectoryW(directory, MAX_PATH)) {
            return;
        }
        auto path = std::filesystem::path(directory) / "dbghelp.dll";
        library_ = LoadLibraryW(path.c_str());
        if (!library_) {
            return;
        }
        initialize_ =
            reinterpret_cast<decltype(initialize_)>(GetProcAddress(library_, "SymInitialize"));
        load_ = reinterpret_cast<decltype(load_)>(GetProcAddress(library_, "SymLoadModuleEx"));
        find_ = reinterpret_cast<decltype(find_)>(GetProcAddress(library_, "SymFromName"));
        HANDLE current = GetCurrentProcess();
        if (!initialize_ || !load_ || !find_ ||
            !DuplicateHandle(current, current, current, &process_, 0, FALSE,
                             DUPLICATE_SAME_ACCESS)) {
            return;
        }
        if (!initialize_(process_, nullptr, FALSE)) {
            CloseHandle(process_);
            process_ = nullptr;
        }
        // Library and session intentionally remain alive for the process lifetime.
    }

    std::optional<std::pair<uintptr_t, uint32_t>> Find(HMODULE module, const std::string& name) {
        if (!process_) {
            return std::nullopt;
        }
        char filename[32768]{};
        if (!GetModuleFileNameA(module, filename, sizeof(filename))) {
            return std::nullopt;
        }
        if (!loaded_.contains(module)) {
            const auto base = reinterpret_cast<uintptr_t>(module);
            load_(process_, nullptr, filename, nullptr, base, 0, nullptr, 0);
            loaded_[module] = true;
        }
        alignas(SYMBOL_INFO) unsigned char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME]{};
        auto symbol = reinterpret_cast<SYMBOL_INFO*>(buffer);
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen = MAX_SYM_NAME;
        auto qualified = std::filesystem::path(filename).stem().string() + "!" + name;
        if (!find_(process_, qualified.c_str(), symbol) ||
            symbol->ModBase != reinterpret_cast<uintptr_t>(module)) {
            return std::nullopt;
        }
        return std::pair{uintptr_t(symbol->Address), symbol->Size};
    }
};

const Symbol* reflect(const std::string& qualified) {
    auto separator = qualified.find('!');
    const auto moduleName =
        separator == std::string::npos ? std::string{} : qualified.substr(0, separator);
    const auto name = separator == std::string::npos ? qualified : qualified.substr(separator + 1);
    auto module = GetModuleHandleA(moduleName.empty() ? nullptr : moduleName.c_str());
    if (!module || name.empty()) {
        return nullptr;
    }
    static DebugSymbols debug;
    auto information = debug.Find(module, name);
    auto exported = GetProcAddress(module, name.c_str());
    if (!information && !exported) {
        return nullptr;
    }
    const auto address = information ? information->first : reinterpret_cast<uintptr_t>(exported);
    const auto size = information ? information->second : 0;
    HMODULE pinned{};
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<const char*>(address), &pinned)) {
        return nullptr;
    }
    return remember(qualified, address, size);
}

std::vector<std::optional<unsigned char>> parsePattern(const char* pattern) {
    if (!pattern) {
        throw std::runtime_error("missing symbol signature");
    }
    std::istringstream input(pattern);
    std::vector<std::optional<unsigned char>> result;
    bool concrete = false;
    for (std::string token; input >> token;) {
        if (token == "??" || token == "?") {
            result.push_back(std::nullopt);
            continue;
        }
        unsigned value{};
        auto parsed = std::from_chars(token.data(), token.data() + token.size(), value, 16);
        if (token.size() != 2 || parsed.ec != std::errc{} || parsed.ptr != token.data() + 2 ||
            value > 255) {
            throw std::runtime_error("signature must contain hex bytes or ?? wildcards");
        }
        concrete = true;
        result.push_back(static_cast<unsigned char>(value));
    }
    if (!concrete) {
        throw std::runtime_error("empty or all-wildcard symbol signature");
    }
    return result;
}

bool matches(std::span<const unsigned char> bytes,
             const std::vector<std::optional<unsigned char>>& pattern) {
    if (bytes.size() < pattern.size()) {
        return false;
    }
    for (size_t i = 0; i < pattern.size(); ++i) {
        if (pattern[i] && bytes[i] != *pattern[i]) {
            return false;
        }
    }
    return true;
}
} // namespace

bool addBinding(const char* name, uintptr_t address, uint32_t size, uint32_t expected) {
    std::lock_guard lock(symbolsMutex);
    if (!executableRange(address, size)) {
        return false;
    }
    auto bytes = std::span(reinterpret_cast<const unsigned char*>(address), size);
    if (expected && fingerprint(bytes) != expected) {
        return false;
    }
    remember(name, address, size);
    return true;
}

bool definePattern(const FDSymbolPattern& spec, bool& inserted) {
    std::lock_guard lock(symbolsMutex);
    inserted = false;
    if (!spec.name || !*spec.name || !spec.size) {
        throw std::runtime_error("symbol signature requires a name and verified function size");
    }
    auto pattern = parsePattern(spec.pattern);
    if (pattern.size() > spec.size) {
        throw std::runtime_error("signature exceeds the supplied function extent");
    }
    auto module = GetModuleHandleA(spec.module);
    if (!module) {
        throw std::runtime_error("signature module is not loaded");
    }
    auto base = reinterpret_cast<const unsigned char*>(module);
    auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    auto pe = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    const auto moduleBegin = reinterpret_cast<uintptr_t>(base);
    const auto moduleEnd = moduleBegin + pe->OptionalHeader.SizeOfImage;
    if (auto found = symbols.find(spec.name); found != symbols.end() && found->second.size) {
        const auto& existing = found->second;
        if (existing.address < moduleBegin || existing.address >= moduleEnd ||
            existing.size != spec.size || !matches(existing.original, pattern) ||
            (spec.fingerprint && fingerprint(existing.original) != spec.fingerprint)) {
            throw std::runtime_error("symbol definition conflicts with an existing range");
        }
        return true;
    }
    uintptr_t match{};
    auto section = IMAGE_FIRST_SECTION(pe);
    for (unsigned i = 0; i < pe->FileHeader.NumberOfSections; ++i) {
        if (!(section[i].Characteristics & IMAGE_SCN_MEM_EXECUTE)) {
            continue;
        }
        const auto size = section[i].Misc.VirtualSize;
        const auto rva = section[i].VirtualAddress;
        if (rva > pe->OptionalHeader.SizeOfImage || size > pe->OptionalHeader.SizeOfImage - rva ||
            size < spec.size) {
            continue;
        }
        auto bytes = std::span(base + rva, size);
        if (!executableRange(reinterpret_cast<uintptr_t>(bytes.data()), bytes.size())) {
            continue;
        }
        for (uint32_t offset = 0; offset <= size - spec.size; ++offset) {
            if (!matches(bytes.subspan(offset), pattern)) {
                continue;
            }
            if (match) {
                throw std::runtime_error("symbol signature is ambiguous");
            }
            match = reinterpret_cast<uintptr_t>(bytes.data() + offset);
        }
    }
    if (!match) {
        throw std::runtime_error("symbol signature was not found");
    }
    auto bytes = std::span(reinterpret_cast<const unsigned char*>(match), spec.size);
    if (spec.fingerprint && fingerprint(bytes) != spec.fingerprint) {
        throw std::runtime_error(
            "symbol function fingerprint differs from the consumer's expectation");
    }
    if (auto previous = symbols.find(spec.name); previous != symbols.end()) {
        if (previous->second.address != match) {
            throw std::runtime_error("signature disagrees with reflected symbol address");
        }
        previous->second.size = spec.size;
        previous->second.original.assign(bytes.begin(), bytes.end());
    } else {
        remember(spec.name, match, spec.size);
        inserted = true;
    }
    HMODULE pinned{};
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                       reinterpret_cast<const char*>(match), &pinned);
    return true;
}

void eraseSymbol(const std::string& name) {
    std::lock_guard lock(symbolsMutex);
    symbols.erase(name);
}

const Symbol* find(const char* name) {
    std::lock_guard lock(symbolsMutex);
    if (!name || !*name) {
        return nullptr;
    }
    auto found = symbols.find(name);
    return found == symbols.end() ? reflect(name) : &found->second;
}

uint32_t symbolCount() {
    std::lock_guard lock(symbolsMutex);
    return uint32_t(symbols.size());
}

const Symbol* symbolAt(uint32_t index) {
    std::lock_guard lock(symbolsMutex);
    if (index >= symbols.size()) {
        return nullptr;
    }
    auto found = symbols.begin();
    std::advance(found, index);
    return &found->second;
}
#ifdef FD_NATIVE_TESTING
void testEngineProfile();

void testProfile(std::vector<Symbol> entries) {
    std::lock_guard lock(symbolsMutex);
    symbols.clear();
    testEngineProfile();
    for (auto& symbol : entries) {
        const auto* bytes = reinterpret_cast<const unsigned char*>(symbol.address);
        symbol.original.assign(bytes, bytes + symbol.size);
        symbols.emplace(symbol.name, std::move(symbol));
    }
}
#endif
} // namespace fd::native
