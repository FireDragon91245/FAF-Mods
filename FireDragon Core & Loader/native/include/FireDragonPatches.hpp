#pragma once
#include "FireDragonPatches.h"
#include "FireDragonEngine.hpp"
#include "FireDragonPatchBindings.hpp"
#include <memory>
#include <algorithm>
#include <optional>
#include <span>
#include <string_view>

namespace FireDragon {
class Hook {
    FDHookContext* context_;

  public:
    explicit Hook(FDHookContext* context) : context_(context) {}

    FDRegisters& Registers() const {
        return *context_->registers;
    }

    const FDEngineApi* Engine() const {
        return context_->engine;
    }

    std::string_view Symbol() const {
        return context_->symbol;
    }

    uint32_t Offset() const {
        return uint32_t(context_->instruction - context_->functionAddress);
    }

    FDHookResult ResumeAt(uint32_t offset) const {
        context_->resumeOffset = offset;
        return FD_HOOK_REDIRECT;
    }
};

class PatchScan {
    const FDPatchScan* scan_;

  public:
    explicit PatchScan(const FDPatchScan* scan) : scan_(scan) {}

    uint32_t Offset() const {
        return scan_->offset;
    }

    std::span<const unsigned char> Bytes() const {
        return {scan_->bytes, scan_->size};
    }

    std::span<const unsigned char> Remaining() const {
        return Bytes().subspan(Offset());
    }

    bool Matches(std::span<const unsigned char> pattern) const {
        const auto remaining = Remaining();
        return remaining.size() >= pattern.size() &&
               std::equal(pattern.begin(), pattern.end(), remaining.begin());
    }
};

class Patches {
    const FDModContext* owner_;
    const FDPatchRegistry* api_;

    bool Register(FDPatchSpec spec) const {
        spec.structSize = sizeof(spec);
        return api_->registerPatch(owner_, &spec) == FD_SUCCESS;
    }

    static FDPatchSpec Injection(const char* symbol, FDPatchLocation location,
                                 FDHookCallback callback, void* userdata) {
        FDPatchSpec spec{};
        spec.symbol = symbol;
        spec.location = location;
        spec.callback = callback;
        spec.userdata = userdata;
        return spec;
    }

    template <class Call>
    bool RegisterBound(FDPatchSpec spec, Call call, std::optional<BytePattern> pattern = {}) const {
        using Packet = BindingDetail::CallbackPacket<Call>;
        if (spec.location != FD_PATCH_FILTER && call.onFalse &&
            !call.onFalse->pattern.bytes.empty()) {
            throw std::invalid_argument(
                "Pattern continuations require a byte-pattern Filter selector");
        }
        const std::unique_ptr<Packet, decltype(&Packet::Release)> packet(
            new Packet(std::move(call)), &Packet::Release);
        spec.callback = Packet::Invoke;
        spec.userdata = packet.get();
        spec.retainUserdata = Packet::Retain;
        spec.releaseUserdata = Packet::Release;
        typename Packet::Selection selection{pattern.value_or(BytePattern{}), packet.get(), false,
                                             spec.filter, spec.filterUserdata};
        if (pattern && pattern->bytes.empty()) {
            throw std::invalid_argument("Empty injection pattern");
        }
        if (spec.location == FD_PATCH_FILTER) {
            spec.filter = Packet::Selection::Select;
            spec.filterUserdata = &selection;
        }
        return Register(spec);
    }

  public:
    explicit Patches(const FDModContext* owner) : owner_(owner), api_(owner->native->patches) {}

    std::optional<FDSymbolInfo> FindSymbol(const char* name) const {
        FDSymbolInfo symbol{};
        symbol.structSize = sizeof(symbol);
        if (api_->findSymbol(name, &symbol) != FD_SUCCESS) {
            return std::nullopt;
        }
        return symbol;
    }

    bool DefineSymbol(const char* name, const char* pattern, uint32_t size,
                      uint32_t fingerprint = 0, const char* module = nullptr) const {
        const FDSymbolPattern spec{sizeof(spec), name, module, pattern, size, fingerprint};
        return api_->defineSymbol(owner_, &spec) == FD_SUCCESS;
    }

    bool Start(const char* symbol, FDHookCallback callback, void* userdata = nullptr) const {
        return Register(Injection(symbol, FD_PATCH_START, callback, userdata));
    }

    bool End(const char* symbol, FDHookCallback callback, void* userdata = nullptr) const {
        return Register(Injection(symbol, FD_PATCH_END, callback, userdata));
    }

