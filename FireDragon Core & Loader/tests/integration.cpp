#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <dsound.h>
#include <d3dx9effect.h>
#include <iostream>
#include <filesystem>
#include <fstream>
#include <iterator>

extern "C" __declspec(dllexport) int __cdecl FDTestReenter() {
    const char* source = "float4 ps():COLOR{return 1;} technique FixtureReentry { pass p { PixelShader=compile ps_2_0 ps(); } }";
    ID3DXEffectCompiler* compiler = nullptr;
    auto hr = D3DXCreateEffectCompiler(source, UINT(strlen(source)), nullptr, nullptr, 0, &compiler, nullptr);
    if (compiler) compiler->Release();
    return SUCCEEDED(hr) ? 0 : 1;
}

void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
int main(int argc, char** argv) {
    try {
        require(argc >= 2, "usage: loader-test.exe full-mesh.fx [+ExpectedTechnique|-AbsentTechnique ...]");
        // A real import forces Windows to load our adjacent proxy automatically.
        IDirectSound* sound = nullptr;
        auto soundHr = DirectSoundCreate(nullptr, &sound, nullptr);
        require(SUCCEEDED(soundHr) && sound, "DirectSound forwarding failed");
        sound->Release();
        auto proxy = GetModuleHandleW(L"dsound.dll");
        require(proxy != nullptr, "sound DLL not loaded");
        for (const auto& e : {"DirectSoundCreate", "DirectSoundEnumerateA", "DirectSoundEnumerateW", "DllCanUnloadNow", "DllGetClassObject", "DirectSoundCaptureCreate", "DirectSoundCaptureEnumerateA", "DirectSoundCaptureEnumerateW", "GetDeviceID", "DirectSoundFullDuplexCreate", "DirectSoundCreate8", "DirectSoundCaptureCreate8"})
            require(GetProcAddress(proxy, e) != nullptr, "missing sound export");
        require(GetProcAddress(proxy, MAKEINTRESOURCEA(1)) == GetProcAddress(proxy, "DirectSoundCreate"), "DirectSound ordinal 1 incorrect");
        std::ifstream input(std::filesystem::u8path(argv[1]), std::ios::binary);
        require(bool(input), "cannot open effect source");
        std::string source((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
        ID3DXEffectCompiler* compiler = nullptr;
        ID3DXBuffer* errors = nullptr;
        // Match the flags used by the FA engine, including its legacy compiler.
        DWORD flags = D3DXSHADER_DEBUG | D3DXSHADER_USE_LEGACY_D3DX9_31_DLL;
        auto hr = D3DXCreateEffectCompiler(source.data(), UINT(source.size()), nullptr, nullptr, flags, &compiler, &errors);
        if (errors) { std::cerr << static_cast<char*>(errors->GetBufferPointer()) << '\n'; errors->Release(); errors = nullptr; }
        require(SUCCEEDED(hr) && compiler, "effect parse failed");
        ID3DXBuffer* code = nullptr;
        hr = compiler->CompileEffect(D3DXSHADER_DEBUG, &code, &errors);
        if (errors) { std::cerr << static_cast<char*>(errors->GetBufferPointer()) << '\n'; errors->Release(); errors = nullptr; }
        compiler->Release();
        require(SUCCEEDED(hr) && code, "full effect compile failed");
        auto d3d = Direct3DCreate9(D3D_SDK_VERSION);
        require(d3d != nullptr, "Direct3D9 unavailable");
        HWND window = CreateWindowW(L"STATIC", L"FireDragon loader integration test", WS_POPUP, 0, 0, 64, 64, nullptr, nullptr, nullptr, nullptr);
        D3DPRESENT_PARAMETERS pp{};
        pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.hDeviceWindow = window;
        IDirect3DDevice9* device = nullptr;
        hr = d3d->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &device);
        require(SUCCEEDED(hr) && device, "test D3D9 device creation failed");
        ID3DXEffect* effect = nullptr;
        hr = D3DXCreateEffect(device, code->GetBufferPointer(), DWORD(code->GetBufferSize()), nullptr, nullptr, D3DXSHADER_DEBUG, nullptr, &effect, &errors);
        if (errors) { std::cerr << static_cast<char*>(errors->GetBufferPointer()) << '\n'; errors->Release(); }
        require(SUCCEEDED(hr) && effect, "D3DXCreateEffect failed");
        require(effect->GetParameterByName(nullptr, "transPalette") != nullptr, "stock mesh parameters were lost");
        for (int i = 2; i < argc; ++i) {
            std::string request(argv[i]);
            require(request.size() > 1 && (request[0] == '+' || request[0] == '-'), "invalid technique expectation");
            auto technique = effect->GetTechniqueByName(request.c_str()+1);
            require((technique != nullptr) == (request[0] == '+'), ("technique availability: "+request).c_str());
            if (technique) require(SUCCEEDED(effect->ValidateTechnique(technique)), "technique invalid on D3D9 device");
        }
        effect->Release(); code->Release(); device->Release(); d3d->Release(); DestroyWindow(window);
        std::cout << "PASS: automatic bootstrap, sound forwarding, full mesh effect and GPU technique checks\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; return 1; }
}
