#include "../native/src/native_runtime.hpp"
#include "FireDragonPatches.hpp"
#include "MinHook.h"
#include <windows.h>
#include <atomic>
#include <cassert>
#include <cstring>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

static_assert(__cplusplus >= 202400L, "Native tests must run in C++26 mode");

extern "C" FD_EXPORT __attribute__((naked, noinline)) int FD_CALL ReflectedExample(int) {
    asm volatile("nop; nop; nop; nop; nop; mov 4(%esp), %eax; add $7,%eax; ret");
}

namespace {
std::atomic<unsigned> starts{}, ends{};

FDHookResult FD_CALL start(FDHookContext* context, void*) {
    assert(context->registers->esp);
    ++starts;
    return FD_HOOK_CONTINUE;
}

FDHookResult FD_CALL finish(FDHookContext* context, void*) {
    ++ends;
    context->registers->eax += 10;
    return FD_HOOK_CONTINUE;
}

FDHookResult FD_CALL observeEnd(FDHookContext*, void*) {
    ++ends;
    return FD_HOOK_CONTINUE;
}

FDHookResult FD_CALL offset(FDHookContext* context, void*) {
    context->registers->eax += 3;
    return FD_HOOK_CONTINUE;
}

FDHookResult FD_CALL reject(FDHookContext* context, void*) {
    return FireDragon::Hook(context).ResumeAt(6);
}

int FD_CALL selectFirstByte(const FDPatchScan* scan, void*) {
    return scan->offset == 0;
}

FDHookResult FD_CALL disturbFloatingPoint(FDHookContext*, void*) {
    asm volatile("fldz; pxor %%xmm0,%%xmm0" ::: "xmm0", "memory");
    return FD_HOOK_CONTINUE;
}

int FD_CALL replacement(int value) {
    return value * 3;
}

struct Code {
    unsigned char* memory = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));

    explicit Code(std::initializer_list<unsigned char> bytes) {
        assert(memory);
        std::memcpy(memory, bytes.begin(), bytes.size());
    }

    ~Code() {
        fd::native::removeTestPatches();
        VirtualFree(memory, 0, MEM_RELEASE);
    }

    void relative(unsigned operand, unsigned target) {
        const int32_t displacement = int32_t(target) - int32_t(operand + 4);
        std::memcpy(memory + operand, &displacement, sizeof(displacement));
    }

    void profile(unsigned size) {
        fd::native::testProfile({{"MethodA", reinterpret_cast<uintptr_t>(memory), size, {}}});
    }
};

FDModContext owner{sizeof(owner), FD_API_VERSION, "NativeTests",    nullptr,
                   nullptr,       nullptr,        fd::native::api()};

void begin() {
    fd::native::beginEntry(&owner);
}

void commit() {
    if (!fd::native::endEntry(true)) {
        std::cerr << fd::native::lastError() << '\n';
        std::abort();
    }
}

void testLocationsAndChains() {
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0x8b, 0x44, 0x24, 0x04, 0x05, 0x01, 0, 0, 0, 0xc3};
    code.profile(15);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(code.memory);
    assert(function(5) == 6);
    begin();
    FireDragon::Patches patches(&owner);
    assert(patches.Start("MethodA", start));
    assert(patches.Offset("MethodA", 9, offset));
    assert(patches.End("MethodA", finish));
    commit();
    assert(function(5) == 19 && starts == 1 && ends == 1);
    begin();
    assert(patches.Start("MethodA", start));
    commit();
    assert(function(5) == 19 && starts == 3 && ends == 2);
    fd::native::removeTestPatches();
    assert(function(5) == 6);
}

void testRelocationsAndRejection() {
    // A relative call is stolen into the trampoline. The semantic filter can
    // instead branch to the named, instruction-aligned rejection path.
    Code code{0xe8, 0, 0, 0, 0, 0xc3, 0xb8, 0x63, 0, 0, 0, 0xc3};
    const unsigned char helper[] = {0xb8, 7, 0, 0, 0, 0xc3};
    std::memcpy(code.memory + 64, helper, sizeof(helper));
    code.relative(1, 64);
    code.profile(12);
    auto function = reinterpret_cast<int(FD_CALL*)()>(code.memory);
    assert(function() == 7);
    begin();
    assert(FireDragon::Patches(&owner).Start("MethodA", start));
    commit();
    assert(function() == 7);
    begin();
    assert(FireDragon::Patches(&owner).Filter("MethodA", selectFirstByte, reject));
    commit();
    assert(function() == 99);
    fd::native::removeTestPatches();
    assert(function() == 7);
    // The stolen near conditional branch points outside the overwritten span.
    Code conditional{0x85, 0xc0, 0x0f, 0x84, 1, 0, 0, 0, 0xc3, 0xb8, 42, 0, 0, 0, 0xc3};
    conditional.profile(15);
    begin();
    assert(FireDragon::Patches(&owner).Start("MethodA", start));
    commit();
    auto call = [&](unsigned input) {
        unsigned output;
        asm volatile("call *%2"
                     : "=a"(output)
                     : "a"(input), "r"(conditional.memory)
                     : "ecx", "edx", "memory", "cc");
        return output;
    };
    assert(call(0) == 42 && call(9) == 9);
}

