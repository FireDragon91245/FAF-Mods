// Run library contracts on the same float-number Lua dialect as the FAF host.
#include <iostream>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

int main(int argc, char** argv) {
    if (argc != 2)
        return 2;
    auto* state = lua_open();
    if (!state)
        return 2;
    luaopen_base(state);
    luaopen_table(state);
    luaopen_string(state);
    luaopen_math(state);
    lua_settop(state, 0);
    int result = luaL_loadfile(state, argv[1]);
    if (!result)
        result = lua_pcall(state, 0, 0, 0);
    if (result)
        std::cerr << lua_tostring(state, -1) << '\n';
    lua_close(state);
    return result ? 1 : 0;
}
