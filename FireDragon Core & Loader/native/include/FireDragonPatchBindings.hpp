#pragma once
#include "FireDragonPatches.h"
#include "FireDragonEngine.hpp"
#include <algorithm>
#include <atomic>
#include <bit>
#include <concepts>
#include <functional>
#include <optional>
#include <span>
#include <stdexcept>
#include <tuple>
#include <type_traits>
#include <utility>

namespace FireDragon {
enum class Register { Eax, Ecx, Edx, Ebx, Esp, Ebp, Esi, Edi };

inline uint32_t& RegisterValue(FDRegisters& registers, Register source) {
    switch (source) {
    case Register::Eax:
        return registers.eax;
    case Register::Ecx:
        return registers.ecx;
    case Register::Edx:
        return registers.edx;
    case Register::Ebx:
        return registers.ebx;
    case Register::Esp:
        return registers.esp;
    case Register::Ebp:
        return registers.ebp;
    case Register::Esi:
        return registers.esi;
    case Register::Edi:
        return registers.edi;
    }
    throw std::invalid_argument("Unknown CPU register");
}

struct BytePattern {
    std::span<const unsigned char> bytes;

    bool Matches(std::span<const unsigned char> remaining) const {
        return remaining.size() >= bytes.size() &&
               std::equal(bytes.begin(), bytes.end(), remaining.begin());
    }

    uint32_t FindUnique(std::span<const unsigned char> function) const {
        if (bytes.empty()) {
            throw std::invalid_argument("Empty continuation pattern");
        }
        std::optional<uint32_t> found;
        for (size_t offset = 0; offset < function.size(); ++offset) {
            if (!Matches(function.subspan(offset))) {
                continue;
            }
            if (found) {
                throw std::runtime_error("Continuation pattern is ambiguous");
            }
            found = uint32_t(offset);
        }
        if (!found) {
            throw std::runtime_error("Continuation pattern was not found");
        }
        return *found;
    }
};

inline BytePattern AtBytes(std::span<const unsigned char> bytes) {
    return {bytes};
}

struct Continuation {
    uint32_t offset{};
    BytePattern pattern{};
};

inline Continuation ContinueAt(uint32_t offset) {
    return {offset, {}};
}

inline Continuation ContinueAt(std::span<const unsigned char> bytes) {
    return {0, {bytes}};
}

namespace BindingDetail {
template <class T>
concept EngineView =
    requires { T::SchemaId; } && std::constructible_from<T, const FDEngineApi*, const void*>;

template <class T> T DecodeRegister(const FDHookContext& context, uint32_t bits) {
    if constexpr (EngineView<T>) {
        return T(context.engine, reinterpret_cast<const void*>(uintptr_t(bits)));
    } else if constexpr (std::is_pointer_v<T>) {
        return reinterpret_cast<T>(uintptr_t(bits));
    } else if constexpr (std::is_same_v<T, float>) {
        return std::bit_cast<float>(bits);
    } else {
        static_assert((std::is_integral_v<T> || std::is_enum_v<T>) && sizeof(T) <= 4,
                      "A register argument must be a 32-bit scalar, pointer or engine view");
        return static_cast<T>(bits);
    }
}

template <class T> T ReadMemory(const FDHookContext& context, uintptr_t address) {
    static_assert(std::is_trivially_copyable_v<T>);
    T value{};
    if (!context.readMemory || context.readMemory(address, &value, sizeof(value)) != FD_SUCCESS) {
        throw std::runtime_error("Hook argument memory is unreadable");
    }
    return value;
}

template <class Source, auto Getter> struct MemberArgument;
template <class Source> struct DereferencedArgument;

template <class Derived> struct ArgumentOperations {
    template <auto Getter> auto Member() const {
        return MemberArgument<Derived, Getter>(static_cast<const Derived&>(*this));
    }

    auto Dereference() const {
        return DereferencedArgument<Derived>(static_cast<const Derived&>(*this));
    }
};

template <class T> struct RegisterArgument : ArgumentOperations<RegisterArgument<T>> {
    using Value = T;
    Register source;

    explicit RegisterArgument(Register reg) : source(reg) {}

    T Read(const FDHookContext& context) const {
        return DecodeRegister<T>(context, RegisterValue(*context.registers, source));
    }
};

template <class T> struct MemoryArgument : ArgumentOperations<MemoryArgument<T>> {
    using Value = T;
    Register source;
    int32_t displacement;

    MemoryArgument(Register reg, int32_t offset) : source(reg), displacement(offset) {}

    T Read(const FDHookContext& context) const {
        const auto address = uintptr_t(RegisterValue(*context.registers, source)) + displacement;
        if constexpr (EngineView<T>) {
            return DecodeRegister<T>(context, ReadMemory<uint32_t>(context, address));
        } else {
            return ReadMemory<T>(context, address);
        }
    }
};

template <class Source, auto Getter>
struct MemberArgument : ArgumentOperations<MemberArgument<Source, Getter>> {
    using Value =
        std::remove_cvref_t<std::invoke_result_t<decltype(Getter), typename Source::Value>>;
    Source source;

    explicit MemberArgument(Source value) : source(std::move(value)) {}

    Value Read(const FDHookContext& context) const {
        const auto object = source.Read(context);
        if constexpr (requires { static_cast<bool>(object); }) {
            if (!object) {
                return {};
            }
        }
        return std::invoke(Getter, object);
    }
};

template <class Source>
struct DereferencedArgument : ArgumentOperations<DereferencedArgument<Source>> {
    using Pointer = typename Source::Value;

