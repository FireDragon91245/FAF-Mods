#include "FireDragonLoader.h"

int FD_CALL Answer(const FDLuaStack* lua, FDLuaCall* call, void*) {
    lua->pushNumber(call,42);
    return 1;
}

// Include native/include when building. Build x86 and export this exact C name.
FD_MOD_ENTRY(MyMod, EngineHooks) {
    if (!context || context->apiVersion != FD_API_VERSION || !context->lua) return FD_FAILURE;
    if (context->lua->setJson(context,"Config","{\"enabled\":true}") != FD_SUCCESS ||
        context->lua->registerFunction(context,"Answer",&Answer,nullptr) != FD_SUCCESS) return FD_FAILURE;
    context->log(FD_LOG_INFO, "MyMod EngineHooks initialized");
    // Install the mod's native components here, outside the Windows loader lock.
    return FD_SUCCESS;
}
