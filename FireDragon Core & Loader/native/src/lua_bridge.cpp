#include "lua_bridge.hpp"
#include "resources.hpp"
#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

struct FDLuaCall {
    lua_State* state;
    int arguments;
    bool failed;
};

namespace fd::lua {
namespace {
Api api{};
Snapshot modsSnapshot, logsSnapshot;
Logger logger;

struct Node {
    enum Kind { Table, Value, Function } kind = Table;

    std::map<std::string, std::shared_ptr<Node>> children;
    nlohmann::json value;
    FDLuaFunction function = nullptr;
    void* userdata = nullptr;
    unsigned functionId = 0;
};

std::mutex registryMutex;
std::map<std::string, std::shared_ptr<Node>> registeredMods;
std::vector<std::shared_ptr<Node>> pinnedFunctions;
unsigned generation = 1;
const std::string generationKey = "FireDragonLoader.private.generation";
thread_local const FDModContext* entryContext;
thread_local std::shared_ptr<Node> staging;
thread_local bool attaching;

void report(int level, const std::string& msg) {
    if (logger)
        logger(level, msg);
}

int absolute(lua_State* L, int index) {
    return index < 0 && index > RegistryIndex ? api.gettop(L) + index + 1 : index;
}

void string(lua_State* L, const std::string& s) {
    api.pushlstring(L, s.data(), s.size());
}

void field(lua_State* L, int index, const std::string& key) {
    index = absolute(L, index);
    string(L, key);
    api.rawget(L, index);
}

void pop(lua_State* L) {
    api.settop(L, -2);
}

void pushJson(lua_State* L, const nlohmann::json& value, int depth = 0) {
    if (depth > 32)
        throw std::runtime_error("Lua value nesting exceeds 32");
    if (value.is_null())
        api.pushnil(L);
    else if (value.is_boolean())
        api.pushboolean(L, value.get<bool>());
    else if (value.is_number()) {
        auto number = value.get<double>();
        if (!std::isfinite(number) || std::abs(number) > std::numeric_limits<float>::max())
            throw std::runtime_error("number exceeds the host Lua range");
        api.pushnumber(L, float(number));
    } else if (value.is_string())
        string(L, value.get<std::string>());
    else {
        api.newtable(L);
        int table = api.gettop(L);
        if (value.is_array()) {
            int index = 1;
            for (auto& child : value) {
                pushJson(L, child, depth + 1);
                api.rawseti(L, table, index++);
            }
        } else
            for (auto it = value.begin(); it != value.end(); ++it) {
                string(L, it.key());
                pushJson(L, it.value(), depth + 1);
                api.rawset(L, table);
            }
    }
}

nlohmann::json parseValue(const char* text) {
    if (!text || std::strlen(text) > 65536)
        throw std::runtime_error("JSON value exceeds 64 KiB");
    return nlohmann::json::parse(text,
                                 [](int depth, nlohmann::json::parse_event_t, nlohmann::json&) {
                                     if (depth > 24)
                                         throw std::runtime_error("JSON value nesting exceeds 24");
                                     return true;
                                 });
}

std::shared_ptr<Node> clone(const std::shared_ptr<Node>& node) {
    auto copy = std::make_shared<Node>(*node);
    for (auto& child : copy->children)
        child.second = clone(child.second);
    return copy;
}

std::shared_ptr<Node> fromJson(const nlohmann::json& value) {
    auto node = std::make_shared<Node>();
    if (value.is_object()) {
        for (auto it = value.begin(); it != value.end(); ++it)
            node->children[it.key()] = fromJson(it.value());
    } else {
        node->kind = Node::Value;
        node->value = value;
    }
    return node;
}

std::vector<std::string> pathParts(const char* path) {
    if (!path || std::strlen(path) > 512)
        throw std::runtime_error("invalid Lua registration path");
    std::vector<std::string> parts;
    std::string text(path);
    size_t start = 0;
    while (true) {
        auto stop = text.find('.', start);
        auto part = text.substr(start, stop == text.npos ? stop : stop - start);
        if (!fd::identifier(part) || parts.size() >= 16)
            throw std::runtime_error("Lua registration paths need 1..16 identifier segments");
        parts.push_back(part);
        if (stop == text.npos)
            return parts;
        start = stop + 1;
    }
}

int put(const FDModContext* context, const char* path, std::shared_ptr<Node> value,
        bool tableOnly) {
    try {
        if (!context || context != entryContext || !staging)
            throw std::runtime_error(
                "Lua registration is only allowed during the owning FDEntry call");
        auto parts = pathParts(path);
        auto parent = staging;
        for (size_t i = 0; i + 1 < parts.size(); ++i) {
            auto& child = parent->children[parts[i]];
            if (!child)
                child = std::make_shared<Node>();
            if (child->kind != Node::Table)
                throw std::runtime_error("Lua registration crosses a non-table value");
            parent = child;
        }
        auto found = parent->children.find(parts.back());
        if (found != parent->children.end()) {
            if (tableOnly && found->second->kind == Node::Table)
                return FD_SUCCESS;
            throw std::runtime_error("Lua registration would overwrite an existing value");
        }
        parent->children[parts.back()] = std::move(value);
        return FD_SUCCESS;
    } catch (const std::exception& e) {
        report(FD_LOG_ERROR, std::string("LUA_REGISTER ") + e.what());
        return FD_FAILURE;
    }
}

int FD_CALL createTable(const FDModContext* context, const char* path) {
    try {
        return put(context, path, std::make_shared<Node>(), true);
    } catch (...) {
        return FD_FAILURE;
    }
}

int FD_CALL setJson(const FDModContext* context, const char* path, const char* text) {
    try {
        return put(context, path, fromJson(parseValue(text)), false);
    } catch (const std::exception& e) {
        report(FD_LOG_ERROR, std::string("LUA_REGISTER ") + e.what());
        return FD_FAILURE;
    }
}

int FD_CALL registerFunction(const FDModContext* context, const char* path, FDLuaFunction function,
                             void* userdata) {
    if (!function)
        return FD_FAILURE;
    try {
        auto node = std::make_shared<Node>();
        node->kind = Node::Function;
        node->function = function;
        node->userdata = userdata;
        return put(context, path, node, false);
    } catch (...) {
        return FD_FAILURE;
    }
}

const FDLuaRegistry registrationApi{sizeof(FDLuaRegistry), FD_API_VERSION, &createTable, &setJson,
                                    &registerFunction};

int FD_CALL argumentCount(FDLuaCall* call) {
    return call->arguments;
}

int FD_CALL argumentType(FDLuaCall* call, int index) {
    if (index < 1 || index > call->arguments)
        return FD_LUA_NIL;
    int type = api.type(call->state, index);
    return type == 0 || type == 1 || type == 3 || type == 4 || type == 5 ? type : FD_LUA_OTHER;
}

int FD_CALL boolean(FDLuaCall* call, int index) {
    return argumentType(call, index) == FD_LUA_BOOLEAN && api.toboolean(call->state, index);
}

double FD_CALL number(FDLuaCall* call, int index) {
    return argumentType(call, index) == FD_LUA_NUMBER ? double(api.tonumber(call->state, index))
                                                      : 0;
}

const char* FD_CALL text(FDLuaCall* call, int index) {
    return argumentType(call, index) == FD_LUA_STRING ? api.tostring(call->state, index) : nullptr;
}

bool pushAllowed(FDLuaCall* call) {
    if (api.gettop(call->state) - call->arguments >= 64) {
        call->failed = true;
        return false;
    }
    return true;
}

void FD_CALL pushNil(FDLuaCall* call) {
    if (pushAllowed(call))
        api.pushnil(call->state);
}

void FD_CALL pushBoolean(FDLuaCall* call, int value) {
    if (pushAllowed(call))
        api.pushboolean(call->state, value != 0);
}

void FD_CALL pushNumber(FDLuaCall* call, double value) {
    if (!std::isfinite(value) || std::abs(value) > std::numeric_limits<float>::max()) {
        call->failed = true;
        return;
    }
    if (pushAllowed(call))
        api.pushnumber(call->state, float(value));
}

void FD_CALL pushString(FDLuaCall* call, const char* value) {
    if (!value || std::strlen(value) > 65536) {
        call->failed = true;
        return;
    }
    if (pushAllowed(call))
        api.pushlstring(call->state, value, std::strlen(value));
}

int FD_CALL pushJsonResult(FDLuaCall* call, const char* text) {
    int top = api.gettop(call->state);
    try {
        if (!pushAllowed(call))
            return FD_FAILURE;
        pushJson(call->state, parseValue(text));
        return FD_SUCCESS;
    } catch (...) {
        api.settop(call->state, top);
        call->failed = true;
        return FD_FAILURE;
    }
}

const FDLuaStack stackApi{sizeof(FDLuaStack), FD_API_VERSION, &argumentCount, &argumentType,
                          &boolean,           &number,        &text,          &pushNil,
                          &pushBoolean,       &pushNumber,    &pushString,    &pushJsonResult};

int invoke(lua_State* L) {
    unsigned id = unsigned(api.tonumber(L, GlobalsIndex - 1));
    std::shared_ptr<Node> node;
    {
        std::lock_guard<std::mutex> lock(registryMutex);
        if (id && id <= pinnedFunctions.size())
            node = pinnedFunctions[id - 1];
    }
    int top = api.gettop(L);
    try {
        if (!api.checkstack(L, 256) || !node || !node->function)
            throw std::runtime_error("invalid native Lua callback");
        FDLuaCall call{L, top, false};
        int count = node->function(&stackApi, &call, node->userdata);
        if (call.failed || count < 0 || count > 64 || count > api.gettop(L) - top)
            throw std::runtime_error("native Lua callback returned invalid results");
        return count;
    } catch (...) {
        api.settop(L, top);
        api.pushnil(L);
        string(L, "FireDragon native callback failed; see FireDragonLoader.Logs()");
        report(FD_LOG_ERROR, "LUA_CALLBACK failed; returned nil and an error message");
        return 2;
    }
}

int isPresent(lua_State* L) {
    api.pushboolean(L, 1);
    return 1;
}

int version(lua_State* L) {
    api.pushnumber(L, float(LoaderVersion));
    return 1;
}

int loadedMods(lua_State* L) {
    try {
        pushJson(L, modsSnapshot ? modsSnapshot() : nlohmann::json::array());
        return 1;
    } catch (...) {
        api.newtable(L);
        return 1;
    }
}

int logs(lua_State* L) {
    try {
        pushJson(L, logsSnapshot ? logsSnapshot() : nlohmann::json::array());
        return 1;
    } catch (...) {
        api.newtable(L);
        return 1;
    }
}

void ensureTable(lua_State* L, int parent, const std::string& key) {
    parent = absolute(L, parent);
    field(L, parent, key);
    if (api.type(L, -1) == 5)
        return;
    pop(L);
    string(L, key);
    api.newtable(L);
    api.rawset(L, parent);
    field(L, parent, key);
}

void apply(lua_State* L, int table, const std::shared_ptr<Node>& node) {
    table = absolute(L, table);
    for (auto& pair : node->children) {
        const auto& key = pair.first;
        const auto& child = pair.second;
        if (child->kind == Node::Table) {
            ensureTable(L, table, key);
            apply(L, -1, child);
            pop(L);
        } else {
            string(L, key);
            if (child->kind == Node::Value)
                pushJson(L, child->value);
            else {
                api.pushnumber(L, float(child->functionId));
                api.pushcclosure(L, &invoke, 1);
            }
            api.rawset(L, table);
        }
    }
}

void pin(const std::shared_ptr<Node>& node) {
    if (node->kind == Node::Function && !node->functionId) {
        if (pinnedFunctions.size() >= 16384)
            throw std::runtime_error("native Lua function limit exceeded");
        node->functionId = unsigned(pinnedFunctions.size() + 1);
        pinnedFunctions.push_back(node);
    }
    for (auto& child : node->children)
        pin(child.second);
}
} // namespace

void configure(Snapshot mods, Snapshot logs, Logger sink) {
    modsSnapshot = mods;
    logsSnapshot = logs;
    logger = sink;
}

void setApi(const Api& value) {
    api = value;
}

const FDLuaRegistry* registry() {
    return &registrationApi;
}

void ensureMod(const std::string& name) {
    std::lock_guard<std::mutex> lock(registryMutex);
    if (!registeredMods.count(name)) {
        registeredMods[name] = std::make_shared<Node>();
        ++generation;
    }
}

void beginEntry(const FDModContext* context) {
    if (entryContext)
        throw std::runtime_error("nested component entry");
    std::lock_guard<std::mutex> lock(registryMutex);
    auto found = registeredMods.find(context->modName);
    staging = found == registeredMods.end() ? std::make_shared<Node>() : clone(found->second);
    entryContext = context;
}

void endEntry(bool success) {
    if (entryContext && success) {
        std::lock_guard<std::mutex> lock(registryMutex);
        pin(staging);
        registeredMods[entryContext->modName] = staging;
        ++generation;
    }
    staging.reset();
    entryContext = nullptr;
}

void attach(lua_State* L) noexcept {
    if (!api.gettop || !L || attaching)
        return;
    attaching = true;
    int top = api.gettop(L);
    try {
        if (!api.checkstack(L, 256))
            throw std::runtime_error("cannot reserve Lua bridge stack");
        unsigned current;
        std::map<std::string, std::shared_ptr<Node>> bindings;
        {
            std::lock_guard<std::mutex> lock(registryMutex);
            current = generation;
        }
        string(L, generationKey);
        api.rawget(L, RegistryIndex);
        unsigned seen = api.type(L, -1) == 3 ? unsigned(api.tonumber(L, -1)) : 0;
        pop(L);
        field(L, GlobalsIndex, "FireDragonLoader");
        bool exists = api.type(L, -1) == 5;
        pop(L);
        if (seen != current || !exists) {
            {
                std::lock_guard<std::mutex> lock(registryMutex);
                bindings = registeredMods;
                current = generation;
            }
            ensureTable(L, GlobalsIndex, "FireDragonLoader");
            int table = api.gettop(L);
            for (auto pair :
                 {std::make_pair("IsPresent", &isPresent), std::make_pair("Version", &version),
                  std::make_pair("LoadedMods", &loadedMods), std::make_pair("Logs", &logs)}) {
                string(L, pair.first);
                api.pushcclosure(L, pair.second, 0);
                api.rawset(L, table);
            }
            ensureTable(L, table, "Mods");
            int mods = api.gettop(L);
            for (const auto& pair : bindings) {
                ensureTable(L, mods, pair.first);
                apply(L, -1, pair.second);
                pop(L);
            }
            string(L, generationKey);
            api.pushnumber(L, float(current));
            api.rawset(L, RegistryIndex);
            if (!seen)
                report(FD_LOG_INFO, "LUA_ATTACH registered FireDragonLoader in a Lua runtime");
        }
    } catch (const std::exception& e) {
        report(FD_LOG_ERROR, std::string("LUA_ATTACH ") + e.what());
    } catch (...) {
        report(FD_LOG_ERROR, "LUA_ATTACH failed");
    }
    api.settop(L, top);
    attaching = false;
}
} // namespace fd::lua
