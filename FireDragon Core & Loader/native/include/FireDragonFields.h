#ifndef FIREDRAGON_FIELDS_H
#define FIREDRAGON_FIELDS_H
#include "FireDragonLoader.h"

/* Immutable layout metadata for the active executable profile. Addresses are
   borrowed engine memory; the SDK never constructs or owns engine objects. */
typedef enum FDFieldKind {
    FD_FIELD_OPAQUE,
    FD_FIELD_BOOLEAN,
    FD_FIELD_SIGNED,
    FD_FIELD_UNSIGNED,
    FD_FIELD_FLOAT,
    FD_FIELD_POINTER,
    FD_FIELD_ARRAY,
    FD_FIELD_RECORD,
    FD_FIELD_STRING,
    FD_FIELD_SHARED
} FDFieldKind;

typedef struct FDTypeInfo {
    uint32_t id;
    const char* name;
    FDFieldKind kind;
    uint32_t size, alignment;
    int layoutKnown;
    uint32_t elementType, elementCount, fieldCount, baseCount;
    const char* source;
} FDTypeInfo;

typedef struct FDFieldInfo {
    const char* name;
    uint32_t type, offset, bitOffset, bitWidth;
    const char* declaringType;
    const char* source;
} FDFieldInfo;

typedef struct FDBaseInfo {
    uint32_t type, offset;
} FDBaseInfo;

typedef struct FDObjectRef {
    const void* address;
    uint32_t type;
    uint32_t bitOffset, bitWidth;
} FDObjectRef;

typedef struct FDFieldsApi {
    uint32_t structSize, apiVersion;
    uint32_t(FD_CALL* typeCount)();
    const FDTypeInfo*(FD_CALL* typeAt)(uint32_t index);
    const FDTypeInfo*(FD_CALL* findType)(const char* name);
    const FDTypeInfo*(FD_CALL* typeById)(uint32_t id);
    const FDFieldInfo*(FD_CALL* fieldAt)(uint32_t type, uint32_t index);
    /* An ambiguous inherited name needs declaringType; no arbitrary match. */
    const FDFieldInfo*(FD_CALL* findField)(uint32_t type, const char* name,
                                           const char* declaringType);
    FDObjectRef(FD_CALL* field)(FDObjectRef object, const FDFieldInfo* field);
    FDObjectRef(FD_CALL* dereference)(FDObjectRef object);
    uint32_t(FD_CALL* count)(FDObjectRef object);
    FDObjectRef(FD_CALL* at)(FDObjectRef object, uint32_t index);
    /* Copies exact storage. Bitfields use readBits instead. Returns FD_SUCCESS
       only for readable memory, a known profile and a matching field size. */
    int(FD_CALL* read)(FDObjectRef object, void* result, uint32_t size);
    int(FD_CALL* readBits)(FDObjectRef object, uint64_t* result);
    /* Copies a native string including NUL; reports required capacity. */
    uint32_t(FD_CALL* text)(FDObjectRef object, char* result, uint32_t capacity);
    const FDBaseInfo*(FD_CALL* baseAt)(uint32_t type, uint32_t index);
    FDObjectRef(FD_CALL* cast)(FDObjectRef object, uint32_t baseType);
} FDFieldsApi;
#endif
