#define WIN32_LEAN_AND_MEAN
#include "bootstrap_api.hpp"
#include "resources.hpp"
#include "FireDragonLoader.h"
#include "lua_bridge.hpp"
#include <deque>
#include <mutex>

static_assert(sizeof(void*) == 4, "FAF needs a 32-bit loader");
namespace {
fd::CompilerFn realCompiler;
fd::EffectFn realEffect;
fd::fs::path modsDirectory, logFile;
fd::Resources resources;
std::once_flag hostOnce, resourceOnce;
std::mutex logMutex;
struct LogRecord { std::string level, msg; };
std::deque<LogRecord> logRecords;
struct ModStatus {
    std::string name;
    int version;
    size_t expectedDlls, expectedShaders;
    bool compiled = false;
    std::vector<std::string> dlls, shaders;
};
std::mutex statusMutex;
std::map<std::string,ModStatus> modStatus;
thread_local bool initializingResources = false;
struct LoadedDll { HMODULE module; FDModContext context; };
std::deque<LoadedDll> loadedDlls;

void recordLog(int level, const std::string& message) noexcept {
    try {
        std::lock_guard<std::mutex> lock(logMutex);
        logRecords.push_back({level == FD_LOG_ERROR ? "error" : level == FD_LOG_WARNING ? "warning" : "info", message.substr(0,16000)});
        if (logRecords.size() > 512) logRecords.pop_front();
        if (!logFile.empty()) {
            std::ofstream out(logFile, std::ios::app);
            out << GetTickCount64() << " " << message << '\n';
        }
    } catch (...) {}
}
void log(const std::string& message) noexcept {
    const bool error = message.find("ERROR") != message.npos || message.find("REJECT") != message.npos || message.rfind("MISSING",0) == 0;
    recordLog(error ? FD_LOG_ERROR : FD_LOG_INFO,message);
}
nlohmann::json logsSnapshot() {
    std::lock_guard<std::mutex> lock(logMutex);
    auto result = nlohmann::json::array();
    for (auto& row : logRecords) result.push_back({{"level",row.level},{"msg",row.msg}});
    return result;
}
nlohmann::json modsSnapshot() {
    std::lock_guard<std::mutex> lock(statusMutex);
    auto result = nlohmann::json::array();
    for (auto& pair : modStatus) {
        auto& mod = pair.second;
        if (mod.dlls.size() == mod.expectedDlls && mod.shaders.size() == mod.expectedShaders)
            result.push_back({{"name",mod.name},{"version",mod.version},{"dlls",mod.dlls},{"shaders",mod.shaders}});
    }
    return result;
}
void FD_CALL pluginLog(int level, const char* message) {
    if (message) recordLog(level,std::string("PLUGIN ")+(level == FD_LOG_ERROR ? "ERROR " : level == FD_LOG_WARNING ? "WARN " : "INFO ")+std::string(message).substr(0,16000));
}
bool x86Dll(const fd::fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    IMAGE_DOS_HEADER dos{};
    if (!file.read(reinterpret_cast<char*>(&dos), sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 0 || dos.e_lfanew > 1024*1024) return false;
    file.seekg(dos.e_lfanew);
    DWORD signature{};
    IMAGE_FILE_HEADER header{};
    return file.read(reinterpret_cast<char*>(&signature), sizeof(signature)) && signature == IMAGE_NT_SIGNATURE &&
        file.read(reinterpret_cast<char*>(&header), sizeof(header)) && header.Machine == IMAGE_FILE_MACHINE_I386 && (header.Characteristics & IMAGE_FILE_DLL);
}
void loadDlls() {
    for (const auto& mod : resources.mods) for (const auto& dll : mod.dlls) {
        if (!x86Dll(dll.path)) { log("DLL_REJECT "+dll.entry+" expected an x86 PE DLL"); continue; }
        auto module = LoadLibraryExW(dll.path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        if (!module) { log("DLL_ERROR "+dll.entry+" LoadLibraryEx win32="+std::to_string(GetLastError())); continue; }
        // Never unload a component after running its code: it may retain hooks/callbacks.
        loadedDlls.push_back({module, {sizeof(FDModContext), FD_API_VERSION, mod.name.c_str(), mod.root.c_str(), &pluginLog, fd::lua::registry()}});
        auto entry = reinterpret_cast<FDModEntry>(GetProcAddress(module, dll.entry.c_str()));
        if (!entry) { log("DLL_ERROR missing exact export "+dll.entry); continue; }
        try {
            fd::lua::beginEntry(&loadedDlls.back().context);
            int result = entry(&loadedDlls.back().context);
            fd::lua::endEntry(result == FD_SUCCESS);
            if (result == FD_SUCCESS) {
                std::lock_guard<std::mutex> lock(statusMutex);
                modStatus.at(mod.name).dlls.push_back(dll.path.lexically_relative(mod.root).generic_u8string());
            }
            log(std::string(result == FD_SUCCESS ? "DLL_ENTRY " : "DLL_ERROR ")+dll.entry+" result="+std::to_string(result));
        } catch (...) { fd::lua::endEntry(false); log("DLL_ERROR "+dll.entry+" threw across the C ABI"); }
    }
}
void ensureResources() {
    // Plugins may invoke D3DX during their entry callback. Avoid recursive call_once.
    if (initializingResources) return;
    std::call_once(resourceOnce, [] {
        initializingResources = true;
        struct Reset { ~Reset() { initializingResources = false; } } reset;
        try {
            resources = fd::discover(modsDirectory);
            for (auto& message : resources.messages) log(message);
            for (const auto& mod : resources.mods) {
                size_t shaders = 0;
                for (auto& fragment : mod.shaders) shaders += fragment.techniques.size();
                { std::lock_guard<std::mutex> lock(statusMutex);
                  modStatus.emplace(mod.name,ModStatus{mod.name,mod.version,mod.dlls.size(),shaders,false,{},{}}); }
                fd::lua::ensureMod(mod.name);
            }
            // Publish the complete immutable resource list before invoking plugins.
            loadDlls();
            log("READY mods="+std::to_string(resources.mods.size())+" loadedDlls="+std::to_string(loadedDlls.size()));
        } catch (const std::exception& e) { log(std::string("ERROR resource initialization: ")+e.what()); }
        catch (...) { log("ERROR resource initialization"); }
    });
}
void diagnostics(ID3DXBuffer* buffer) {
    if (buffer) log(std::string(static_cast<const char*>(buffer->GetBufferPointer()), std::min<size_t>(buffer->GetBufferSize(), 16000)));
}
bool compile(const std::string& source, const D3DXMACRO* defines, LPD3DXINCLUDE include, DWORD flags, ID3DXEffectCompiler** output) {
    ID3DXEffectCompiler* compiler = nullptr;
    ID3DXBuffer *errors = nullptr, *code = nullptr;
    auto hr = realCompiler(source.data(), UINT(source.size()), defines, include, flags, &compiler, &errors);
    if (FAILED(hr)) diagnostics(errors);
    if (errors) { errors->Release(); errors = nullptr; }
    if (SUCCEEDED(hr) && compiler) {
        hr = compiler->CompileEffect(flags & ~D3DXSHADER_USE_LEGACY_D3DX9_31_DLL, &code, &errors);
        if (FAILED(hr)) diagnostics(errors);
        if (code) code->Release();
        if (errors) errors->Release();
        if (SUCCEEDED(hr)) { *output = compiler; return true; }
    }
    if (compiler) compiler->Release();
    return false;
}
HRESULT WINAPI compileHook(LPCSTR source, UINT length, const D3DXMACRO* defines,
    LPD3DXINCLUDE include, DWORD flags, LPD3DXEFFECTCOMPILER* output, LPD3DXBUFFER* errors) {
    try {
        ensureResources();
        if (output && fd::meshSource(source, length)) {
            std::string accepted(source, length);
            ID3DXEffectCompiler* last = nullptr;
            for (const auto& mod : resources.mods) {
                if (mod.shaders.empty()) continue;
                auto combined = fd::append(accepted, mod);
                ID3DXEffectCompiler* candidate = nullptr;
                if (compile(combined, defines, include, flags, &candidate)) {
                    bool complete = true;
                    for (const auto& f : mod.shaders) for (const auto& name : f.techniques)
                        if (!candidate->GetTechniqueByName(name.c_str())) { log("SHADER_ERROR missing declared technique "+name); complete = false; }
                    if (complete) {
                        if (last) last->Release();
                        last = candidate;
                        accepted = std::move(combined);
                        { std::lock_guard<std::mutex> lock(statusMutex); modStatus.at(mod.name).compiled = true; }
                        log("SHADER_ACCEPT "+mod.name+" files="+std::to_string(mod.shaders.size()));
                        continue;
                    }
                    candidate->Release();
                }
                log("SHADER_REJECT "+mod.name+"; retained original effect and previously accepted mods");
                { std::lock_guard<std::mutex> lock(statusMutex); modStatus.at(mod.name).compiled = false; modStatus.at(mod.name).shaders.clear(); }
            }
            if (last) {
                *output = last;
                if (errors) *errors = nullptr;
                log("COMPILED augmented mesh effect");
                return S_OK;
            }
        }
    } catch (const std::exception& e) { log(std::string("ERROR compiler hook: ")+e.what()); }
    catch (...) { log("ERROR compiler hook"); }
    return realCompiler(source, length, defines, include, flags, output, errors);
}
HRESULT WINAPI effectHook(LPDIRECT3DDEVICE9 device, LPCVOID source, UINT length, const D3DXMACRO* defines,
    LPD3DXINCLUDE include, DWORD flags, LPD3DXEFFECTPOOL pool, LPD3DXEFFECT* effect, LPD3DXBUFFER* errors) {
    try { ensureResources(); } catch (...) { log("ERROR effect resource initialization"); }
    auto hr = realEffect(device, source, length, defines, include, flags, pool, effect, errors);
    try {
        // Stock mesh-effect parameter; no consumer-specific technique assumptions.
        if (SUCCEEDED(hr) && effect && *effect && (*effect)->GetParameterByName(nullptr, "transPalette")) {
            for (auto& mod : resources.mods) {
                std::vector<std::string> available;
                for (auto& f : mod.shaders) for (auto& t : f.techniques) {
                    auto technique = (*effect)->GetTechniqueByName(t.c_str());
                    bool valid = technique && SUCCEEDED((*effect)->ValidateTechnique(technique));
                    log(std::string(valid ? "AVAILABLE " : "MISSING ")+t);
                    if (valid) available.push_back(t);
                }
                std::lock_guard<std::mutex> lock(statusMutex);
                auto& status = modStatus.at(mod.name);
                status.shaders = status.compiled ? std::move(available) : std::vector<std::string>{};
            }
        }
    } catch (...) { log("ERROR checking effect techniques"); }
    return hr;
}
}
extern "C" int __cdecl FDInitializeV1(const fd::HostApi* host, fd::Hooks* hooks) {
    if (!host || !hooks || host->size != sizeof(fd::HostApi) || host->version != fd::BootstrapApiVersion ||
        hooks->size != sizeof(fd::Hooks) || hooks->version != fd::BootstrapApiVersion || !host->modsDirectory || !host->compiler || !host->effect) return FD_FAILURE;
    try {
        std::call_once(hostOnce, [&] {
            modsDirectory = fd::fs::path(host->modsDirectory);
            realCompiler = host->compiler;
            realEffect = host->effect;
            wchar_t local[32768]{};
            if (GetEnvironmentVariableW(L"LOCALAPPDATA", local, 32768)) {
                auto dir = fd::fs::path(local)/"FireDragonModLoader";
                fd::fs::create_directories(dir);
                logFile = dir/("loader-"+std::to_string(GetCurrentProcessId())+".log");
            }
            log("BOOT FireDragonLoader 2 x86 JSON manifest API 1");
            fd::lua::configure(&modsSnapshot,&logsSnapshot,&recordLog);
            log(fd::lua::installRuntimeHooks() ? "LUA_HOOK supported FAF 3841 runtime attached" : "LUA_UNSUPPORTED executable fingerprint; Lua bridge disabled");
        });
        if (host->compiler != realCompiler || host->effect != realEffect) return FD_FAILURE;
        *hooks = {sizeof(fd::Hooks), fd::BootstrapApiVersion, &compileHook, &effectHook};
        return FD_SUCCESS;
    } catch (...) { return FD_FAILURE; }
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(module);
    return TRUE;
}
