#ifndef FIREDRAGON_LOADER_H
#define FIREDRAGON_LOADER_H
#include <stdint.h>
#include <stddef.h>

#define FD_API_VERSION 5u
#define FD_CALL __cdecl
#define FD_EXPORT __declspec(dllexport)
#ifdef __cplusplus
#define FD_EXTERN_C extern "C"
#else
#define FD_EXTERN_C extern
#endif

enum FDLogLevel { FD_LOG_INFO = 0, FD_LOG_WARNING = 1, FD_LOG_ERROR = 2 };

enum FDResult { FD_SUCCESS = 0, FD_FAILURE = 1 };

typedef void(FD_CALL* FDLogFunction)(int level, const char* message);
typedef struct FDModContext FDModContext;
typedef struct FDNativeApi FDNativeApi;
typedef struct FDLuaCall FDLuaCall;

enum FDLuaType {
    FD_LUA_OTHER = -1,
    FD_LUA_NIL = 0,
    FD_LUA_BOOLEAN = 1,
    FD_LUA_NUMBER = 3,
    FD_LUA_STRING = 4,
    FD_LUA_TABLE = 5
};

/* The loader owns the Lua state. Callbacks use this facade rather than linking
   another Lua runtime. Strings returned by string() are borrowed for this call. */
typedef struct FDLuaStack {
    uint32_t structSize, apiVersion;
    int(FD_CALL* argumentCount)(FDLuaCall*);
    int(FD_CALL* argumentType)(FDLuaCall*, int index);
    int(FD_CALL* boolean)(FDLuaCall*, int index);
    double(FD_CALL* number)(FDLuaCall*, int index);
    const char*(FD_CALL* string)(FDLuaCall*, int index);
    void(FD_CALL* pushNil)(FDLuaCall*);
    void(FD_CALL* pushBoolean)(FDLuaCall*, int value);
    void(FD_CALL* pushNumber)(FDLuaCall*, double value);
    void(FD_CALL* pushString)(FDLuaCall*, const char* value);
    int(FD_CALL* pushJson)(FDLuaCall*, const char* json);
} FDLuaStack;

/* Return the number of pushed results, or a negative value for failure.
   Do not throw across the ABI. userdata remains owned by the component. */
typedef int(FD_CALL* FDLuaFunction)(const FDLuaStack*, FDLuaCall*, void* userdata);

typedef struct FDLuaRegistry {
    uint32_t structSize, apiVersion;
    int(FD_CALL* createTable)(const FDModContext*, const char* path);
    int(FD_CALL* setJson)(const FDModContext*, const char* path, const char* json);
    int(FD_CALL* registerFunction)(const FDModContext*, const char* path, FDLuaFunction function,
                                   void* userdata);
} FDLuaRegistry;

/* Borrowed, immutable pointers remain valid until the game process exits.
   No C++ objects, allocator ownership or exceptions may cross this ABI. */
struct FDModContext {
    uint32_t structSize;
    uint32_t apiVersion;
    const char* modName;
    const wchar_t* modDirectory;
    FDLogFunction log;
    /* Registration is permitted during this component's FDEntry call only.
       Paths are relative to FireDragonLoader.Mods.<modName>, e.g. Config.Size.
       Successful entry registrations are published in every Lua state. */
    const FDLuaRegistry* lua;
    const FDNativeApi* native;
};

typedef int(FD_CALL* FDModEntry)(const FDModContext* context);

/* Example: FD_MOD_ENTRY(ModularShields, EngineHooks) { return FD_SUCCESS; }
   Exports the exact, case-sensitive name FDEntryModularShieldsEngineHooks. */
#define FD_MOD_ENTRY(modName, dllName)                                                             \
    FD_EXTERN_C FD_EXPORT int FD_CALL FDEntry##modName##dllName(const FDModContext* context)
#endif
