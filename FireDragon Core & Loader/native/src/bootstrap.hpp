#pragma once
#include "bootstrap_api.hpp"
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>

namespace fd::bootstrap {
inline HMODULE selfModule;
inline CompilerFn originalCompiler;
inline EffectFn originalEffect;
inline Hooks hooks{};
inline std::once_flag coreOnce;
inline bool compilerHooked, effectHooked;
using CommandLineFn = LPSTR (WINAPI*)();
inline CommandLineFn originalCommandLine;

inline void diagnostic(const std::string& message) noexcept {
    try {
        wchar_t local[32768]{};
        if (GetEnvironmentVariableW(L"LOCALAPPDATA", local, 32768)) {
            auto dir = std::filesystem::path(local)/"FireDragonModLoader";
            std::filesystem::create_directories(dir);
            std::ofstream out(dir/("loader-"+std::to_string(GetCurrentProcessId())+".log"), std::ios::app);
            out << GetTickCount64() << " BOOTSTRAP " << message << '\n';
        }
    } catch (...) {}
}
inline std::wstring configValue(const std::filesystem::path& path, const wchar_t* key) {
    wchar_t value[32768]{};
    auto n = GetPrivateProfileStringW(L"Loader", key, L"", value, 32768, path.c_str());
    if (n >= 32767) throw std::runtime_error("configuration value too long");
    return value;
}
inline void ensureCore() noexcept {
    try {
        std::call_once(coreOnce, [] {
            // Executed by main-executable code, after Windows has left DllMain.
            diagnostic(std::string("hooks compiler=")+(compilerHooked?"yes":"NO")+" effect="+(effectHooked?"yes":"NO"));
            wchar_t path[32768]{};
            if (!GetModuleFileNameW(selfModule, path, 32768)) { diagnostic("ERROR proxy path unavailable"); return; }
            const auto config = std::filesystem::path(path).parent_path()/"FireDragonLoader.ini";
            auto corePath = std::filesystem::path(configValue(config, L"LoaderPath"));
            auto mods = configValue(config, L"ModsDirectory");
            if (!corePath.is_absolute() || mods.empty()) { diagnostic("ERROR missing absolute LoaderPath or ModsDirectory"); return; }
            HMODULE core = LoadLibraryExW(corePath.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if (!core) { diagnostic("ERROR cannot load FireDragonLoader.dll win32="+std::to_string(GetLastError())); return; }
            auto initialize = reinterpret_cast<InitializeFn>(GetProcAddress(core, "FDInitializeV1"));
            if (!initialize) { diagnostic("ERROR FireDragonLoader.dll lacks FDInitializeV1"); return; }
            const HostApi host{sizeof(HostApi), BootstrapApiVersion, mods.c_str(), originalCompiler, originalEffect};
            Hooks candidate{sizeof(Hooks), BootstrapApiVersion, nullptr, nullptr};
            if (initialize(&host, &candidate) != 0 || !candidate.compiler || !candidate.effect || candidate.version != BootstrapApiVersion) {
                diagnostic("ERROR incompatible loader core; original shader calls retained"); return;
            }
            hooks = candidate;
            diagnostic("FireDragonLoader.dll initialized");
            // Deliberately keep the core's load reference for the process lifetime.
        });
    } catch (const std::exception& e) { diagnostic(std::string("ERROR ")+e.what()); }
    catch (...) { diagnostic("ERROR initializing loader core"); }
}
inline HRESULT WINAPI compilerDispatch(LPCSTR source, UINT length, const D3DXMACRO* defines,
    LPD3DXINCLUDE include, DWORD flags, LPD3DXEFFECTCOMPILER* compiler, LPD3DXBUFFER* errors) {
    ensureCore();
    return (hooks.compiler ? hooks.compiler : originalCompiler)(source, length, defines, include, flags, compiler, errors);
}
inline HRESULT WINAPI effectDispatch(LPDIRECT3DDEVICE9 device, LPCVOID source, UINT length, const D3DXMACRO* defines,
    LPD3DXINCLUDE include, DWORD flags, LPD3DXEFFECTPOOL pool, LPD3DXEFFECT* effect, LPD3DXBUFFER* errors) {
    ensureCore();
    return (hooks.effect ? hooks.effect : originalEffect)(device, source, length, defines, include, flags, pool, effect, errors);
}
inline LPSTR WINAPI commandLineDispatch() {
    LPSTR command = originalCommandLine();
    ensureCore();
    return command;
}
template<class T> inline bool hookImport(const char* name, T replacement, T& original, const char* dllName = "d3dx9_35.dll") {
    auto base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    auto pe = reinterpret_cast<IMAGE_NT_HEADERS32*>(base+dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_I386) return false;
    auto directory = pe->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!directory.VirtualAddress) return false;
    auto imports = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base+directory.VirtualAddress);
    for (; imports->Name; ++imports) {
        if (_stricmp(reinterpret_cast<char*>(base+imports->Name), dllName) || !imports->OriginalFirstThunk) continue;
        auto names = reinterpret_cast<IMAGE_THUNK_DATA32*>(base+imports->OriginalFirstThunk);
        auto slots = reinterpret_cast<IMAGE_THUNK_DATA32*>(base+imports->FirstThunk);
        for (; names->u1.AddressOfData; ++names, ++slots) {
            if (IMAGE_SNAP_BY_ORDINAL32(names->u1.Ordinal)) continue;
            auto symbol = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(base+names->u1.AddressOfData);
            if (strcmp(reinterpret_cast<char*>(symbol->Name), name)) continue;
            DWORD protection;
            if (!VirtualProtect(&slots->u1.Function, sizeof(DWORD), PAGE_READWRITE, &protection)) return false;
            original = reinterpret_cast<T>(slots->u1.Function);
            InterlockedExchange(reinterpret_cast<volatile LONG*>(&slots->u1.Function), reinterpret_cast<LONG>(replacement));
            DWORD unused;
            VirtualProtect(&slots->u1.Function, sizeof(DWORD), protection, &unused);
            return true;
        }
    }
    return false;
}
inline void attach(HMODULE module) {
    selfModule = module;
    DisableThreadLibraryCalls(module);
    compilerHooked = hookImport("D3DXCreateEffectCompiler", &compilerDispatch, originalCompiler);
    effectHooked = hookImport("D3DXCreateEffect", &effectDispatch, originalEffect);
    // FA's main executable calls this during normal CRT/startup, before its Lua
    // VMs are initialized. Shader dispatch remains a fallback for other hosts.
    hookImport("GetCommandLineA", &commandLineDispatch, originalCommandLine, "KERNEL32.dll");
}
}
