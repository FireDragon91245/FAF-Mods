#include <windows.h>
#include <cstring>
#include "FireDragonLoader.h"
#ifndef FD_FIXTURE_FAIL
extern "C" __declspec(dllimport) int FDFixtureDependency();
int FD_CALL fixtureLua(const FDLuaStack* api, FDLuaCall* call, void*) {
    api->pushNumber(call,42);
    return 1;
}
FD_MOD_ENTRY(Fixture, EngineHooks) {
    static int calls = 0;
    if (++calls != 1 || !context || context->structSize != sizeof(FDModContext) || context->apiVersion != FD_API_VERSION ||
        std::strcmp(context->modName, "Fixture") || !context->modDirectory || !context->log || !context->lua || FDFixtureDependency() != 42) return FD_FAILURE;
    if (context->lua->setJson(context,"Config","{\"enabled\":true}") != FD_SUCCESS ||
        context->lua->registerFunction(context,"Answer",&fixtureLua,nullptr) != FD_SUCCESS) return FD_FAILURE;
    auto reenter = reinterpret_cast<int(__cdecl*)()>(GetProcAddress(GetModuleHandleW(nullptr), "FDTestReenter"));
    if (!reenter || reenter() != 0) return FD_FAILURE;
    context->log(FD_LOG_INFO, "fixture entry called once; dependency, context and reentrant D3DX call passed");
    return FD_SUCCESS;
}
#else
FD_MOD_ENTRY(Fixture, Failing) {
    context->lua->setJson(context,"ShouldNotExist","true");
    context->log(FD_LOG_WARNING, "fixture deliberately returned failure");
    return FD_FAILURE;
}
#endif