int FD_CALL selectAdd(const FDPatchScan* scan, void*) {
    const unsigned char pattern[]{0x05, 0x01, 0, 0, 0};
    return FireDragon::PatchScan(scan).Matches(pattern);
}

int FD_CALL selectEveryNop(const FDPatchScan* scan, void*) {
    return scan->bytes[scan->offset] == 0x90;
}

int FD_CALL selectInsideInstruction(const FDPatchScan* scan, void*) {
    return scan->offset == 1;
}

int FD_CALL selectNothing(const FDPatchScan*, void*) {
    return false;
}

int FD_CALL throwingSelector(const FDPatchScan*, void*) {
    throw std::runtime_error("selector failed");
}

FDHookResult FD_CALL invalidRedirect(FDHookContext* context, void*) {
    return FireDragon::Hook(context).ResumeAt(0xffffffffu);
}

void testDynamicFilters() {
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0x8b, 0x44, 0x24, 0x04, 0x05, 0x01, 0, 0, 0, 0xc3};
    code.profile(15);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(code.memory);
    const FireDragon::Patches patches(&owner);
    begin();
    assert(patches.Filter("MethodA", selectAdd, offset));
    commit();
    assert(function(5) == 9);
    // Scanning still sees original bytes after another mod has installed a hook.
    begin();
    assert(patches.Filter("MethodA", selectAdd, offset));
    commit();
    assert(function(5) == 12);
    fd::native::removeTestPatches();
    begin();
    assert(!patches.Filter("MethodA", selectNothing, start));
    assert(!fd::native::endEntry(true));
    begin();
    assert(!patches.Filter("MethodA", selectEveryNop, start));
    assert(!fd::native::endEntry(true));
    begin();
    assert(patches.Filter("MethodA", selectEveryNop, start, nullptr, nullptr, 5));
    assert(!fd::native::endEntry(true)); // Matching locations overlap their five-byte spans.
    assert(function(5) == 6);
    begin();
    assert(!patches.Filter("MethodA", throwingSelector, start));
    assert(!fd::native::endEntry(true));
    begin();
    assert(patches.Start("MethodA", invalidRedirect));
    commit();
    assert(function(5) == 6); // Invalid redirects retain the original continuation.
    fd::native::removeTestPatches();
    Code unaligned{0xb8, 1, 0, 0, 0, 0xc3};
    unaligned.profile(6);
    begin();
    assert(!patches.Filter("MethodA", selectInsideInstruction, start));
    assert(!fd::native::endEntry(true));
}

void testCallSelectors() {
    // The immediate operand also contains E8: only actual decoded CALLs match.
    Code code{0xb8, 0xe8, 0, 0, 0, 0xe8, 0, 0, 0, 0, 0xe8, 0, 0, 0, 0, 0xc3};
    const unsigned char helper[]{0xb8, 7, 0, 0, 0, 0xc3};
    std::memcpy(code.memory + 64, helper, sizeof(helper));
    code.relative(6, 64);
    code.relative(11, 64);
    fd::native::testProfile({{"Caller", reinterpret_cast<uintptr_t>(code.memory), 16, {}},
                             {"Callee", reinterpret_cast<uintptr_t>(code.memory + 64), 6, {}}});
    auto function = reinterpret_cast<int(FD_CALL*)()>(code.memory);
    const FireDragon::Patches patches(&owner);
    begin();
    assert(!patches.Call("Caller", "Callee", start)); // Two calls are ambiguous by default.
    assert(!fd::native::endEntry(true));
    const auto priorStarts = starts.load();
    begin();
    assert(patches.Call("Caller", "Callee", start, nullptr, 2));
    commit();
    assert(function() == 7 && starts == priorStarts + 2);
    fd::native::removeTestPatches();
    begin();
    assert(!patches.Call("Caller", "Missing", start));
    assert(!fd::native::endEntry(true));
    unsigned boundCalls = 0;
    begin();
    assert(patches.Call("Caller", "Callee", FireDragon::CallWith([&] { ++boundCalls; }), 2));
    commit();
    assert(function() == 7 && boundCalls == 2);
    fd::native::removeTestPatches();
    // IAT-style indirect CALL resolves the pointer stored in the absolute slot.
    Code indirect{0xff, 0x15, 0, 0, 0, 0, 0xc3};
    std::memcpy(indirect.memory + 64, helper, sizeof(helper));
    auto slot = reinterpret_cast<uintptr_t>(indirect.memory + 96);
    auto callee = reinterpret_cast<uintptr_t>(indirect.memory + 64);
    std::memcpy(indirect.memory + 2, &slot, 4);
    std::memcpy(indirect.memory + 96, &callee, 4);
    fd::native::testProfile({{"Caller", reinterpret_cast<uintptr_t>(indirect.memory), 7, {}},
                             {"Callee", callee, 6, {}}});
    begin();
    assert(patches.Call("Caller", "Callee", start));
    commit();
    assert(reinterpret_cast<int(FD_CALL*)()>(indirect.memory)() == 7);
}

