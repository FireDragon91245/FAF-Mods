# Native engine and patch SDK

Core mod v27 provides native component ABI v5 and native SDK v5. Rebuild native
components against the installed `sdk/` headers. All older native DLLs must be rebuilt;
the shader manifest and Lua networking/storage/UI contracts are unchanged.
Consumers must rebuild against v5; hook memory access and callback lifetime fields changed.

## Ownership and supported engine

Mods declare patches during `FDEntry`. Each mod owns hook locations, matching
patterns, register/stack argument mappings and continuation choices. Core provides
symbol resolution, shared game bindings, executable memory, instruction relocation
and activation. Entry failure discards its declarations.
Patch preparation failure rolls back that component and prevents its Lua API
from being published. Other valid components can still load.

The generic patch resolver discovers names from loaded PE exports and local PDB
symbols through DbgHelp. Use `module.dll!ExactSymbol` to select a DLL; unqualified
names refer to the executable. It never guesses function bounds from the next
export or searches for a substring of a C++ name. The cached symbol listing
contains resolved/defined symbols, rather than an eager list of every symbol.

FAF 3841 is stripped: its internal function names cannot be recovered by reflection.
Consumers can define a uniquely matching executable-byte signature and verified
function extent. Each mod owns its function signatures, injection selectors,
register/stack argument mappings, and continuation choices. Core's patch resolver
contains no mod hook names, offsets or semantic argument adapters.

The separate `engine_profile.cpp` adapter still verifies the FAF executable hash
and supplies the version-specific Lua/engine method ABIs and generated field
layouts. Those are shared game bindings, independent of mod patch selection.
The generic patching API also works in other loaded modules without that profile.

Native components stay loaded until process exit. Patches are installed at entry,
not from gameplay callbacks. Callbacks must not throw, block, or retain engine
objects beyond their lifetime. The API does not support DLL hot-unloading.

## Generated engine types

Include `FireDragonEngine.hpp` for engine types, or `FireDragonPatches.hpp` for
both engine types and hooks. `FireDragonNative.h` and `FireDragonNative.hpp` have
been removed. All engine-specific classes now come from the generator, rather
than a handwritten facade beside a separate set of generated fields.

```cpp
FireDragon::Hook hook(context);
// This consumer verified that ECX contains Unit* at its injection point.
FAF::Unit unit(hook.Engine(), reinterpret_cast<void*>(hook.Registers().ecx));
int32_t id = unit.Id();
auto state = unit.VarDat();               // generated SSTIEntityVariableData
float health = state.Health();
bool construction = state.IsBeingBuilt();
auto simulation = *unit.SimulationRef();
auto tick = simulation.CurTick();
auto army = unit.ArmyRef().Get();
auto nativeIndex = army.ConstDat().ArmyIndex();
auto blueprint = *unit.GetBlueprint(); // generated RUnitBlueprint
std::string description = blueprint.Description().Text();
bool silo = unit.IsInCategory("SILO");
auto position = unit.GetPosition();         // native method, borrowed Vector3
float x = position.X();
for (uint32_t i = 0; i < simulation.ArmiesList().Count(); ++i) {
    auto member = simulation.ArmiesList().At(i).Get();
    auto name = member.ConstDat().ArmyName().Text();
}
```

The generator normalizes field accessors to PascalCase: `id_` becomes `Id`,
`mVarDat` becomes `VarDat`, `pos_` becomes `Pos`, and `x` becomes `X`. It removes
member prefixes (`m` before an uppercase letter, or `m_`) and surrounding
underscores. Native spellings stay intact in the layout catalog and reflection.
Names that collide with generated helpers or constructors receive a `Field`
suffix; native method names remain unchanged. Scalar getters return C++ values
directly; nested records return their generated classes. Native enums become
scoped C++ enums. `Pointer<T>.Get()` and `*pointer` return the same borrowed value;
arrays and native vectors provide `Count()` and `At()`. Native shared-pointer
records expose their storage fields, `Get()`, and `operator*` as well. `fa::string.Text()` copies
its text. Other containers expose their native links and storage fields.

The generated classes are borrowed views, not owning engine allocations. Null
records and pointers are false. Their addresses, and all values referring to
engine objects, remain valid only for the owning object's lifetime. Scalar reads
from null, unreadable, or incompatible storage throw; hooks must contain errors
within their callbacks. A successful read does not extend an object's lifetime.
No compiler-owned STL object or allocator crosses the DLL boundary.

