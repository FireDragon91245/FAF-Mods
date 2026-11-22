#ifndef FIREDRAGON_PATCHES_H
#define FIREDRAGON_PATCHES_H
#include "FireDragonEngine.h"

typedef enum FDPatchLocation {
    FD_PATCH_START,
    FD_PATCH_END,
    FD_PATCH_CALL,
    FD_PATCH_OFFSET,
    FD_PATCH_FILTER
} FDPatchLocation;

typedef enum FDPatchType { FD_PATCH_INJECT, FD_PATCH_DETOUR } FDPatchType;

typedef enum FDHookResult { FD_HOOK_CONTINUE, FD_HOOK_REDIRECT } FDHookResult;

/* Saved x86 state. Changing esp/stack depth is unsupported. Core also preserves
   x87, MXCSR and XMM registers. Mods declare their hook argument mappings. */
typedef struct FDRegisters {
    uint32_t edi, esi, ebp, esp, ebx, edx, ecx, eax, eflags;
} FDRegisters;

typedef struct FDHookContext {
    uint32_t structSize;
    const char* symbol;
    FDRegisters* registers;
    const FDEngineApi* engine;
    uintptr_t instruction;
    uintptr_t functionAddress;
    uint32_t functionSize;
    /* FD_HOOK_REDIRECT resumes at this instruction-aligned function offset.
       End callbacks cannot redirect. Core validates before transferring control. */
    uint32_t resumeOffset;
    int(FD_CALL* readMemory)(uintptr_t address, void* result, uint32_t size);
} FDHookContext;

typedef FDHookResult(FD_CALL* FDHookCallback)(FDHookContext*, void* userdata);

/* FILTER runs at registration time once per byte of the original function.
   True selects that offset; every selection must be an instruction boundary.
   The immutable buffer is borrowed only for this invocation. */
typedef struct FDPatchScan {
    uint32_t structSize;
    const char* symbol;
    uintptr_t address;
    const unsigned char* bytes;
    uint32_t size;
    uint32_t offset;
} FDPatchScan;

typedef int(FD_CALL* FDPatchFilter)(const FDPatchScan*, void* userdata);

typedef struct FDPatchSpec {
    uint32_t structSize;
    const char* symbol;
    FDPatchLocation location;
    uint32_t offset;
    FDPatchType type;
    FDHookCallback callback;
    void* userdata;
    void* detour;
    void** original;
    const char* calledSymbol;
    FDPatchFilter filter;
    void* filterUserdata;
    /* CALL/FILTER require exactly this many matches. Zero allows any nonzero
       count. Missing, ambiguous and overlapping selections fail the entry. */
    uint32_t expectedMatches;
    /* Optional paired lifetime operations. Core retains userdata for pending
       and installed hooks, releasing it on rollback or subscription removal.
       Both operations must not throw. */
    void(FD_CALL* retainUserdata)(void*);
    void(FD_CALL* releaseUserdata)(void*);
} FDPatchSpec;

typedef struct FDSymbolInfo {
    uint32_t structSize;
    const char* name;
    uintptr_t address;
    uint32_t size;
} FDSymbolInfo;

/* Consumer-owned fallback for stripped code. module is a loaded DLL name, or
   null for the EXE. pattern uses hex bytes and ?? wildcards and must uniquely
   match executable memory. size is the verified function extent. fingerprint
   is optional FNV-1a of the whole original range. */
typedef struct FDSymbolPattern {
    uint32_t structSize;
    const char* name;
    const char* module;
    const char* pattern;
    uint32_t size;
    uint32_t fingerprint;
} FDSymbolPattern;

typedef struct FDPatchRegistry {
    uint32_t structSize, apiVersion;
    int(FD_CALL* registerPatch)(const FDModContext*, const FDPatchSpec*);
    /* Dynamic export/PDB lookup: module!name, or an EXE symbol name. Export-only
       symbols can have size zero. Supply a pattern/extent before patching when
       debug symbols do not describe function bounds. */
    int(FD_CALL* findSymbol)(const char*, FDSymbolInfo*);
    const char*(FD_CALL* lastError)();
    uint32_t(FD_CALL* symbolCount)();
    int(FD_CALL* symbolAt)(uint32_t index, FDSymbolInfo*);
    int(FD_CALL* defineSymbol)(const FDModContext*, const FDSymbolPattern*);
} FDPatchRegistry;

typedef struct FDNativeApi {
    uint32_t structSize, apiVersion;
    const FDEngineApi* engine;
    const FDPatchRegistry* patches;
} FDNativeApi;
#endif
