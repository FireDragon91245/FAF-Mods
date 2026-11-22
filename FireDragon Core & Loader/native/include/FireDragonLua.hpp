#pragma once
#include "FireDragonLoader.h"
#include <cmath>
#include <limits>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>

namespace FireDragon::Lua {
struct Json {
    std::string text;
};

namespace Detail {
template <class T> bool Valid(const FDLuaStack* api, FDLuaCall* call, int index) {
    if constexpr (std::is_same_v<T, bool>)
        return api->argumentType(call, index) == FD_LUA_BOOLEAN;
    else if constexpr (std::is_integral_v<T>) {
        if (api->argumentType(call, index) != FD_LUA_NUMBER)
            return false;
        auto value = api->number(call, index);
        return std::isfinite(value) && std::floor(value) == value &&
               value >= double(std::numeric_limits<T>::lowest()) &&
               value <= double(std::numeric_limits<T>::max());
    } else if constexpr (std::is_floating_point_v<T>)
        return api->argumentType(call, index) == FD_LUA_NUMBER;
    else if constexpr (std::is_same_v<T, const char*>)
        return api->argumentType(call, index) == FD_LUA_STRING;
    else
        return false;
}

template <class T> T Read(const FDLuaStack* api, FDLuaCall* call, int index) {
    if constexpr (std::is_same_v<T, bool>)
        return api->boolean(call, index) != 0;
    else if constexpr (std::is_arithmetic_v<T>)
        return static_cast<T>(api->number(call, index));
    else
        return api->string(call, index);
}

template <class T> int Push(const FDLuaStack* api, FDLuaCall* call, T value) {
    if constexpr (std::is_same_v<T, Json>)
        return api->pushJson(call, value.text.c_str()) == FD_SUCCESS ? 1 : -1;
    else if constexpr (std::is_same_v<T, bool>)
        api->pushBoolean(call, value);
    else if constexpr (std::is_arithmetic_v<T>)
        api->pushNumber(call, double(value));
    else if constexpr (std::is_same_v<T, std::string>)
        api->pushString(call, value.c_str());
    else if constexpr (std::is_same_v<T, const char*>)
        api->pushString(call, value);
    else
        static_assert(!sizeof(T), "Unsupported native Lua return type");
    return 1;
}
template <auto Function> struct Binding;

template <class Return, class... Arguments, Return (*Function)(Arguments...)>
struct Binding<Function> {
    template <size_t... Indices>
    static int Call(const FDLuaStack* api, FDLuaCall* call, std::index_sequence<Indices...>) {
        if (api->argumentCount(call) != sizeof...(Arguments) ||
            !(Valid<Arguments>(api, call, int(Indices) + 1) && ...))
            return -1;
        if constexpr (std::is_void_v<Return>) {
            Function(Read<Arguments>(api, call, int(Indices) + 1)...);
            return 0;
        } else
            return Push(api, call, Function(Read<Arguments>(api, call, int(Indices) + 1)...));
    }

    static int FD_CALL Invoke(const FDLuaStack* api, FDLuaCall* call, void*) noexcept {
        try {
            return Call(api, call, std::index_sequence_for<Arguments...>{});
        } catch (...) {
            return -1;
        }
    }
};
} // namespace Detail

class Bindings {
    const FDModContext* owner_;

  public:
    explicit Bindings(const FDModContext* owner) : owner_(owner) {}

    template <auto Function> bool Bind(const char* name) const {
        return owner_->lua->registerFunction(owner_, name, Detail::Binding<Function>::Invoke,
                                             nullptr) == FD_SUCCESS;
    }
};
} // namespace FireDragon::Lua
