// Version-specific game bindings belong to the engine adapter, not the patch resolver.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <cstring>
#include "native_runtime.hpp"

namespace fd::native {
namespace {
const char* selectedProfile = nullptr;
}

std::string executableHash() {
    wchar_t filename[32768]{};
    if (!GetModuleFileNameW(nullptr, filename, 32768))
        return {};
    std::ifstream file(std::filesystem::path(filename), std::ios::binary);
    if (!file)
        return {};
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;

    struct Cleanup {
        BCRYPT_ALG_HANDLE& algorithm;
        BCRYPT_HASH_HANDLE& hash;

        ~Cleanup() {
            if (hash)
                BCryptDestroyHash(hash);
            if (algorithm)
                BCryptCloseAlgorithmProvider(algorithm, 0);
        }
    } cleanup{algorithm, hash};

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
        return {};
    DWORD objectSize = 0, bytes = 0;
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objectSize),
                          sizeof(objectSize), &bytes, 0) < 0)
        return {};
    std::vector<unsigned char> object(objectSize);
    if (BCryptCreateHash(algorithm, &hash, object.data(), objectSize, nullptr, 0, 0) < 0)
        return {};
    char buffer[32768];
    while (file) {
        file.read(buffer, sizeof(buffer));
        if (file.gcount() &&
            BCryptHashData(hash, reinterpret_cast<PUCHAR>(buffer), ULONG(file.gcount()), 0) < 0)
            return {};
    }
    unsigned char digest[32]{};
    if (file.bad() || BCryptFinishHash(hash, digest, sizeof(digest), 0) < 0)
        return {};
    std::ostringstream text;
    for (auto value : digest)
        text << std::hex << std::setfill('0') << std::setw(2) << unsigned(value);
    return text.str();
}

bool initializeEngineBindings() {
    if (selectedProfile) {
        return true;
    }
    if (executableHash() != "dff5e25ea82053dbbacf27ed20542fec3693b48006377581dcf7faf4ea9ec286") {
        return false;
    }
    // Engine method ABIs and field layouts remain version-specific.
    const auto add = [](const char* name, uintptr_t preferred, uint32_t size, uint32_t hash) {
        const auto image = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        return addBinding(name, image + preferred - 0x400000, size, hash);
    };
#include "generated/native_method_symbols.inc"
    const std::pair<const char*, uintptr_t> luaSymbols[] = {
        {"lua_gettop", 0x90c590},      {"lua_settop", 0x90c5a0},
        {"lua_checkstack", 0x90c460},  {"lua_type", 0x90c740},
        {"lua_tonumber", 0x90c9f0},    {"lua_toboolean", 0x90ca40},
        {"lua_tostring", 0x90ca90},    {"lua_touserdata", 0x90cbb0},
        {"lua_pushnil", 0x90cd00},     {"lua_pushnumber", 0x90cd40},
        {"lua_pushlstring", 0x90cd80}, {"lua_pushcclosure", 0x90ced0},
        {"lua_pushboolean", 0x90cf80}, {"lua_pushlightuserdata", 0x90cfc0},
        {"lua_rawget", 0x90d050},      {"lua_rawset", 0x90d2a0},
        {"lua_rawgeti", 0x90d0a0},     {"lua_rawseti", 0x90d2f0},
        {"lua_newtable", 0x90d110},    {"lua_pushvalue", 0x90c6e0},
        {"lua_pcall", 0x90d430},       {"lua_call", 0x90d400}};
    for (auto& symbol : luaSymbols) {
        const uint32_t size = std::strcmp(symbol.first, "lua_call") == 0    ? 0x21
                              : std::strcmp(symbol.first, "lua_pcall") == 0 ? 0x9c
                                                                            : 0;
        const uint32_t expected = std::strcmp(symbol.first, "lua_call") == 0    ? 0x10c4c947
                                  : std::strcmp(symbol.first, "lua_pcall") == 0 ? 0xa25cd593
                                                                                : 0;
        if (!add(symbol.first, symbol.second, size, expected)) {
            return false;
        }
    }
    selectedProfile = "FAF 3841";
    return true;
}

bool initialize() {
    return initializeEngineBindings();
}

const char* profile() {
    return selectedProfile;
}
#ifdef FD_NATIVE_TESTING
void testEngineProfile() {
    selectedProfile = "Synthetic x86 test profile";
}
#endif
} // namespace fd::native
