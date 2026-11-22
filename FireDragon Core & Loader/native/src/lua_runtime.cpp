#include "lua_bridge.hpp"
#include "native_runtime.hpp"
#include "FireDragonPatches.hpp"

namespace fd::lua {
namespace {
using ProtectedCall = int(__cdecl*)(lua_State*, int, int, int);
using Call = void(__cdecl*)(lua_State*, int, int);
ProtectedCall originalProtected;
Call originalCall;

int __cdecl protectedHook(lua_State* state, int arguments, int results, int errorHandler) {
    attach(state);
    return originalProtected(state, arguments, results, errorHandler);
}

void __cdecl callHook(lua_State* state, int arguments, int results) {
    attach(state);
    originalCall(state, arguments, results);
}

template <class T> T symbol(const char* name) {
    auto value = native::find(name);
    return value ? reinterpret_cast<T>(value->address) : nullptr;
}
} // namespace

bool installRuntimeHooks() {
    if (!native::initialize())
        return false;
    Api api{};
#define API(member, name) api.member = symbol<decltype(api.member)>(name)
    API(gettop, "lua_gettop");
    API(settop, "lua_settop");
    API(checkstack, "lua_checkstack");
    API(type, "lua_type");
    API(tonumber, "lua_tonumber");
    API(toboolean, "lua_toboolean");
    API(tostring, "lua_tostring");
    API(touserdata, "lua_touserdata");
    API(pushnil, "lua_pushnil");
    API(pushnumber, "lua_pushnumber");
    API(pushlstring, "lua_pushlstring");
    API(pushcclosure, "lua_pushcclosure");
    API(pushboolean, "lua_pushboolean");
    API(pushlightuserdata, "lua_pushlightuserdata");
    API(rawget, "lua_rawget");
    API(rawset, "lua_rawset");
    API(rawgeti, "lua_rawgeti");
    API(rawseti, "lua_rawseti");
    API(newtable, "lua_newtable");
    API(pushvalue, "lua_pushvalue");
#undef API
    static const FDModContext owner{
        sizeof(FDModContext), FD_API_VERSION, "FireDragonCore", nullptr, nullptr, nullptr,
        native::api()};
    native::beginEntry(&owner);
    const FireDragon::Patches patches(&owner);
    const bool declared = patches.Detour("lua_pcall", reinterpret_cast<void*>(&protectedHook),
                                         reinterpret_cast<void**>(&originalProtected)) &&
                          patches.Detour("lua_call", reinterpret_cast<void*>(&callHook),
                                         reinterpret_cast<void**>(&originalCall));
    setApi(api);
    if (!native::endEntry(declared)) {
        setApi({});
        return false;
    }
    return true;
}
} // namespace fd::lua