`Unit`, `Entity`, `RBlueprint`, `REntityBlueprint`, `RUnitBlueprint`, `CArmyImpl`,
`Sim`, and all other known records follow the same generated implementation.
Catalog root names such as `Blueprint`, `Army`, and `Simulation` are generated
aliases to those classes, not alternative wrappers. There is no `.Fields()` or
`.Read()` step in ordinary mod code. Native army indices are zero-based; Lua's
army index is that value plus one.

## C++26 and optional values

Core and Repair Station Control build with `-std=c++26` using 32-bit MinGW-w64
GCC 15.2.0. The native suite requires C++26 mode explicitly. This validates our
code against that toolchain's implemented language/library features; GCC's
C++26 implementation remains partial. The loader C ABI and engine layouts are
independent of the C++ language mode.

`std::optional<T>` represents an absent value in the C++ SDK:

```cpp
std::optional<FireDragon::FAF::Simulation> simulation = unit.SimulationRef().TryGet();
if (simulation) {
    auto tick = simulation->CurTick();
}
auto maybeId = unit.Inspect().Field("id_").TryRead<int32_t>();
auto id = maybeId.value_or(0);
```

Pointers and native shared-pointer records provide `TryGet()`. It returns
`std::nullopt` for a null pointer, and also for an unreadable scalar pointee.
For record pointees it checks presence; the returned view retains the engine's
object lifetime and field-read requirements. `Get()` and `operator*` keep their
existing behavior. Reflection's `TryRead<T>()` returns an optional value for an
exact successful read; the existing `TryRead(T&)` overload is also available.
Valid zero and false values remain engaged optionals. Optionals stay inside
the component's C++ code and never cross the loader C ABI or replace native
engine storage layouts.

## Layouts, inheritance, and native methods

The catalog contains 1,466 type descriptors, 5,874 field entries, 37 enum types,
and 15,656 declared method signatures. Fields include known nested/inherited
records, arrays, container storage, shared-pointer lanes, internal pointers,
reserved storage, and polymorphic-subobject vtable pointers. Entries may alias
inherited storage; the counts do not represent unique memory locations.

Generated `AsEntity()` and other unambiguous base conversions use cataloged
native subobject offsets. For example, `Unit.AsEntity()` adjusts to the Entity
base; it never treats a Unit pointer as an unadjusted Entity pointer. This also
applies when invoking an inherited native method.

Callable methods come from `sdk/methods.json`, which declares their native owner,
signature, symbol, verified instruction hash, and calling-convention bridge. The
same metadata generates public class methods, loader dispatch bindings, and
verified engine symbols. The initial callable methods are `Entity::IsInCategory`
and `Unit::GetBlueprint`, `GetPosition`, and `GetTransform`. Their native names
and return types are preserved, including borrowed pointers and references.
Adding a method means adding verified metadata and, when needed, a reusable ABI
bridge; it does not mean editing an engine facade class.

Other recovered signatures remain inspectable through `MethodCount()` and
`MethodInfo(index)`; `callable` explicitly distinguishes verified bindings.
A header declaration alone does not establish the executable's ABI, so the SDK
does not manufacture executable wrappers for unverified methods or vtable slots.
Mod-specific predicates, including strategic missile silo policy, stay in mods.

`Inspect()` provides low-level type/field metadata and read diagnostics when a
mod needs reflection. `Native::View<N>` is the generator's storage implementation,
not a second set of public engine types for mods to mix with a manual facade.
Ambiguous inherited field names remain available through reflection with an
explicit declaring type. The C services are `FDEngineApi` and `FDFieldsApi`;
they provide generic field, cast, method-dispatch, and introspection operations,
rather than a manually maintained table of selected properties.

The complete catalog ships as `sdk/faf3841.fields.json`. Facts were extracted
from faf-re commit `e39c263b85e5a67a12b892ec8bc9893510c6ab57`, including its patched
WildMagic dependency. It records the executable hash and source provenance;
engine implementations are not bundled. `scripts/generate_native_fields.py`
extracts facts; `scripts/render_native_fields.py` renders the storage layer and
runs `scripts/render_engine_types.py` for public types and method bindings.
Regeneration requires clang-format; release builds use the checked-in output
and need neither libclang nor the reference checkout.

103 unresolved descriptors remain explicitly opaque: forward-only engine types,
external compiler-specific internals, or incompatible layouts. Their pointers
remain exposed, while `layoutKnown` is false and no readable layout is invented.
`SMsgReceiverLinkage` and dependent layouts are excluded due to GNU/MSVC base
padding differences. Reserved arrays retain storage whose meaning is unknown.
Memory reads and calls require the verified executable profile. The game fixture
independently checks common fields, native method calls, and base adjustments;
it does not verify every recovered engine field in a running game.

