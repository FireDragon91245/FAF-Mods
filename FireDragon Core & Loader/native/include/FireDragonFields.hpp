#pragma once
#include "FireDragonFields.h"
#include <optional>
#include <stdexcept>
#include <string>
#include <type_traits>

namespace FireDragon::FAF::Native {
class Object {
  protected:
    const FDFieldsApi* api_{};
    FDObjectRef object_{};

  public:
    Object() = default;

    Object(const FDFieldsApi* api, FDObjectRef object) : api_(api), object_(object) {}

    explicit operator bool() const {
        return api_ && object_.address && Type();
    }

    const void* Address() const {
        return object_.address;
    }

    FDObjectRef Reference() const {
        return object_;
    }

    const FDTypeInfo* Type() const {
        return api_ ? api_->typeById(object_.type) : nullptr;
    }

    const FDFieldInfo* FieldInfo(uint32_t index) const {
        return api_ ? api_->fieldAt(object_.type, index) : nullptr;
    }

    Object Field(const char* name, const char* declaringType = nullptr) const {
        if (!api_)
            return {};
        auto field = api_->findField(object_.type, name, declaringType);
        return {api_, api_->field(object_, field)};
    }

    Object Field(uint32_t index) const {
        return api_ ? Object(api_, api_->field(object_, FieldInfo(index))) : Object{};
    }

    Object Dereference() const {
        return api_ ? Object(api_, api_->dereference(object_)) : Object{};
    }

    uint32_t Count() const {
        return api_ ? api_->count(object_) : 0;
    }

    Object At(uint32_t index) const {
        return api_ ? Object(api_, api_->at(object_, index)) : Object{};
    }

    template <class T> bool TryRead(T& result) const {
        static_assert(std::is_trivially_copyable_v<T>, "Only copy native storage into value types");
        return api_ && api_->read(object_, &result, sizeof(T)) == FD_SUCCESS;
    }

    template <class T> std::optional<T> TryRead() const {
        T result{};
        if (!TryRead(result))
            return std::nullopt;
        return result;
    }

    template <class T> T Read() const {
        T result{};
        if (!TryRead(result))
            throw std::runtime_error("Native field is unavailable or has a different size");
        return result;
    }

    uint64_t Bits() const {
        uint64_t result = 0;
        if (!api_ || api_->readBits(object_, &result) != FD_SUCCESS)
            throw std::runtime_error("Native bitfield is unavailable");
        return result;
    }

    std::string Text() const {
        const auto size = api_ ? api_->text(object_, nullptr, 0) : 0;
        if (!size)
            return {};
        std::string result(size, '\0');
        if (api_->text(object_, result.data(), size) != size)
            return {};
        result.resize(size - 1);
        return result;
    }
};

template <uint32_t Id> class View : public Object {
  public:
    View() = default;

    View(const FDFieldsApi* api, const void* address) : Object(api, {address, Id, 0, 0}) {}

    explicit View(Object value) : Object(value) {}
};
} // namespace FireDragon::FAF::Native

#include "FireDragonFieldViews.hpp"