void testReflectionAndConsumerSymbols() {
    fd::native::testProfile({});
    const FireDragon::Patches patches(&owner);
    const auto reflected = patches.FindSymbol("ReflectedExample");
    assert(reflected && reflected->address == reinterpret_cast<uintptr_t>(&ReflectedExample));
    assert(ReflectedExample(3) == 10);
    begin();
    assert(patches.DefineSymbol("ReflectedExample", "90 90 90 90 90 8B 44 24 04 83 C0 07 C3", 13));
    assert(patches.Start("ReflectedExample", start));
    assert(patches.End("ReflectedExample", finish));
    commit();
    assert(ReflectedExample(3) == 20);
    fd::native::removeTestPatches();
    begin();
    assert(patches.DefineSymbol("ConsumerAlias", "90 90 90 90 90 8B 44 24 04 83 C0 07 C3", 13));
    assert(!fd::native::endEntry(false));
    assert(!patches.FindSymbol("ConsumerAlias")); // Failed entry discards its definitions.
    begin();
    assert(
        !patches.DefineSymbol("BadFingerprint", "90 90 90 90 90 8B 44 24 04 83 C0 07 C3", 13, 1));
    assert(!fd::native::endEntry(true));
    begin();
    assert(!patches.DefineSymbol("BadPattern", "?? ??", 13));
    assert(!fd::native::endEntry(true));
    begin();
    assert(!patches.DefineSymbol("InvalidPattern", "ZZ", 13));
    assert(!fd::native::endEntry(true));
    begin();
    assert(!patches.DefineSymbol("AmbiguousPattern", "90", 13));
    assert(!fd::native::endEntry(true));
    begin();
    assert(!patches.DefineSymbol("MissingPattern", "01 23 45 67 89 AB CD EF 98 76 54 32 10", 13));
    assert(!fd::native::endEntry(true));
    assert(!patches.FindSymbol("Missing.dll!Absent"));
}

void testPdbReflection(const char* filename) {
    auto module = LoadLibraryA(filename);
    assert(module);
    assert(!GetProcAddress(module, "DebugOnly"));
    const FireDragon::Patches patches(&owner);
    const auto symbol = patches.FindSymbol("SymbolFixture.dll!DebugOnly");
    assert(symbol && symbol->size >= 5);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(symbol->address);
    assert(function(3) == 20);
    begin();
    assert(patches.Start("SymbolFixture.dll!DebugOnly", start));
    assert(patches.End("SymbolFixture.dll!DebugOnly", finish));
    commit();
    assert(function(3) == 30);
    fd::native::removeTestPatches();
    std::cout << "PASS: real PDB reflection resolves and patches a non-exported DLL function\n";
}

std::atomic<unsigned> typedCalls{};

int __stdcall twice(int value) {
    ++typedCalls;
    return value * 2;
}

bool isSeven(int value) {
    ++typedCalls;
    return value == 7;
}

