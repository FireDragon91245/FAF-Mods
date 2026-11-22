// Filters only the candidate gates of FAF's CUnitPodAssist. Selection, distance,
// query order, dispatch and task lifetime remain in the original executable.
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include "FireDragonLoader.h"
namespace {
std::mutex gate;
void* activeSimulation=nullptr;
std::unordered_map<uint32_t,unsigned> workers, targets;
unsigned calls=0, drops=0, lastWorker=0,lastTarget=0,lastFlags=0,lastTargetFlags=0;
template<class T> T read(void* unit,unsigned offset) { return *reinterpret_cast<T*>(static_cast<char*>(unit)+offset); }
}
extern "C" __attribute__((force_align_arg_pointer)) int __cdecl rscAllowed(void* worker,void* target) {
    if (!worker || !target) return 1;
    std::lock_guard<std::mutex> lock(gate);
    void* simulation=read<void*>(worker,0x150);
    // A later session may disable this mod while the DLL remains loaded.
    // Never apply metadata from the old simulation to its reused entity IDs.
    if (activeSimulation && activeSimulation!=simulation) { workers.clear();targets.clear(); }
    activeSimulation=simulation;
    ++calls;lastWorker=read<uint32_t>(worker,0x70);lastTarget=read<uint32_t>(target,0x70);
    const auto it=workers.find(lastWorker);
    if (it==workers.end() || !it->second) return 1;
    const unsigned flags=it->second;lastFlags=flags;
    const auto t=targets.find(read<uint32_t>(target,0x70));
    lastTargetFlags=t==targets.end()?0:t->second;
    if (t!=targets.end() && ((t->second&2) || ((flags&2) && (t->second&1)))) { ++drops;return 0; }
    if ((flags&1) && read<void*>(worker,0x154)!=read<void*>(target,0x154)) {
        return !read<unsigned char>(target,0xa0) && read<float>(target,0x98)<read<float>(target,0x9c);
    }
    return 1;
}
// Preserve general registers and flags. These gates have no live XMM lanes.
extern "C" __attribute__((naked)) void nearbyOrigin() {
    asm volatile("pushfl; pushal; push %esi; push 0x1c(%edi); call _rscAllowed; add $8,%esp; test %eax,%eax; jz 1f; popal; popfl; mov (%esi),%edx; mov 0x3c(%edx),%eax; push $15; push $0x61dc5c; ret; 1: popal; popfl; push $0x61dd3a; ret");
}
extern "C" __attribute__((naked)) void nearbyResolved() {
    asm volatile("pushfl; pushal; push %esi; push 0x1c(%edi); call _rscAllowed; add $8,%esp; test %eax,%eax; jz 1f; popal; popfl; mov (%esi),%edx; mov 0x14(%edx),%eax; mov %esi,%ecx; push $0x61dce2; ret; 1: popal; popfl; push $0x61dd3a; ret");
}
extern "C" __attribute__((naked)) void focusedHost() {
    asm volatile("pushfl; pushal; push %ecx; push 0x1c(%esi); call _rscAllowed; add $8,%esp; test %eax,%eax; jz 1f; popal; popfl; mov (%ecx),%eax; mov 0x3c(%eax),%edx; push $38; push $0x61de91; ret; 1: popal; popfl; push $0x61dfff; ret");
}
extern "C" __attribute__((naked)) void focusedTarget() {
    asm volatile("pushfl; pushal; push %edi; push 0x1c(%esi); call _rscAllowed; add $8,%esp; test %eax,%eax; jz 1f; popal; popfl; test %edi,%edi; jz 2f; push $0x61df03; ret; 2: push $0x61df5e; ret; 1: popal; popfl; push $0x61dfff; ret");
}
namespace {
uint32_t fingerprint(uintptr_t start,unsigned size) {
    uint32_t h=2166136261u;
    for (unsigned i=0;i<size;++i) h=(h^reinterpret_cast<unsigned char*>(start)[i])*16777619u;
    return h;
}
struct Patch { uintptr_t address; void (*hook)(); unsigned size; unsigned char original[8]; };
Patch patches[]={{0x61dc55,nearbyOrigin,7,{}},{0x61dcdb,nearbyResolved,7,{}},
                 {0x61de8a,focusedHost,7,{}},{0x61defd,focusedTarget,8,{}}};
bool patch(Patch& p,bool install) {
    DWORD prior;
    if (!VirtualProtect(reinterpret_cast<void*>(p.address),p.size,PAGE_EXECUTE_READWRITE,&prior)) return false;
    auto bytes=reinterpret_cast<unsigned char*>(p.address);
    if (install) {
        std::memcpy(p.original,bytes,p.size); std::memset(bytes,0x90,p.size); bytes[0]=0xe9;
        const uint32_t displacement=reinterpret_cast<uintptr_t>(p.hook)-p.address-5;
        std::memcpy(bytes+1,&displacement,4);
    } else std::memcpy(bytes,p.original,p.size);
    FlushInstructionCache(GetCurrentProcess(),bytes,p.size);
    DWORD ignored; VirtualProtect(bytes,p.size,prior,&ignored);
    return true;
}
int FD_CALL debug(const FDLuaStack* api,FDLuaCall* call,void*) {
    std::lock_guard<std::mutex> lock(gate);
    const std::string json="{\"calls\":"+std::to_string(calls)+",\"drops\":"+std::to_string(drops)+",\"worker\":"+std::to_string(lastWorker)+",\"target\":"+std::to_string(lastTarget)+",\"flags\":"+std::to_string(lastFlags)+",\"targetFlags\":"+std::to_string(lastTargetFlags)+",\"workers\":"+std::to_string(workers.size())+",\"targets\":"+std::to_string(targets.size())+"}";
    api->pushJson(call,json.c_str());return 1;
}
int FD_CALL reset(const FDLuaStack*,FDLuaCall*,void*) {
    std::lock_guard<std::mutex> lock(gate); workers.clear();targets.clear();activeSimulation=nullptr;return 0;
}
int FD_CALL worker(const FDLuaStack* api,FDLuaCall* call,void*) {
    if (api->argumentCount(call)!=2 || api->argumentType(call,1)!=FD_LUA_NUMBER || api->argumentType(call,2)!=FD_LUA_NUMBER) return -1;
    const uint32_t id=static_cast<uint32_t>(api->number(call,1));
    const unsigned flags=static_cast<unsigned>(api->number(call,2));
    std::lock_guard<std::mutex> lock(gate); if(flags) workers[id]=flags;else workers.erase(id);return 0;
}
int FD_CALL target(const FDLuaStack* api,FDLuaCall* call,void*) {
    if (api->argumentCount(call)!=2 || api->argumentType(call,1)!=FD_LUA_NUMBER || api->argumentType(call,2)!=FD_LUA_NUMBER) return -1;
    const uint32_t id=static_cast<uint32_t>(api->number(call,1));
    const unsigned flags=static_cast<unsigned>(api->number(call,2));
    std::lock_guard<std::mutex> lock(gate); if(flags) targets[id]=flags;else targets.erase(id);return 0;
}
}
FD_MOD_ENTRY(RepairStationControl, TargetFilter) {
    if (!context || context->apiVersion!=FD_API_VERSION || !context->lua) return FD_FAILURE;
    if (reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))!=0x400000 ||
        fingerprint(0x61da00,0x448)!=0x4b4c322f || fingerprint(0x61de50,0x1c2)!=0xdbffd9ae) {
        context->log(FD_LOG_ERROR,"RSC native filter: unsupported or modified acquisition routines"); return FD_FAILURE;
    }
    unsigned installed=0;
    for (auto& p:patches) {
        if (!patch(p,true)) {
            while(installed) { patch(patches[--installed],false); }
            return FD_FAILURE;
        }
        ++installed;
    }
    if (context->lua->registerFunction(context,"Debug",debug,nullptr)!=FD_SUCCESS ||
        context->lua->registerFunction(context,"Reset",reset,nullptr)!=FD_SUCCESS ||
        context->lua->registerFunction(context,"Worker",worker,nullptr)!=FD_SUCCESS ||
        context->lua->registerFunction(context,"Target",target,nullptr)!=FD_SUCCESS) {
        while(installed) { patch(patches[--installed],false); }
        return FD_FAILURE;
    }
    context->log(FD_LOG_INFO,"RSC native candidate gates installed; original acquisition and dispatch retained");
    return FD_SUCCESS;
}