    static auto Pointee() {
        if constexpr (std::is_pointer_v<Pointer>) {
            return std::type_identity<std::remove_cv_t<std::remove_pointer_t<Pointer>>>{};
        } else {
            return std::type_identity<decltype(std::declval<Pointer>().Get())>{};
        }
    }

    using Value = typename decltype(Pointee())::type;
    Source source;

    explicit DereferencedArgument(Source value) : source(std::move(value)) {}

    Value Read(const FDHookContext& context) const {
        const auto pointer = source.Read(context);
        if (!pointer) {
            return {};
        }
        if constexpr (std::is_pointer_v<Pointer>) {
            return ReadMemory<Value>(context, reinterpret_cast<uintptr_t>(pointer));
        } else {
            return pointer.Get();
        }
    }
};
} // namespace BindingDetail

template <class T> auto From(Register source) {
    return BindingDetail::RegisterArgument<T>(source);
}

template <class T> auto FromMemory(Register source, int32_t displacement = 0) {
    return BindingDetail::MemoryArgument<T>(source, displacement);
}

template <class T> auto Stack(int32_t offset) {
    return FromMemory<T>(Register::Esp, offset);
}

template <class Function, class... Arguments> struct BoundCallback {
    static_assert(std::invocable<Function, typename Arguments::Value...>,
                  "Declared hook arguments must match the callback signature");
    using Result = std::invoke_result_t<Function, typename Arguments::Value...>;
    Function function;
    std::tuple<Arguments...> arguments;
    std::optional<Continuation> onFalse;
    std::optional<Register> resultRegister;

    auto OnFalse(Continuation continuation) const {
        static_assert(std::same_as<Result, bool>, "OnFalse requires a bool callback");
        auto copy = *this;
        copy.onFalse = continuation;
        return copy;
    }

    auto StoreResult(Register destination) const {
        static_assert(
            std::is_pointer_v<Result> ||
                ((std::is_integral_v<Result> || std::is_enum_v<Result>) && sizeof(Result) <= 4),
            "StoreResult requires a 32-bit scalar or pointer result");
        auto copy = *this;
        copy.resultRegister = destination;
        return copy;
    }
};

template <class Function, class... Arguments>
auto CallWith(Function function, Arguments... arguments) {
    return BoundCallback<Function, Arguments...>{
        function, std::tuple(std::move(arguments)...), {}, {}};
}

namespace BindingDetail {
template <class Call> struct CallbackPacket {
    std::atomic<unsigned> references{1};
    Call call;
    uint32_t resumeOffset{};

    explicit CallbackPacket(Call value) : call(std::move(value)) {
        if (call.onFalse) {
            resumeOffset = call.onFalse->offset;
        }
    }

    static void FD_CALL Retain(void* userdata) noexcept {
        ++static_cast<CallbackPacket*>(userdata)->references;
    }

    static void FD_CALL Release(void* userdata) noexcept {
        auto packet = static_cast<CallbackPacket*>(userdata);
        if (--packet->references == 0) {
            delete packet;
        }
    }

    static FDHookResult FD_CALL Invoke(FDHookContext* context, void* userdata) {
        auto& packet = *static_cast<CallbackPacket*>(userdata);
        auto invoke = [&](const auto&... arguments) {
            return std::invoke(packet.call.function, arguments.Read(*context)...);
        };
        if constexpr (std::is_void_v<typename Call::Result>) {
            std::apply(invoke, packet.call.arguments);
        } else {
            const auto result = std::apply(invoke, packet.call.arguments);
            if (packet.call.resultRegister) {
                if constexpr (std::is_pointer_v<typename Call::Result>) {
                    RegisterValue(*context->registers, *packet.call.resultRegister) =
                        reinterpret_cast<uintptr_t>(result);
                } else if constexpr ((std::is_integral_v<typename Call::Result> ||
                                      std::is_enum_v<typename Call::Result>) &&
                                     sizeof(result) <= 4) {
                    RegisterValue(*context->registers, *packet.call.resultRegister) =
                        uint32_t(result);
                }
            }
            if constexpr (std::same_as<typename Call::Result, bool>) {
                if (!result && packet.call.onFalse) {
                    context->resumeOffset = packet.resumeOffset;
                    return FD_HOOK_REDIRECT;
                }
            }
        }
        return FD_HOOK_CONTINUE;
    }

    struct Selection {
        BytePattern pattern;
        CallbackPacket* packet;
        bool prepared = false;
        FDPatchFilter filter{};
        void* filterUserdata{};

        static int FD_CALL Select(const FDPatchScan* scan, void* userdata) {
            auto& selection = *static_cast<Selection*>(userdata);
            const auto bytes = std::span(scan->bytes, scan->size);
            const bool selected = selection.filter
                                      ? selection.filter(scan, selection.filterUserdata)
                                      : selection.pattern.Matches(bytes.subspan(scan->offset));
            if (!selected) {
                return false;
            }
            const auto& onFalse = selection.packet->call.onFalse;
            if (!selection.prepared && onFalse && !onFalse->pattern.bytes.empty()) {
                selection.packet->resumeOffset = onFalse->pattern.FindUnique(bytes);
            }
            selection.prepared = true;
            return true;
        }
    };
};
} // namespace BindingDetail
} // namespace FireDragon
