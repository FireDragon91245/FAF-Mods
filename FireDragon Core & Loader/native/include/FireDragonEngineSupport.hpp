#pragma once
#include "FireDragonEngine.h"
#include "FireDragonFields.hpp"
#include <optional>
#include <type_traits>

namespace FireDragon::FAF {
namespace Detail {
template <class T> T Value(const FDEngineApi* api, Native::Object object) {
    if constexpr (std::is_arithmetic_v<T> || std::is_enum_v<T>)
        return object.Read<T>();
    else
        return T(api, object);
}

template <class T> std::optional<T> TryValue(const FDEngineApi* api, Native::Object object) {
    if (!api || !api->fields || !object.Address())
        return std::nullopt;
    if constexpr (std::is_arithmetic_v<T> || std::is_enum_v<T>)
        return object.TryRead<T>();
    else
        return T(api, object);
}

/* Shared mechanics only. Engine-specific fields, types, casts and methods are
   emitted by the generator in FireDragonEngine.hpp. */
template <class Storage> class Record {
  protected:
    const FDEngineApi* engine_{};
    Storage native_{};

    FDMethodValue Invoke(const char* symbol, const FDMethodValue* args, uint32_t count) const {
        FDMethodValue result{};
        if (!engine_ || !engine_->invoke ||
            engine_->invoke(symbol, native_.Reference(), args, count, &result) != FD_SUCCESS)
            throw std::runtime_error("Native method is unavailable for this object/profile");
        return result;
    }

  public:
    Record() = default;

    Record(const FDEngineApi* api, const void* address)
        : engine_(api), native_(api ? api->fields : nullptr, address) {}

    Record(const FDEngineApi* api, Native::Object object) : engine_(api), native_(object) {}

    explicit operator bool() const {
        return engine_ && native_.Address();
    }

    const void* Address() const {
        return native_.Address();
    }

    const Native::Object& Inspect() const {
        return native_;
    }

    template <class Other> bool operator==(const Other& other) const {
        return Address() == other.Address();
    }

    template <class Other> bool operator!=(const Other& other) const {
        return !(*this == other);
    }

    uint32_t MethodCount() const {
        auto type = native_.Type();
        return type && engine_ && engine_->methodCount ? engine_->methodCount(type->id) : 0;
    }

    const FDMethodInfo* MethodInfo(uint32_t index) const {
        auto type = native_.Type();
        return type && engine_ && engine_->methodAt ? engine_->methodAt(type->id, index) : nullptr;
    }
};
} // namespace Detail

template <class T> class Pointer {
    const FDEngineApi* engine_{};
    Native::Object storage_{};
    std::optional<Native::Object> target_;

    Native::Object Target() const {
        return target_ ? *target_ : storage_.Dereference();
    }

  public:
    Pointer() = default;

    Pointer(const FDEngineApi* api, Native::Object storage) : engine_(api), storage_(storage) {}

    Pointer(const FDEngineApi* api, const void* address, uint32_t type)
        : engine_(api),
          target_(std::in_place, api ? api->fields : nullptr, FDObjectRef{address, type, 0, 0}) {}

    const void* Address() const {
        return Target().Address();
    }

    explicit operator bool() const {
        return Address() != nullptr;
    }

    T Get() const {
        return Detail::Value<T>(engine_, Target());
    }

    std::optional<T> TryGet() const {
        return Detail::TryValue<T>(engine_, Target());
    }

    T operator*() const {
        return Get();
    }
};

template <class T> class Array {
    const FDEngineApi* engine_{};
    Native::Object storage_{};

  public:
    Array() = default;

    Array(const FDEngineApi* api, Native::Object storage) : engine_(api), storage_(storage) {}

    uint32_t Count() const {
        return storage_.Count();
    }

    T At(uint32_t index) const {
        return Detail::Value<T>(engine_, storage_.At(index));
    }
};
} // namespace FireDragon::FAF