void testTypedScalarBindings() {
    using namespace FireDragon;
    // EAX contains the input when the selected five NOPs are reached.
    Code code{0x8b, 0x44, 0x24, 0x04, 0x90, 0x90, 0x90, 0x90, 0x90, 0xc3, 0xb8, 99, 0, 0, 0, 0xc3};
    code.profile(16);
    const unsigned char site[]{0x90, 0x90, 0x90, 0x90, 0x90};
    const unsigned char rejected[]{0xb8, 99, 0, 0, 0, 0xc3};
    const Patches patches(&owner);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(code.memory);
    begin();
    assert(patches.Filter("MethodA", AtBytes(site),
                          CallWith(twice, From<int>(Register::Eax)).StoreResult(Register::Eax)));
    commit();
    assert(function(7) == 14);
    fd::native::removeTestPatches();
    begin();
    assert(patches.Filter("MethodA", AtBytes(site),
                          CallWith(isSeven, Stack<int>(4)).OnFalse(ContinueAt(rejected))));
    commit();
    assert(function(7) == 7 && function(8) == 99);
    fd::native::removeTestPatches();
    begin();
    assert(patches.End("MethodA",
                       CallWith(twice, From<int>(Register::Eax)).StoreResult(Register::Eax)));
    commit();
    assert(function(7) == 14);
    fd::native::removeTestPatches();
    begin();
    assert(patches.Offset("MethodA", 4,
                          CallWith(twice, From<int>(Register::Eax)).StoreResult(Register::Eax)));
    commit();
    assert(function(7) == 14);
    fd::native::removeTestPatches();
    // Custom scanning callbacks use the same typed adapter as byte patterns.
    begin();
    assert(patches.Filter("MethodA", selectFirstByte,
                          CallWith(isSeven, Stack<int>(4)).OnFalse(ContinueAt(rejected))));
    commit();
    assert(function(7) == 7 && function(8) == 99);
    fd::native::removeTestPatches();
    // An invalid indirect argument skips the callback and continues safely.
    const auto before = typedCalls.load();
    begin();
    assert(patches.Filter("MethodA", AtBytes(site),
                          CallWith(twice, From<int*>(Register::Eax).Dereference())));
    commit();
    assert(function(1) == 1 && typedCalls == before);
    fd::native::removeTestPatches();
    // Floating stack values and register bit patterns retain their meaning.
    float captured{};
    begin();
    assert(patches.Start("MethodA",
                         CallWith([&](float value) { captured = value; }, Stack<float>(4))));
    commit();
    reinterpret_cast<void(FD_CALL*)(float)>(code.memory)(3.5f);
    assert(captured == 3.5f);
    fd::native::removeTestPatches();
    begin();
    assert(patches.Filter(
        "MethodA", AtBytes(site),
        CallWith([&](float value) { captured = value; }, From<float>(Register::Eax))));
    commit();
    reinterpret_cast<void(FD_CALL*)(float)>(code.memory)(2.25f);
    assert(captured == 2.25f);
}

void testBoundCallbackLifetime() {
    using namespace FireDragon;
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0x8b, 0x44, 0x24, 0x04, 0xc3};
    code.profile(10);
    const Patches patches(&owner);
    std::weak_ptr<int> lifetime;
    {
        auto owned = std::make_shared<int>(0);
        lifetime = owned;
        begin();
        assert(patches.Start("MethodA",
                             CallWith([owned](int value) { *owned = value; }, Stack<int>(4))));
        commit();
    }
    assert(!lifetime.expired());
    assert(reinterpret_cast<int(FD_CALL*)(int)>(code.memory)(7) == 7);
    assert(*lifetime.lock() == 7);
    fd::native::removeTestPatches();
    assert(lifetime.expired());
    {
        auto owned = std::make_shared<int>(0);
        lifetime = owned;
        begin();
        assert(patches.Start("MethodA", CallWith([owned] { ++*owned; })));
        assert(!fd::native::endEntry(false));
    }
    assert(lifetime.expired());
    {
        auto owned = std::make_shared<int>(0);
        lifetime = owned;
        begin();
        const unsigned char missing[]{0xcc, 0xcc, 0xcc};
        assert(!patches.Filter("MethodA", AtBytes(missing), CallWith([owned] { ++*owned; })));
        assert(!fd::native::endEntry(true));
    }
    assert(lifetime.expired());
}

bool unitArgumentPolicy(const FireDragon::FAF::Unit& worker, const FireDragon::FAF::Unit& target) {
    ++typedCalls;
    return worker && target && worker.Id() == 111 && target.Id() == 222;
}

