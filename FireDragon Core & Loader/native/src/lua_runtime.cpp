#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <vector>
#include "lua_bridge.hpp"
#include "MinHook.h"

namespace fd::lua {
namespace {
using ProtectedCall = int (__cdecl*)(lua_State*,int,int,int);
using Call = void (__cdecl*)(lua_State*,int,int);
ProtectedCall originalProtected;
Call originalCall;
int __cdecl protectedHook(lua_State* state, int arguments, int results, int errorHandler) {
    attach(state);
    return originalProtected(state,arguments,results,errorHandler);
}
void __cdecl callHook(lua_State* state, int arguments, int results) {
    attach(state);
    originalCall(state,arguments,results);
}
std::string imageHash() {
    wchar_t filename[32768]{};
    if (!GetModuleFileNameW(nullptr,filename,32768)) return {};
    std::ifstream file(std::filesystem::path(filename),std::ios::binary);
    if (!file) return {};
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    struct Cleanup {
        BCRYPT_ALG_HANDLE* algorithm; BCRYPT_HASH_HANDLE* hash;
        ~Cleanup() { if (*hash) BCryptDestroyHash(*hash); if (*algorithm) BCryptCloseAlgorithmProvider(*algorithm,0); }
    } cleanup{&algorithm,&hash};
    if (BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0) < 0) return {};
    DWORD objectSize = 0, bytes = 0;
    if (BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&objectSize),sizeof(objectSize),&bytes,0) < 0) return {};
    std::vector<unsigned char> object(objectSize);
    if (BCryptCreateHash(algorithm,&hash,object.data(),objectSize,nullptr,0,0) < 0) return {};
    char buffer[32768];
    while (file) {
        file.read(buffer,sizeof(buffer));
        if (file.gcount() && BCryptHashData(hash,reinterpret_cast<PUCHAR>(buffer),ULONG(file.gcount()),0) < 0) return {};
    }
    unsigned char digest[32]{};
    if (file.bad() || BCryptFinishHash(hash,digest,sizeof(digest),0) < 0) return {};
    std::ostringstream text;
    for (auto value : digest) text << std::hex << std::setfill('0') << std::setw(2) << unsigned(value);
    return text.str();
}
template<class T> T address(uintptr_t preferredAddress) {
    return reinterpret_cast<T>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+preferredAddress-0x400000);
}
}
bool installRuntimeHooks() {
    // Exact supported image. Never apply an address map merely because the file
    // calls itself ForgedAlliance.exe or reports a matching Lua/game version.
    if (imageHash() != "dff5e25ea82053dbbacf27ed20542fec3693b48006377581dcf7faf4ea9ec286") return false;
    Api api{};
#define API(member, va) api.member = address<decltype(api.member)>(va)
    API(gettop,0x90C590); API(settop,0x90C5A0); API(checkstack,0x90C460); API(type,0x90C740);
    API(tonumber,0x90C9F0); API(toboolean,0x90CA40); API(tostring,0x90CA90); API(touserdata,0x90CBB0);
    API(pushnil,0x90CD00); API(pushnumber,0x90CD40); API(pushlstring,0x90CD80); API(pushcclosure,0x90CED0);
    API(pushboolean,0x90CF80); API(pushlightuserdata,0x90CFC0); API(rawget,0x90D050); API(rawset,0x90D2A0);
    API(rawgeti,0x90D0A0); API(rawseti,0x90D2F0); API(newtable,0x90D110); API(pushvalue,0x90C6E0);
#undef API
    auto status = MH_Initialize();
    if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED) return false;
    auto protectedTarget = address<void*>(0x90D430);
    auto callTarget = address<void*>(0x90D400);
    if (MH_CreateHook(protectedTarget,reinterpret_cast<void*>(&protectedHook),reinterpret_cast<void**>(&originalProtected)) != MH_OK) return false;
    if (MH_CreateHook(callTarget,reinterpret_cast<void*>(&callHook),reinterpret_cast<void**>(&originalCall)) != MH_OK) {
        MH_RemoveHook(protectedTarget); return false;
    }
    setApi(api);
    if (MH_QueueEnableHook(protectedTarget) != MH_OK || MH_QueueEnableHook(callTarget) != MH_OK || MH_ApplyQueued() != MH_OK) {
        MH_DisableHook(protectedTarget); MH_DisableHook(callTarget);
        MH_RemoveHook(protectedTarget); MH_RemoveHook(callTarget);
        setApi({}); return false;
    }
    return true;
}
}
