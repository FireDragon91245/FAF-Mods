#include "../native/src/lua_bridge.hpp"
#include "FireDragonLua.hpp"
#include <iostream>
#include <stdexcept>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}
static_assert(sizeof(lua_Number) == sizeof(float), "Test the host's float Lua ABI");

namespace {
nlohmann::json messages = nlohmann::json::array();

nlohmann::json mods() {
    return nlohmann::json::array({{{"name", "Fixture"},
                                   {"version", 7},
                                   {"dlls", {"dlls/EngineHooks.dll"}},
                                   {"shaders", {"FixtureSurface"}}}});
}

nlohmann::json logs() {
    return messages;
}

void log(int level, const std::string& message) {
    messages.push_back({{"level", level == FD_LOG_ERROR ? "error" : "info"}, {"msg", message}});
}

void require(bool value) {
    if (!value)
        throw std::runtime_error("native Lua registration assertion failed");
}

int FD_CALL echo(const FDLuaStack* api, FDLuaCall* call, void* userdata) {
    require(api->argumentCount(call) == 3);
    require(api->argumentType(call, 1) == FD_LUA_NUMBER &&
            api->argumentType(call, 2) == FD_LUA_STRING &&
            api->argumentType(call, 3) == FD_LUA_BOOLEAN);
    api->pushNumber(call, api->number(call, 1) + *static_cast<int*>(userdata));
    api->pushString(call, api->string(call, 2));
    api->pushBoolean(call, api->boolean(call, 3));
    require(api->pushJson(call, "{\"answer\":42,\"items\":[1,2]}") == FD_SUCCESS);
    return 4;
}

int FD_CALL bad(const FDLuaStack*, FDLuaCall*, void*) {
    return 70;
}

uint32_t typedId = 0;
bool typedTeam = false, typedNukes = false;

void typedRestrictions(uint32_t id, bool team, bool nukes) {
    typedId = id;
    typedTeam = team;
    typedNukes = nukes;
}

FireDragon::Lua::Json typedMetadata() {
    return {"{\"answer\":42}"};
}

std::string typedString(const char* text) {
    return std::string(text) + "!";
}

bool typedBoolean(bool value) {
    return !value;
}

lua_State* state() {
    auto L = lua_open();
    require(L != nullptr);
    luaopen_base(L);
    luaopen_table(L);
    luaopen_string(L);
    lua_settop(L, 0);
    return L;
}

void run(lua_State* L, const char* source) {
    fd::lua::attach(L);
    int result = luaL_loadbuffer(L, source, std::strlen(source), "FireDragon Lua bridge test");
    if (!result)
        result = lua_pcall(L, 0, 0, 0);
    if (result) {
        auto message = lua_tostring(L, -1);
        throw std::runtime_error(message ? message : "Lua error");
    }
    require(lua_gettop(L) == 0);
}
} // namespace