void testTypedEngineArguments() {
    using namespace FireDragon;
    // Load task and target registers independently of the typed callback ABI.
    Code code{0x8b, 0x4c, 0x24, 0x04, 0x8b, 0x54, 0x24, 0x08, 0x90, 0x90, 0x90, 0x90, 0x90,
              0xb8, 7,    0,    0,    0,    0xc3, 0xb8, 99,   0,    0,    0,    0xc3};
    code.profile(25);
    unsigned char task[0x24]{}, worker[0x6a8]{}, target[0x6a8]{};
    const auto workerAddress = reinterpret_cast<uintptr_t>(worker);
    std::memcpy(task + 0x1c, &workerAddress, 4);
    const int workerId = 111, targetId = 222;
    std::memcpy(worker + 0x70, &workerId, 4);
    std::memcpy(target + 0x70, &targetId, 4);
    const unsigned char site[]{0x90, 0x90, 0x90, 0x90, 0x90};
    const unsigned char rejected[]{0xb8, 99, 0, 0, 0, 0xc3};
    begin();
    assert(Patches(&owner).Filter(
        "MethodA", AtBytes(site),
        CallWith(
            unitArgumentPolicy,
            From<FAF::CCommandTask>(Register::Ecx).Member<&FAF::CCommandTask::Unit>().Dereference(),
            From<FAF::Unit>(Register::Edx))
            .OnFalse(ContinueAt(rejected))));
    commit();
    auto function = reinterpret_cast<int(FD_CALL*)(void*, void*)>(code.memory);
    assert(function(task, target) == 7);
    assert(function(task, worker) == 99);
    assert(function(nullptr, target) == 99);
    assert(function(task, nullptr) == 99);
}

void testAllReturnsAndStackCleanup() {
    Code code{0x8b, 0x44, 0x24, 0x04, 0x85, 0xc0, 0x74, 0x06, 0x83, 0xc0, 0x01,
              0xc2, 0x04, 0,    0xb8, 42,   0,    0,    0,    0xc2, 0x04, 0};
    code.profile(22);
    auto function = reinterpret_cast<int(__stdcall*)(int)>(code.memory);
    begin();
    assert(FireDragon::Patches(&owner).End("MethodA", finish));
    commit();
    assert(function(0) == 52 && function(5) == 16);
}

void testRecursiveAndThreadedReturns() {
    Code code{0x8b, 0x44, 0x24, 0x04, 0x85, 0xc0, 0x74, 0x0d, 0x48, 0x50, 0xe8, 0,
              0,    0,    0,    0x83, 0xc4, 0x04, 0x40, 0xc3, 0x90, 0x31, 0xc0, 0xc3};
    code.relative(11, 0);
    code.profile(24);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(code.memory);
    assert(function(3) == 3);
    ends = 0;
    begin();
    assert(FireDragon::Patches(&owner).End("MethodA", observeEnd));
    commit();
    auto run = [&] {
        for (int i = 0; i < 100; ++i)
            assert(function(3) == 3);
    };
    std::thread first(run), second(run);
    first.join();
    second.join();
    assert(ends == 800);
}

void testFloatingPointPreservation() {
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0xc3};
    code.profile(6);
    begin();
    assert(FireDragon::Patches(&owner).Start("MethodA", disturbFloatingPoint));
    commit();
    const float input = 3.5f;
    float output = 0;
    double x87 = 0;
    asm volatile("fld1; movss %2,%%xmm0; call *%3; movss %%xmm0,%0; fstpl %1"
                 : "=m"(output), "=m"(x87)
                 : "m"(input), "r"(code.memory)
                 : "eax", "ecx", "edx", "xmm0", "memory", "cc");
    assert(output == input && x87 == 1.0);
    unsigned savedEax = 0, savedEcx = 0, savedEdx = 0;
    unsigned char carry = 0;
    auto function = code.memory;
    asm volatile("mov $123,%%eax; mov $456,%%ecx; mov $789,%%edx; stc; call *%4; mov %%eax,%0; mov "
                 "%%ecx,%1; mov %%edx,%2; setc %3"
                 : "=m"(savedEax), "=m"(savedEcx), "=m"(savedEdx), "=m"(carry)
                 : "m"(function)
                 : "eax", "ecx", "edx", "memory", "cc");
    assert(savedEax == 123 && savedEcx == 456 && savedEdx == 789 && carry);
}

