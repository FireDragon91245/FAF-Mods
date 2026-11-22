#include "FireDragonLoader.h"

namespace {
int FD_CALL answer(const FDLuaStack* lua, FDLuaCall* call, void*) {
    lua->pushNumber(call, 42);
    return 1;
}

int FD_CALL echo(const FDLuaStack* lua, FDLuaCall* call, void*) {
    if (lua->argumentCount(call) != 2 || lua->argumentType(call, 1) != FD_LUA_NUMBER ||
        lua->argumentType(call, 2) != FD_LUA_STRING)
        return -1;
    lua->pushNumber(call, lua->number(call, 1) + 1);
    lua->pushString(call, lua->string(call, 2));
    return 2;
}
} // namespace

FD_MOD_ENTRY(FireDragonLuaProbe, Probe) {
    if (!context || context->apiVersion != FD_API_VERSION || !context->lua)
        return FD_FAILURE;
    if (context->lua->setJson(
            context, "Config",
            "{\"enabled\":true,\"nested\":{\"value\":17},\"items\":[\"one\",\"two\"]}") !=
            FD_SUCCESS ||
        context->lua->registerFunction(context, "Answer", &answer, nullptr) != FD_SUCCESS ||
        context->lua->registerFunction(context, "Echo", &echo, nullptr) != FD_SUCCESS)
        return FD_FAILURE;
    context->log(FD_LOG_INFO, "native Lua probe registered");
    return FD_SUCCESS;
}