## Registering patches

```cpp
#include "FireDragonPatches.hpp"

FDHookResult FD_CALL Observe(FDHookContext* context, void*) {
    const FireDragon::Hook hook(context);
    const auto& registers = hook.Registers();
    // The consumer decides what ECX, stack slots, etc. mean at this location.
    // For a verified Unit* in ECX:
    FireDragon::FAF::Unit unit(hook.Engine(), reinterpret_cast<void*>(registers.ecx));
    return FD_HOOK_CONTINUE;
}

int FD_CALL SelectInstruction(const FDPatchScan* context, void*) {
    const unsigned char signature[]{0x8b, 0x44, 0x24, 0x04};
    return FireDragon::PatchScan(context).Matches(signature);
}

FD_MOD_ENTRY(MyMod, EngineHooks) {
    if (!FireDragon::HasNativeApi(context)) {
        return FD_FAILURE;
    }
    const FireDragon::Patches patches(context);
    return patches.Start("Example.dll!Work", Observe) &&
           patches.End("Example.dll!Work", Observe) ? FD_SUCCESS : FD_FAILURE;
}
```

| Declaration | Behavior |
|---|---|
| `Start(symbol, callback)` | Injects before original entry instructions. |
| `End(symbol, callback)` | Injects on each normal return, including recursive calls and multiple return instructions. |
| `Call(symbol, calledSymbol, callback)` | Decodes the caller and injects immediately before matching direct relative or absolute IAT-indirect calls. |
| `Offset(symbol, byteOffset, callback)` | Injects at a supplied instruction boundary. |
| `Filter(symbol, scanCallback, callback)` | Calls the scan callback once per byte of the original function during registration; true selects an injection point. |
| `Detour(symbol, replacement, originalOut)` | Replaces entry with an ABI-compatible function and supplies the original trampoline. |

C++ methods use PascalCase. `Call` does not infer register-indirect/vtable call
targets; use `Filter` to identify those instructions from mod-owned patterns.
Callbacks run before the selected instruction. An overwritten CALL is relocated
into the trampoline, so it still executes once when processing continues.

`Call` and `Filter` expect one match by default and fail for missing or ambiguous
matches. Their last argument is `expectedMatches`: a positive value requires that
exact count; zero allows any nonzero count. Every selected location is patched,
subject to instruction-boundary, overlap, relocation and integrity checks.
`Filter` receives `filterUserdata` separately from the installed callback's
`userdata`. Scan callbacks must be deterministic and must not mutate the bytes.
They are not called during gameplay. A thrown scan callback fails the entry.

`Hook` exposes `Registers()`, `Engine()`, `Symbol()` and `Offset()`. It has no
worker, target or named-site concepts. Mods declare their verified register/stack
mappings through `CallWith`, or use the low-level context when needed. Callback userdata remains owned by the
mod and must remain alive while the hook is installed.

Callbacks normally return `FD_HOOK_CONTINUE`. `hook.ResumeAt(functionOffset)`
returns `FD_HOOK_REDIRECT` and requests a continuation inside the same function.
Core validates instruction alignment and rejects destinations inside displaced
patch instructions. A valid redirect ends that site's subscriber chain. End
callbacks may edit saved result registers but cannot redirect. A detour must
match the native ABI; a symbol name alone does not supply a calling convention.

### Typed callbacks and argument declarations

Include `FireDragonPatches.hpp`. The shared `FireDragonPatchBindings.hpp` adapter
lets a mod register its ordinary function with an argument declaration. No
`FDHookContext` callback or per-mod register switch is required:

```cpp
bool IsAssistanceAllowed(const FAF::Unit& worker, const FAF::Unit& target);

const auto worker = From<FAF::CCommandTask>(Register::Edi)
                        .Member<&FAF::CCommandTask::Unit>().Dereference();

patches.Filter(symbol, AtBytes(injectionBytes),
    CallWith(IsAssistanceAllowed, worker, From<FAF::Unit>(Register::Esi))
        .OnFalse(ContinueAt(continuationBytes)));
```

The mod declares which registers and fields mean which arguments at its site.
The Core SDK creates the typed adapter. Core retains its binding data, restores
saved CPU state around invocation and applies the callback's result policy.
Arguments are prepared on each invocation from the current register snapshot;
engine object pointers are borrowed only for that callback.