void testTransactionsAndConflicts() {
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0x8b, 0x44, 0x24, 0x04, 0x05, 0x01, 0, 0, 0, 0xc3};
    code.profile(15);
    auto function = reinterpret_cast<int(FD_CALL*)(int)>(code.memory);
    FireDragon::Patches patches(&owner);
    begin();
    assert(patches.Start("MethodA", start));
    assert(!patches.Offset("MethodA", 6, start));
    assert(!fd::native::endEntry(true));
    assert(function(5) == 6);
    begin();
    assert(patches.Start("MethodA", start));
    assert(!fd::native::endEntry(false));
    assert(function(5) == 6);
    void* original = nullptr;
    begin();
    assert(patches.Detour("MethodA", reinterpret_cast<void*>(replacement), &original));
    commit();
    assert(function(5) == 15 && reinterpret_cast<int(FD_CALL*)(int)>(original)(5) == 6);
    begin();
    assert(patches.Start("MethodA", start));
    assert(!fd::native::endEntry(true));
    assert(function(5) == 15);
    fd::native::removeTestPatches();
    assert(function(5) == 6);
    // A backend record created outside the registry must not be removed when
    // our own CreateHook fails with ALREADY_CREATED.
    void* externalOriginal = nullptr;
    assert(MH_CreateHook(code.memory, reinterpret_cast<void*>(replacement), &externalOriginal) ==
           MH_OK);
    begin();
    assert(patches.Start("MethodA", start));
    assert(!fd::native::endEntry(true));
    assert(MH_EnableHook(code.memory) == MH_OK && function(5) == 15);
    assert(MH_DisableHook(code.memory) == MH_OK && MH_RemoveHook(code.memory) == MH_OK &&
           function(5) == 6);
    begin();
    assert(patches.Start("MethodA", start));
    assert(patches.Offset("MethodA", 1, offset));
    assert(!fd::native::endEntry(true));
    assert(function(5) == 6); // Overlap rolls back prepared hooks.
    begin();
    assert(patches.Start("MethodA", start));
    assert(patches.Offset("MethodA", 9, offset));
    // This pair is adjacent, not overlapping: both are supported.
    commit();
    assert(function(5) == 9);
    fd::native::removeTestPatches();
    code.memory[0] = 0xcc;
    begin();
    assert(patches.Start("MethodA", start));
    assert(!fd::native::endEntry(true));
    code.memory[0] = 0x90;
    assert(!patches.Start("MethodA", start)); // Entry-only registration.
    begin();
    assert(!patches.Start("Missing", start));
    assert(!fd::native::endEntry(true));
}

