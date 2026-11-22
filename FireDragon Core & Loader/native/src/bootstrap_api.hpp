#pragma once
#include <windows.h>
#include <d3dx9effect.h>
#include <cstdint>

namespace fd {
constexpr uint32_t BootstrapApiVersion = 1;
using CompilerFn = decltype(&D3DXCreateEffectCompiler);
using EffectFn = decltype(&D3DXCreateEffect);

struct HostApi {
    uint32_t size, version;
    const wchar_t* modsDirectory;
    CompilerFn compiler;
    EffectFn effect;
};

struct Hooks {
    uint32_t size, version;
    CompilerFn compiler;
    EffectFn effect;
};

using InitializeFn = int(__cdecl*)(const HostApi*, Hooks*);
} // namespace fd
