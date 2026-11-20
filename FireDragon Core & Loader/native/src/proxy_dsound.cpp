#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include "bootstrap.hpp"
static_assert(sizeof(void*) == 4, "FAF needs a 32-bit bootstrap");
namespace {
HMODULE systemSound() {
    static HMODULE dll = [] {
        wchar_t path[MAX_PATH]{};
        UINT n = GetSystemDirectoryW(path, MAX_PATH);
        if (!n || n >= MAX_PATH-12) return HMODULE(nullptr);
        wcscat_s(path, L"\\dsound.dll");
        return LoadLibraryW(path);
    }();
    return dll;
}
template<class T> T soundFunction(const char* name) {
    auto dll = systemSound();
    return dll ? reinterpret_cast<T>(GetProcAddress(dll, name)) : nullptr;
}
}
#define FORWARD(name, args, values) extern "C" HRESULT WINAPI FD_##name args { \
    auto fn = soundFunction<decltype(&name)>(#name); return fn ? fn values : E_FAIL; }
FORWARD(DirectSoundCreate, (LPCGUID a, LPDIRECTSOUND* b, LPUNKNOWN c), (a,b,c))
FORWARD(DirectSoundCreate8, (LPCGUID a, LPDIRECTSOUND8* b, LPUNKNOWN c), (a,b,c))
FORWARD(DirectSoundEnumerateA, (LPDSENUMCALLBACKA a, LPVOID b), (a,b))
FORWARD(DirectSoundEnumerateW, (LPDSENUMCALLBACKW a, LPVOID b), (a,b))
FORWARD(DirectSoundCaptureCreate, (LPCGUID a, LPDIRECTSOUNDCAPTURE* b, LPUNKNOWN c), (a,b,c))
FORWARD(DirectSoundCaptureCreate8, (LPCGUID a, LPDIRECTSOUNDCAPTURE8* b, LPUNKNOWN c), (a,b,c))
FORWARD(DirectSoundCaptureEnumerateA, (LPDSENUMCALLBACKA a, LPVOID b), (a,b))
FORWARD(DirectSoundCaptureEnumerateW, (LPDSENUMCALLBACKW a, LPVOID b), (a,b))
FORWARD(GetDeviceID, (LPCGUID a, LPGUID b), (a,b))
FORWARD(DirectSoundFullDuplexCreate, (LPCGUID a, LPCGUID b, LPCDSCBUFFERDESC c, LPCDSBUFFERDESC d, HWND e,
    DWORD f, LPDIRECTSOUNDFULLDUPLEX* g, LPDIRECTSOUNDCAPTUREBUFFER8* h, LPDIRECTSOUNDBUFFER8* i, LPUNKNOWN j), (a,b,c,d,e,f,g,h,i,j))
extern "C" HRESULT WINAPI FD_DllCanUnloadNow() {
    auto fn = soundFunction<HRESULT(WINAPI*)()>("DllCanUnloadNow"); return fn ? fn() : S_FALSE;
}
extern "C" HRESULT WINAPI FD_DllGetClassObject(REFCLSID a, REFIID b, LPVOID* c) {
    auto fn = soundFunction<HRESULT(WINAPI*)(REFCLSID,REFIID,LPVOID*)>("DllGetClassObject"); return fn ? fn(a,b,c) : E_FAIL;
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) fd::bootstrap::attach(module);
    return TRUE;
}