int main() {
    try {
        fd::lua::Api api{&lua_gettop,      &lua_settop,
                         &lua_checkstack,  &lua_type,
                         &lua_tonumber,    &lua_toboolean,
                         &lua_tostring,    &lua_touserdata,
                         &lua_pushnil,     &lua_pushnumber,
                         &lua_pushlstring, &lua_pushcclosure,
                         &lua_pushboolean, &lua_pushlightuserdata,
                         &lua_rawget,      &lua_rawset,
                         &lua_rawgeti,     &lua_rawseti,
                         &lua_newtable,    &lua_pushvalue};
        fd::lua::setApi(api);
        fd::lua::configure(&mods, &logs, &log);
        auto first = state();
        run(first, "assert(FireDragonLoader.IsPresent()==true); "
                   "assert(type(FireDragonLoader.IsPresent())=='boolean'); "
                   "assert(FireDragonLoader.Version()==3)");
        run(first, "local m=FireDragonLoader.LoadedMods(); assert(m[1].name=='Fixture' and "
                   "m[1].version==7); assert(m[1].dlls[1]=='dlls/EngineHooks.dll'); "
                   "assert(m[1].shaders[1]=='FixtureSurface'); m[1].name='changed'; "
                   "assert(FireDragonLoader.LoadedMods()[1].name=='Fixture')");
        int offset = 9;
        FDModContext context{
            sizeof(FDModContext), FD_API_VERSION, "Fixture", L"C:\\fixture", nullptr,
            fd::lua::registry(),  nullptr};
        fd::lua::ensureMod("Fixture");
        fd::lua::beginEntry(&context);
        require(context.lua->createTable(&context, "Config") == FD_SUCCESS);
        require(context.lua->setJson(
                    &context, "Config.Values",
                    "{\"enabled\":true,\"power\":3.5,\"names\":[\"one\",\"two\"]}") == FD_SUCCESS);
        require(context.lua->registerFunction(&context, "Echo", &echo, &offset) == FD_SUCCESS);
        require(context.lua->registerFunction(&context, "Bad", &bad, nullptr) == FD_SUCCESS);
        FireDragon::Lua::Bindings bindings(&context);
        require(bindings.Bind<typedRestrictions>("SetRestrictions"));
        require(bindings.Bind<typedMetadata>("Metadata"));
        require(bindings.Bind<typedString>("Text"));
        require(bindings.Bind<typedBoolean>("Boolean"));
        require(context.lua->setJson(&context, "Echo", "false") == FD_FAILURE);
        FDModContext other = context;
        other.modName = "Other";
        require(context.lua->setJson(&other, "NotOwned", "true") == FD_FAILURE);
        fd::lua::endEntry(true);
        require(context.lua->setJson(&context, "TooLate", "true") == FD_FAILURE);
        const char* verify = R"(
            local f=FireDragonLoader.Mods.Fixture
            assert(f.Config.Values.enabled and f.Config.Values.power==3.5 and f.Config.Values.names[2]=='two')
            local number,text,flag,object=f.Echo(12,'hello',true)
            assert(number==21 and text=='hello' and flag==true and object.answer==42 and object.items[2]==2)
            local value,reason=f.Bad(); assert(value==nil and type(reason)=='string')
            f.SetRestrictions(17,true,false)
            assert(f.Metadata().answer==42 and f.Text('hello')=='hello!' and f.Boolean(false)==true)
            for _,bad in ipairs({-1,1.5,'17'}) do
                local value,reason=f.SetRestrictions(bad,true,false);assert(value==nil and type(reason)=='string')
            end
            local value,reason=f.SetRestrictions(17,1,false);assert(value==nil and type(reason)=='string')
            local value,reason=f.Metadata('extra');assert(value==nil and type(reason)=='string')
            assert(table.getn(FireDragonLoader.Logs())>0)
            SavedLoader=FireDragonLoader; SavedMod=f
        )";
        run(first, verify);
        require(typedId == 17 && typedTeam && !typedNukes);
        auto second = state();
        run(second, verify);
        FDModContext rejected = context;
        rejected.modName = "Rejected";
        fd::lua::ensureMod("Rejected");
        fd::lua::beginEntry(&rejected);
        require(rejected.lua->setJson(&rejected, "Leak", "true") == FD_SUCCESS);
        fd::lua::endEntry(false);
        fd::lua::beginEntry(&context);
        require(context.lua->setJson(&context, "Late", "42") == FD_SUCCESS);
        fd::lua::endEntry(true);
        run(first,
            "assert(SavedLoader==FireDragonLoader and SavedMod==FireDragonLoader.Mods.Fixture); "
            "assert(SavedMod.Late==42); assert(FireDragonLoader.Mods.Rejected.Leak==nil)");
        lua_close(first);
        lua_close(second);
        auto recreated = state();
        run(recreated, verify);
        lua_close(recreated);
        std::cout << "PASS: real float Lua VM: built-ins, snapshots, scoped registration, "
                     "callbacks, rollback, stack balance and recreated states\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n';
        return 1;
    }
}