void testSymbolMetadataAndTypedViews() {
    Code code{0x90, 0x90, 0x90, 0x90, 0x90, 0xc3};
    code.profile(6);
    auto registry = fd::native::api()->patches;
    assert(registry->symbolCount() == 1);
    FDSymbolInfo info{sizeof(info), nullptr, 0, 0};
    assert(registry->symbolAt(0, &info) == FD_SUCCESS && info.size == 6 &&
           std::strcmp(info.name, "MethodA") == 0);
    // Independent ABI fixtures: seed the documented x86 fields and read them
    // through public views, including the Unit -> Entity base adjustment.
    unsigned char unit[0x6a8]{}, army[0x288]{}, simulation[0xaf8]{}, blueprint[0x568]{};
    auto put = [](void* object, size_t offset, auto value) {
        std::memcpy(static_cast<unsigned char*>(object) + offset, &value, sizeof(value));
    };
    put(unit, 0x70, uint32_t(111));
    put(unit, 0x74, reinterpret_cast<void*>(blueprint));
    put(unit, 0x98, 50.f);
    put(unit, 0x9c, 100.f);
    put(unit, 0xa0, uint8_t(1));

    struct Position {
        float x, y, z;
    };

    put(unit, 0xb4, Position{1, 2, 3});
    put(unit, 0x150, reinterpret_cast<void*>(simulation));
    put(unit, 0x154, reinterpret_cast<void*>(army));
    put(army, 8, int(2));
    put(simulation, 0x900, uint32_t(123));
    std::memcpy(blueprint + 12, "ueb0101", 8);
    put(blueprint, 28, uint32_t(7));
    put(blueprint, 32, uint32_t(15));
    FireDragon::FAF::Unit view(fd::native::api()->engine, reinterpret_cast<void*>(unit));
    assert(view.Id() == 111 && view.VarDat().IsBeingBuilt());
    assert(view.VarDat().Health() == 50 && view.VarDat().MaxHealth() == 100);
    assert(view.VarDat().CurTransform().Pos().Z() == 3);
    assert(view.ArmyRef().Get().ConstDat().ArmyIndex() == 2);
    assert(view.SimulationRef().Get().CurTick() == 123);
    assert((*view.SimulationRef()).CurTick() == view.SimulationRef().Get().CurTick());
    auto maybeSimulation = view.SimulationRef().TryGet();
    static_assert(
        std::is_same_v<decltype(maybeSimulation), std::optional<FireDragon::FAF::Simulation>>);
    assert(maybeSimulation.has_value() && maybeSimulation->CurTick() == 123);
    assert(maybeSimulation.transform([](auto simulation) { return simulation.CurTick(); })
               .value_or(0) == 123);
    FireDragon::FAF::Pointer<FireDragon::FAF::Simulation> absent;
    assert(!*absent && !absent.Get());
    assert(!absent.TryGet().has_value());
    bool destroyed = true;
    put(unit, 0x60, &destroyed);
    assert(*view.DestroyFlag() && view.DestroyFlag().Get());
    destroyed = false;
    auto maybeDestroyed = view.DestroyFlag().TryGet();
    assert(maybeDestroyed.has_value() && !*maybeDestroyed);
    put(unit, 0x60, reinterpret_cast<void*>(1));
    assert(!view.DestroyFlag().TryGet());
    put(unit, 0x60, &destroyed);
    unsigned char resources[4]{};
    put(simulation, 0x8d0, resources);
    auto shared = (*view.SimulationRef()).SimResources();
    assert((*shared).Address() == resources && shared.Get().Address() == resources);
    assert(shared.TryGet()->Address() == resources);
    put(simulation, 0x8d0, static_cast<void*>(nullptr));
    assert(!shared.TryGet());
    put(simulation, 0x8d0, resources);
    assert(view.BluePrint().Get().BlueprintId().Text() == "ueb0101");
    assert(view.AsEntity().Address() == unit + 8 && view.AsEntity().Id() == 111);
    static_assert(
        std::is_same_v<decltype(view.GetBlueprint().Get()), FireDragon::FAF::UnitBlueprint>);
    static_assert(std::is_enum_v<decltype(view.VarDat().LayerMask())>);
    FireDragon::FAF::Native::Unit fields(fd::native::api()->engine->fields, unit);
    assert(fields.id_().Read() == 111);
    assert(fields.mVarDat().mHealth().Read() == view.VarDat().Health());
    assert(fields.mVarDat().mCurTransform().pos_().z().Read() ==
           view.VarDat().CurTransform().Pos().Z());
    assert(fields.SimulationRef().Dereference().mCurTick().Read() == 123);
    assert(fields.ArmyRef().Dereference().mConstDat().mArmyIndex().Read() == 2);
    assert(view.BluePrint().Get().BlueprintId().Text() == "ueb0101");
    put(unit, 0x294, 0.75f);
    assert(fields.mUnitVarDat().mFuelRatio().Read() == 0.75f);
    assert(view.UnitVarDat().FuelRatio() == 0.75f);
    int commands[]{7, 11, 23};
    put(unit, 0x320, commands);
    put(unit, 0x324, commands + 3);
    assert(fields.mUnitVarDat().mCommands().Count() == 3);
    assert(fields.mUnitVarDat().mCommands().At(1).Read() == 11);
    assert(view.UnitVarDat().Commands().At(1) == 11);
    assert(fields.mVarDat().mCurTransform().pos_().m_afTuple().Count() == 3);
    assert(fields.mVarDat().mCurTransform().pos_().m_afTuple().At(2).Read() == 3);
    assert(!fields.mVarDat().mCurTransform().pos_().m_afTuple().At(3));
    bool outOfRange = false;
    try {
        view.VarDat().CurTransform().Pos().AfTuple().At(3);
    } catch (const std::runtime_error&) {
        outOfRange = true;
    }
    assert(outOfRange);
    void* attached[]{reinterpret_cast<void*>(unit)};
    put(unit, 0x188, attached);
    put(unit, 0x18c, attached + 1);
    auto children = fields.mAttachedEntities();
    assert(children.Count() == 1 && children.At(0).Dereference().Address() == unit);
    // Native pointers are borrowed: null and unreadable pointees fail safely.
    put(unit, 0x150, reinterpret_cast<void*>(1));
    uint32_t tick = 0;
    assert(!fields.SimulationRef().Dereference().mCurTick().TryRead(tick));
    assert(!fields.SimulationRef().Dereference().mCurTick().TryRead<uint32_t>());
    put(unit, 0x150, static_cast<void*>(nullptr));
    assert(!fields.SimulationRef().Dereference());
    assert(!view.SimulationRef().TryGet());
    put(unit, 0x150, simulation);
    put(simulation, 0x900, uint32_t(0));
    auto maybeTick = fields.SimulationRef().Dereference().mCurTick().TryRead<uint32_t>();
    assert(maybeTick.has_value() && *maybeTick == 0);
    assert(!fields.Field("missing").TryRead<uint32_t>());
    assert(!fields.Field("id_").TryRead<uint64_t>());
    put(simulation, 0x900, uint32_t(123));
    auto catalog = fd::native::api()->engine->fields;
    assert(catalog->typeCount() > 1000);
    unsigned fieldCount = 0;
    for (uint32_t i = 0; i < catalog->typeCount(); ++i) {
        auto type = catalog->typeAt(i);
        assert(type && catalog->typeById(type->id) == type &&
               catalog->findType(type->name) == type);
        for (uint32_t j = 0; j < type->fieldCount; ++j) {
            auto member = catalog->fieldAt(type->id, j);
            auto memberType = catalog->typeById(member->type);
            assert(memberType && member->offset + memberType->size <= type->size);
            ++fieldCount;
        }
    }
    assert(fieldCount > 5000 && !catalog->typeAt(catalog->typeCount()));
    assert(!catalog->findField(fields.Type()->id, "weakLinkHead_", nullptr));
    assert(!catalog->findType("moho::SMsgReceiverLinkage")->layoutKnown);
    assert(!fields.Field("missing") && !fields.Field("weakLinkHead_"));
    assert(fields.Field("id_").Read<int32_t>() == 111);
    uint64_t wrongSize = 0;
    assert(!fields.Field("id_").TryRead(wrongSize));
    const char* longId = "long_blueprint_identifier";
    put(blueprint, 12, longId);
    put(blueprint, 32, uint32_t(std::strlen(longId)));
    put(blueprint, 28, uint32_t(std::strlen(longId)));
    assert(view.BluePrint().Get().BlueprintId().Text() == longId);
    // Actual machine-code fixtures verify generated calls and base adjustments.
    const unsigned char methods[] = {0x8b, 0x41, 0x74, 0xc3, 0x90, 0x90, 0x90, 0x90, 0x8d, 0x81,
                                     0xb4, 0,    0,    0,    0xc3, 0x90, 0x8d, 0x81, 0xa4, 0,
                                     0,    0,    0xc3, 0x90, 0x8b, 0x41, 0x68, 0xc3};
    std::memcpy(code.memory, methods, sizeof(methods));
    auto address = reinterpret_cast<uintptr_t>(code.memory);
    fd::native::testProfile({{"Moho::Unit::GetBlueprint", address, 4, {}},
                             {"Moho::Unit::GetPosition", address + 8, 7, {}},
                             {"Moho::Unit::GetTransform", address + 16, 7, {}},
                             {"Moho::Entity::IsInCategory", address + 24, 4, {}}});
    assert(view.GetBlueprint().Get().BlueprintId().Text() == longId);
    assert((*view.GetBlueprint()).BlueprintId().Text() == longId);
    assert(view.GetBlueprint().TryGet()->BlueprintId().Text() == longId);
    assert(view.GetPosition().X() == 1 && view.GetTransform().Pos().Z() == 3);
    assert(view.IsInCategory("SILO") && view.AsEntity().IsInCategory("SILO"));
    assert(view.MethodCount() > 4);
    bool callable = false, unavailable = false;
    for (uint32_t i = 0; i < view.MethodCount(); ++i) {
        auto method = view.MethodInfo(i);
        assert(method && method->signature && method->declaringType);
        callable |= method->callable != 0;
        unavailable |= method->callable == 0;
    }
    assert(callable && unavailable);
}
} // namespace

int main(int argc, char** argv) {
    testLocationsAndChains();
    testRelocationsAndRejection();
    testDynamicFilters();
    testCallSelectors();
    testReflectionAndConsumerSymbols();
    if (argc > 1) {
        testPdbReflection(argv[1]);
    }
    testTypedScalarBindings();
    testBoundCallbackLifetime();
    testTypedEngineArguments();
    testAllReturnsAndStackCleanup();
    testRecursiveAndThreadedReturns();
    testFloatingPointPreservation();
    testTransactionsAndConflicts();
    testSymbolMetadataAndTypedViews();
    std::cout << "PASS: typed arguments, results and lifetimes; dynamic export reflection, "
                 "consumer signatures, CALL/FILTER selectors, "
                 "Start/Offset/End/detour patches, relative call/Jcc "
                 "relocation, all returns, stdcall cleanup, recursion, thread isolation, x87/XMM "
                 "preservation, chained hooks, rollback, conflicts, complete native field catalog, "
                 "generated nested fields, pointers, arrays, vectors and strings\n";
}