| Declaration | Argument or result |
|---|---|
| `From<T>(Register::Eax)` | A saved register as an integer/enum of at most 32 bits, raw pointer, float bit pattern, or generated engine view. All eight integer registers are supported. |
| `Stack<T>(byteOffset)` | Reads `T` at saved ESP plus a byte offset. At entry, offset 4 is the first ordinary x86 stack argument. |
| `FromMemory<T>(reg, byteOffset)` | Reads `T` at the address in the saved register plus an offset. For engine views, reads an object pointer from that slot. |
| `.Member<&Type::Getter>()` | Applies a generated field getter to the preceding argument. Projections can be chained. |
| `.Dereference()` | Reads a raw pointer's pointee or calls `Get()` on a generated pointer view. Null chains yield a default/null argument. |
| `.OnFalse(ContinueAt(offset))` | A false bool result requests the specified function-relative continuation. |
| `.OnFalse(ContinueAt(bytes))` | Finds a unique continuation pattern during Filter registration. |
| `.StoreResult(Register::Eax)` | Writes a pointer or integer/enum result of at most 32 bits to a saved register. |

`CallWith` infers the callback signature and checks argument compatibility at
compile time. Its compiler-generated adapter calls the function using its actual
C++ calling convention, including references and declared `__stdcall` functions.
It does not assume that the injected engine location shares that convention.
The default result policy continues execution and discards a non-void result.

Typed callbacks work with all five selectors. `Filter` accepts either `AtBytes`
or the existing custom scan callback alongside `CallWith`. Pattern continuations
are supported for Filter; other selectors use explicit continuation offsets.
End callbacks cannot redirect. Their stack reads use the return-time ESP after
callee cleanup; they do not implicitly recover entry-time stack arguments.
`OnFalse` requires a bool result. `StoreResult` does not imply a function return;
it updates the selected register before execution continues.

Unreadable memory arguments and callback exceptions are logged and retain the
original continuation. Callback captures and argument descriptors are retained
for installed subscriptions, including return frames, and released on failed
registration, transaction rollback or subscription removal. The C ABI uses
paired retain/release operations; allocation and destruction stay in the module
that created the adapter. Lifetime operations must not throw. Raw context-based
callbacks remain available when a mod needs manual CPU-state control.

### Stripped functions and missing function extents

```cpp
// The consumer supplies this signature and verified function size.
patches.DefineSymbol("MyMod::Work", "55 8B EC 83 EC ?? 53 56", verifiedSize,
                     optionalWholeFunctionFnv, "Example.dll");
patches.Filter("MyMod::Work", SelectInstruction, Observe);
```

`DefineSymbol` scans executable sections of a loaded PE module. Null module means
the EXE. Hex bytes and `??` wildcards are supported; signatures must have a
concrete byte and one unique match. The function range must fit executable memory.
An optional FNV-1a fingerprint validates all original function bytes. It is
sensitive to relocation, so consumers must account for their supported image.

A name found through exports may have size zero. You can inspect/call its address,
but patching requires a PDB-provided extent or an explicit consumer signature and
extent. If both reflection and a signature describe a name, their addresses must
agree. No guessed function size is used. Failed entries discard newly defined
symbols and all pending hooks. Modules used by patches are retained for process
lifetime. Private PDB symbol lookup uses a serialized, private DbgHelp session.

The C registry provides `findSymbol`, `symbolCount`, `symbolAt`, `defineSymbol`
and `registerPatch`. There are no predefined injection-site lists. `LastError()`
reports declaration failures; preparation failures are logged after entry returns.

### Installation and execution

Core validates every selection before publishing the component. It decodes whole
x86 instructions with HDE32, checks overlapping spans and branches entering stolen
instructions, then uses MinHook for relocation and patch activation. Compatible
callbacks at one location share a physical hook in registration order. Failed
entries or preparation roll back that component without publishing its Lua API.

Stubs preserve integer registers, EFLAGS, x87 state, MXCSR and XMM registers.
Callbacks receive an aligned stack and empty x87 stack. Editing saved integer
registers is supported; changing ESP/stack depth is not. Floating-point state is
restored. Callback exceptions are caught and retain the original continuation.
Native access violations are not isolated.

End hooks intercept the caller's return address at entry and use a per-thread
recursive return stack. They run after callee stack cleanup, preserving return
values unless the callback changes them. Non-local unwinds do not guarantee End
callbacks. The API does not support hot-unloading DLLs.

`examples/NativePatches.cpp` patches its own exported function and requires no
game-specific injection sites. `tests/native_runtime.cpp` exercises export/PDB
reflection, consumer signature definitions, all five selectors, redirects,
relocation, recursion, threading, CPU-state preservation and transactions. When
Clang and lld-link are present, the build creates a PDB fixture containing a
non-exported function and tests lookup and execution of hooks on that function.
