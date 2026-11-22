#ifndef FIREDRAGON_ENGINE_H
#define FIREDRAGON_ENGINE_H
#include "FireDragonFields.h"

#define FD_NATIVE_API_VERSION 5u

typedef enum FDMethodValueKind {
    FD_METHOD_BOOLEAN,
    FD_METHOD_SIGNED,
    FD_METHOD_UNSIGNED,
    FD_METHOD_FLOAT,
    FD_METHOD_POINTER,
    FD_METHOD_STRING
} FDMethodValueKind;

typedef struct FDMethodValue {
    FDMethodValueKind kind;

    union {
        int boolean;
        int64_t signedValue;
        uint64_t unsignedValue;
        double floatValue;
        const void* pointer;
        const char* string;
    } value;
} FDMethodValue;

typedef struct FDMethodInfo {
    const char* name;
    const char* declaringType;
    const char* signature;
    const char* source;
    const char* symbol;
    int callable;
} FDMethodInfo;

/* Runtime services for generated engine classes. Field properties are generated
   from the catalog; this table contains no hand-maintained property facade. */
typedef struct FDEngineApi {
    uint32_t structSize, apiVersion;
    const char*(FD_CALL* profile)();
    const FDFieldsApi* fields;
    int(FD_CALL* invoke)(const char* symbol, FDObjectRef receiver, const FDMethodValue* arguments,
                         uint32_t count, FDMethodValue* result);
    uint32_t(FD_CALL* methodCount)(uint32_t type);
    const FDMethodInfo*(FD_CALL* methodAt)(uint32_t type, uint32_t index);
} FDEngineApi;
#endif
