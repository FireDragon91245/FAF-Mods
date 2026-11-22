#pragma once
#include "FireDragonLoader.h"
#include "nlohmann/json.hpp"
#include <cstddef>
#include <string>

struct lua_State;

namespace fd::lua {
constexpr int LoaderVersion = 3;
constexpr int RegistryIndex = -10000, GlobalsIndex = -10001;
using CFunction = int(__cdecl*)(lua_State*);

struct Api {
    int(__cdecl* gettop)(lua_State*);
    void(__cdecl* settop)(lua_State*, int);
    int(__cdecl* checkstack)(lua_State*, int);
    int(__cdecl* type)(lua_State*, int);
    float(__cdecl* tonumber)(lua_State*, int);
    int(__cdecl* toboolean)(lua_State*, int);
    const char*(__cdecl* tostring)(lua_State*, int);
    void*(__cdecl* touserdata)(lua_State*, int);
    void(__cdecl* pushnil)(lua_State*);
    void(__cdecl* pushnumber)(lua_State*, float);
    void(__cdecl* pushlstring)(lua_State*, const char*, size_t);
    void(__cdecl* pushcclosure)(lua_State*, CFunction, int);
    void(__cdecl* pushboolean)(lua_State*, int);
    void(__cdecl* pushlightuserdata)(lua_State*, void*);
    void(__cdecl* rawget)(lua_State*, int);
    void(__cdecl* rawset)(lua_State*, int);
    void(__cdecl* rawgeti)(lua_State*, int, int);
    void(__cdecl* rawseti)(lua_State*, int, int);
    void(__cdecl* newtable)(lua_State*);
    void(__cdecl* pushvalue)(lua_State*, int);
};

using Snapshot = nlohmann::json (*)();
using Logger = void (*)(int, const std::string&);
void configure(Snapshot mods, Snapshot logs, Logger logger);
void setApi(const Api& api);
void attach(lua_State* state) noexcept;
void ensureMod(const std::string& name);
const FDLuaRegistry* registry();
void beginEntry(const FDModContext* context);
void endEntry(bool success);
bool installRuntimeHooks();
} // namespace fd::lua
