#include "native_runtime.hpp"
#include "FireDragonFields.hpp"
#include <cstring>

namespace fd::native {
namespace {
using Bridge = int (*)(const Symbol&, FDObjectRef, const FDMethodValue*, uint32_t, FDMethodValue*);

struct MethodRow {
    uint32_t type;
    const FDMethodInfo* methods;
    uint32_t count;
};

struct MethodBinding {
    const char* symbol;
    uint32_t owner;
    Bridge bridge;
};

int invokeEntityCategory(const Symbol& symbol, FDObjectRef object, const FDMethodValue* arguments,
                         uint32_t count, FDMethodValue* output) {
    if (count != 1 || !arguments || arguments[0].kind != FD_METHOD_STRING ||
        !arguments[0].value.string)
        return FD_FAILURE;
    auto api = fieldsApi();
    FireDragon::FAF::Native::Entity entity(api, object.address);
    if (!entity.BluePrint().Dereference() || !entity.SimulationRef().Dereference())
        return FD_FAILURE;

    // Only the loader marshals the engine's MSVC string ABI. This descriptor
    // borrows its bytes and never transfers a C++ allocator or ownership.
    struct EngineString {
        uint32_t allocator{};

        union Storage {
            char buffer[16];
            const char* pointer;

            Storage() : buffer{} {}
        } storage;

        uint32_t length{}, capacity{};
    };

    static_assert(sizeof(EngineString) == 28);
    EngineString text;
    auto name = arguments[0].value.string;
    text.length = uint32_t(std::strlen(name));
    if (text.length < sizeof(text.storage.buffer)) {
        std::memcpy(text.storage.buffer, name, text.length + 1);
        text.capacity = 15;
    } else {
        text.storage.pointer = name;
        text.capacity = text.length;
    }
    uintptr_t result = reinterpret_cast<uintptr_t>(&text);
    auto receiver = object.address;
    auto function = symbol.address;
    // Verified native ABI: ECX = Entity*, EAX = borrowed engine string.
    asm volatile("call *%[function]"
                 : "+a"(result), "+c"(receiver)
                 : [function] "r"(function)
                 : "edx", "memory", "cc");
    output->kind = FD_METHOD_BOOLEAN;
    output->value.boolean = (result & 0xff) != 0;
    return FD_SUCCESS;
}

int invokeThiscallPointer(const Symbol& symbol, FDObjectRef object, const FDMethodValue*,
                          uint32_t count, FDMethodValue* output) {
    if (count)
        return FD_FAILURE;
    using Function = const void*(__attribute__((thiscall))*)(const void*);
    output->kind = FD_METHOD_POINTER;
    output->value.pointer = reinterpret_cast<Function>(symbol.address)(object.address);
    return FD_SUCCESS;
}

#include "generated/native_methods.inc"

uint32_t FD_CALL methodCount(uint32_t type) {
    for (const auto& row : methodRows)
        if (row.type == type)
            return row.count;
    return 0;
}

const FDMethodInfo* FD_CALL methodAt(uint32_t type, uint32_t index) {
    for (const auto& row : methodRows)
        if (row.type == type)
            return index < row.count ? &row.methods[index] : nullptr;
    return nullptr;
}

int FD_CALL invoke(const char* name, FDObjectRef receiver, const FDMethodValue* arguments,
                   uint32_t count, FDMethodValue* output) {
    if (!profile() || !name || !receiver.address || !output)
        return FD_FAILURE;
    const auto* symbol = find(name);
    if (!symbol)
        return FD_FAILURE;
    for (const auto& binding : bindings) {
        if (std::strcmp(name, binding.symbol))
            continue;
        auto object = fieldsApi()->cast(receiver, binding.owner);
        return object.address ? binding.bridge(*symbol, object, arguments, count, output)
                              : FD_FAILURE;
    }
    return FD_FAILURE;
}

const FDEngineApi engine{sizeof(engine), FD_NATIVE_API_VERSION, profile, fieldsApi(),
                         invoke,         methodCount,           methodAt};
} // namespace

const FDEngineApi* engineApi() {
    return &engine;
}
} // namespace fd::native
