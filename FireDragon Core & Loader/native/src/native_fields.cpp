#include "native_runtime.hpp"
#include <windows.h>
#include <algorithm>
#include <cstring>
#include <limits>

namespace fd::native {
namespace {
static_assert(sizeof(void*) == 4, "Native field profiles describe the x86 engine ABI");

struct TypeRow {
    FDTypeInfo info;
    const FDFieldInfo* fields;
    const FDBaseInfo* bases;
};

#include "generated/native_fields.inc"

const TypeRow* row(uint32_t id) {
    auto match = std::lower_bound(
        std::begin(sortedTypeRows), std::end(sortedTypeRows), id,
        [](uint32_t index, uint32_t wanted) { return types[index].info.id < wanted; });
    return match != std::end(sortedTypeRows) && types[*match].info.id == id ? &types[*match]
                                                                            : nullptr;
}

bool copy(const void* source, void* result, size_t size) {
    SIZE_T copied = 0;
    const auto active = profile();
#ifdef FD_NATIVE_TESTING
    const bool compatible = active != nullptr;
#else
    const bool compatible = active && std::strcmp(active, "FAF 3841") == 0;
#endif
    return compatible && source && result && size &&
           ReadProcessMemory(GetCurrentProcess(), source, result, size, &copied) && copied == size;
}

const void* advance(const void* address, size_t offset) {
    const auto base = reinterpret_cast<uintptr_t>(address);
    return address && offset <= std::numeric_limits<uintptr_t>::max() - base
               ? reinterpret_cast<const void*>(base + offset)
               : nullptr;
}

uint32_t FD_CALL typeCount() {
    return uint32_t(std::size(types));
}

const FDBaseInfo* FD_CALL baseAt(uint32_t id, uint32_t index) {
    auto type = row(id);
    return type && index < type->info.baseCount ? &type->bases[index] : nullptr;
}

FDObjectRef FD_CALL cast(FDObjectRef object, uint32_t baseType) {
    if (object.type == baseType)
        return object;
    auto type = row(object.type);
    FDObjectRef result{};
    if (type && object.address)
        for (uint32_t i = 0; i < type->info.baseCount; ++i)
            if (type->bases[i].type == baseType) {
                if (result.address)
                    return {}; // Repeated base subobjects need an explicit path.
                result = {advance(object.address, type->bases[i].offset), baseType, 0, 0};
            }
    return result;
}

const FDTypeInfo* FD_CALL typeAt(uint32_t index) {
    return index < std::size(types) ? &types[index].info : nullptr;
}

const FDTypeInfo* FD_CALL typeById(uint32_t id) {
    auto type = row(id);
    return type ? &type->info : nullptr;
}

const FDTypeInfo* FD_CALL findType(const char* name) {
    if (name)
        for (const auto& type : types)
            if (!std::strcmp(type.info.name, name))
                return &type.info;
    return nullptr;
}

const FDFieldInfo* FD_CALL fieldAt(uint32_t id, uint32_t index) {
    auto type = row(id);
    return type && index < type->info.fieldCount ? &type->fields[index] : nullptr;
}

const FDFieldInfo* FD_CALL findField(uint32_t id, const char* name, const char* declaring) {
    auto type = row(id);
    const FDFieldInfo* result = nullptr;
    if (!type || !name)
        return nullptr;
    for (uint32_t i = 0; i < type->info.fieldCount; ++i) {
        const auto& field = type->fields[i];
        if (!std::strcmp(field.name, name) &&
            (!declaring || !std::strcmp(field.declaringType, declaring))) {
            if (result)
                return nullptr;
            result = &field;
        }
    }
    return result;
}

FDObjectRef FD_CALL field(FDObjectRef object, const FDFieldInfo* member) {
    auto type = row(object.type);
    if (type && object.address && member)
        for (uint32_t i = 0; i < type->info.fieldCount; ++i)
            if (member == &type->fields[i])
                return {advance(object.address, member->offset), member->type, member->bitOffset,
                        member->bitWidth};
    return {};
}

int FD_CALL read(FDObjectRef object, void* result, uint32_t size) {
    auto type = row(object.type);
    return type && type->info.layoutKnown && !object.bitWidth && size == type->info.size &&
                   copy(object.address, result, size)
               ? FD_SUCCESS
               : FD_FAILURE;
}

FDObjectRef FD_CALL dereference(FDObjectRef object) {
    auto type = row(object.type);
    const void* target = nullptr;
    if (type && (type->info.kind == FD_FIELD_POINTER || type->info.kind == FD_FIELD_SHARED) &&
        copy(object.address, &target, sizeof(target)))
        return {target, type->info.elementType, 0, 0};
    return {};
}

bool pointerField(FDObjectRef object, const char* name, const void*& result) {
    auto value = field(object, findField(object.type, name, nullptr));
    return read(value, &result, sizeof(result)) == FD_SUCCESS;
}

struct Sequence {
    const void* begin{};
    uint32_t size{}, element{};
};

Sequence sequence(FDObjectRef object) {
    auto type = row(object.type);
    if (!type)
        return {};
    if (type->info.kind == FD_FIELD_ARRAY)
        return {object.address, type->info.elementCount, type->info.elementType};
    if (!type->info.elementType)
        return {};
    const void* begin = nullptr;
    const void* end = nullptr;
    // MSVC-compatible fa::vector and native FastVector family descriptors.
    bool valid = pointerField(object, "first_", begin) && pointerField(object, "last_", end);
    if (!valid)
        valid = pointerField(object, "start_", begin) && pointerField(object, "end_", end);
    auto element = row(type->info.elementType);
    const auto first = reinterpret_cast<uintptr_t>(begin);
    const auto last = reinterpret_cast<uintptr_t>(end);
    if (!valid || !element || !element->info.layoutKnown || !element->info.size || last < first ||
        (last - first) % element->info.size)
        return {};
    return {begin, uint32_t((last - first) / element->info.size), type->info.elementType};
}

uint32_t FD_CALL count(FDObjectRef object) {
    return sequence(object).size;
}

FDObjectRef FD_CALL at(FDObjectRef object, uint32_t index) {
    auto values = sequence(object);
    auto element = row(values.element);
    if (!element || index >= values.size)
        return {};
    return {advance(values.begin, size_t(index) * element->info.size), values.element, 0, 0};
}

int FD_CALL readBits(FDObjectRef object, uint64_t* result) {
    if (!result || !object.bitWidth || object.bitWidth > 64 ||
        object.bitOffset + object.bitWidth > 64)
        return FD_FAILURE;
    uint64_t storage = 0;
    const auto size = (object.bitOffset + object.bitWidth + 7) / 8;
    if (!copy(object.address, &storage, size))
        return FD_FAILURE;
    const auto mask = object.bitWidth == 64 ? ~uint64_t(0) : (uint64_t(1) << object.bitWidth) - 1;
    *result = (storage >> object.bitOffset) & mask;
    return FD_SUCCESS;
}

uint32_t FD_CALL text(FDObjectRef object, char* result, uint32_t capacity) {
    auto type = row(object.type);
    if (!type || type->info.kind != FD_FIELD_STRING)
        return 0;
    uint32_t length = 0, reserved = 0;
    auto size = field(object, findField(object.type, "mySize", nullptr));
    auto storage = field(object, findField(object.type, "myRes", nullptr));
    if (read(size, &length, sizeof(length)) != FD_SUCCESS ||
        read(storage, &reserved, sizeof(reserved)) != FD_SUCCESS || length > reserved ||
        length > 16 * 1024 * 1024)
        return 0;
    auto buffer = field(object, findField(object.type, "bx", nullptr)).address;
    if (reserved >= 16) {
        const void* pointer = nullptr;
        if (!copy(buffer, &pointer, sizeof(pointer)))
            return 0;
        buffer = pointer;
    }
    if (result && capacity >= length + 1) {
        if (length && !copy(buffer, result, length))
            return 0;
        result[length] = '\0';
    }
    return length + 1;
}

const FDFieldsApi fields{sizeof(fields),
                         FD_NATIVE_API_VERSION,
                         typeCount,
                         typeAt,
                         findType,
                         typeById,
                         fieldAt,
                         findField,
                         field,
                         dereference,
                         count,
                         at,
                         read,
                         readBits,
                         text,
                         baseAt,
                         cast};
} // namespace

const FDFieldsApi* fieldsApi() {
    return &fields;
}
} // namespace fd::native
