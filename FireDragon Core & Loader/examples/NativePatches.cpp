// A self-contained example patches its own export. No game-specific hook sites.
#include "FireDragonPatches.hpp"
#include "FireDragonLua.hpp"
#include <atomic>

extern "C" FD_EXPORT __attribute__((naked, noinline)) int FD_CALL ExampleWork(int) {
    asm volatile("nop; nop; nop; nop; nop; mov 4(%esp), %eax; add $1,%eax; ret");
}

namespace {
std::atomic<unsigned> visits{}, returns{};
std::atomic<int> lastInput{}, lastOutput{};

void ObserveEntry(int input) {
    lastInput = input;
    ++visits;
}

void ObserveReturn(int result) {
    lastOutput = result;
    ++returns;
}

unsigned VisitCount() {
    return visits.load();
}

unsigned ReturnCount() {
    return returns.load();
}

int LastInput() {
    return lastInput.load();
}

int LastOutput() {
    return lastOutput.load();
}

int Exercise(int value) {
    return ExampleWork(value);
}
} // namespace

FD_MOD_ENTRY(NativeExample, NativePatches) {
    if (!FireDragon::HasNativeApi(context)) {
        return FD_FAILURE;
    }
    const FireDragon::Patches patches(context);
    const FireDragon::Lua::Bindings bindings(context);
    // Export lookup supplies the address. A signature supplies the exact extent
    // on builds without PDB function sizes. Both must identify the same code.
    const auto symbol = patches.FindSymbol("NativePatches.dll!ExampleWork");
    if (!symbol) {
        return FD_FAILURE;
    }
    return patches.DefineSymbol("NativePatches.dll!ExampleWork",
                                "90 90 90 90 90 8B 44 24 04 83 C0 01 C3", 13, 0,
                                "NativePatches.dll") &&
                   patches.Start("NativePatches.dll!ExampleWork",
                                 FireDragon::CallWith(ObserveEntry, FireDragon::Stack<int>(4))) &&
                   patches.End(
                       "NativePatches.dll!ExampleWork",
                       FireDragon::CallWith(ObserveReturn,
                                            FireDragon::From<int>(FireDragon::Register::Eax))) &&
                   bindings.Bind<Exercise>("Exercise") && bindings.Bind<LastInput>("LastInput") &&
                   bindings.Bind<LastOutput>("LastOutput") &&
                   bindings.Bind<VisitCount>("VisitCount") &&
                   bindings.Bind<ReturnCount>("ReturnCount")
               ? FD_SUCCESS
               : FD_FAILURE;
}