    bool Call(const char* symbol, const char* calledSymbol, FDHookCallback callback,
              void* userdata = nullptr, uint32_t expectedMatches = 1) const {
        auto spec = Injection(symbol, FD_PATCH_CALL, callback, userdata);
        spec.calledSymbol = calledSymbol;
        spec.expectedMatches = expectedMatches;
        return Register(spec);
    }

    bool Offset(const char* symbol, uint32_t offset, FDHookCallback callback,
                void* userdata = nullptr) const {
        auto spec = Injection(symbol, FD_PATCH_OFFSET, callback, userdata);
        spec.offset = offset;
        return Register(spec);
    }

    bool Filter(const char* symbol, FDPatchFilter filter, FDHookCallback callback,
                void* userdata = nullptr, void* filterUserdata = nullptr,
                uint32_t expectedMatches = 1) const {
        auto spec = Injection(symbol, FD_PATCH_FILTER, callback, userdata);
        spec.filter = filter;
        spec.filterUserdata = filterUserdata;
        spec.expectedMatches = expectedMatches;
        return Register(spec);
    }

    template <class F, class... A>
    bool Filter(const char* symbol, BytePattern pattern, BoundCallback<F, A...> call,
                uint32_t expectedMatches = 1) const {
        auto spec = Injection(symbol, FD_PATCH_FILTER, nullptr, nullptr);
        spec.expectedMatches = expectedMatches;
        return RegisterBound(spec, std::move(call), pattern);
    }

    template <class F, class... A>
    bool Filter(const char* symbol, FDPatchFilter filter, BoundCallback<F, A...> call,
                void* filterUserdata = nullptr, uint32_t expectedMatches = 1) const {
        if (!filter) {
            throw std::invalid_argument("Missing scan callback");
        }
        auto spec = Injection(symbol, FD_PATCH_FILTER, nullptr, nullptr);
        spec.filter = filter;
        spec.filterUserdata = filterUserdata;
        spec.expectedMatches = expectedMatches;
        return RegisterBound(spec, std::move(call));
    }

    template <class F, class... A>
    bool Start(const char* symbol, BoundCallback<F, A...> call) const {
        return RegisterBound(Injection(symbol, FD_PATCH_START, nullptr, nullptr), std::move(call));
    }

    template <class F, class... A> bool End(const char* symbol, BoundCallback<F, A...> call) const {
        if (call.onFalse) {
            throw std::invalid_argument("End callbacks cannot redirect");
        }
        return RegisterBound(Injection(symbol, FD_PATCH_END, nullptr, nullptr), std::move(call));
    }

    template <class F, class... A>
    bool Offset(const char* symbol, uint32_t offset, BoundCallback<F, A...> call) const {
        auto spec = Injection(symbol, FD_PATCH_OFFSET, nullptr, nullptr);
        spec.offset = offset;
        return RegisterBound(spec, std::move(call));
    }

    template <class F, class... A>
    bool Call(const char* symbol, const char* calledSymbol, BoundCallback<F, A...> call,
              uint32_t expectedMatches = 1) const {
        auto spec = Injection(symbol, FD_PATCH_CALL, nullptr, nullptr);
        spec.calledSymbol = calledSymbol;
        spec.expectedMatches = expectedMatches;
        return RegisterBound(spec, std::move(call));
    }

    bool Detour(const char* symbol, void* replacement, void** original) const {
        auto spec = Injection(symbol, FD_PATCH_START, nullptr, nullptr);
        spec.type = FD_PATCH_DETOUR;
        spec.detour = replacement;
        spec.original = original;
        return Register(spec);
    }

    const char* LastError() const {
        return api_->lastError();
    }
};

inline bool HasNativeApi(const FDModContext* context) {
    return context && context->apiVersion == FD_API_VERSION &&
           context->structSize >= sizeof(FDModContext) && context->native &&
           context->native->structSize >= sizeof(FDNativeApi) &&
           context->native->apiVersion == FD_NATIVE_API_VERSION && context->native->engine &&
           context->native->patches && context->native->engine->structSize >= sizeof(FDEngineApi) &&
           context->native->patches->structSize >= sizeof(FDPatchRegistry) &&
           context->native->engine->apiVersion == FD_NATIVE_API_VERSION &&
           context->native->patches->apiVersion == FD_NATIVE_API_VERSION &&
           context->native->engine->fields &&
           context->native->engine->fields->structSize >= sizeof(FDFieldsApi) &&
           context->native->engine->fields->apiVersion == FD_NATIVE_API_VERSION;
}
} // namespace FireDragon
