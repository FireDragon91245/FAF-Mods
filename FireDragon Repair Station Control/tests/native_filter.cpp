// Runs the actual native predicate with synthetic engine-layout units.
#include "../native/TargetFilter.cpp"
#include <cassert>
#include <cstdio>
int main() {
    alignas(16) unsigned char worker[0x160]{}, own[0x160]{}, ally[0x160]{};
    auto put=[](void* p,unsigned offset,auto value) { std::memcpy(static_cast<char*>(p)+offset,&value,sizeof(value)); };
    put(worker,0x70,uint32_t(10));put(own,0x70,uint32_t(20));put(ally,0x70,uint32_t(30));
    put(worker,0x154,uintptr_t(1));put(own,0x154,uintptr_t(1));put(ally,0x154,uintptr_t(2));
    put(own,0x98,100.f);put(own,0x9c,100.f);put(ally,0x98,100.f);put(ally,0x9c,100.f);
    for (unsigned flags=0;flags<4;++flags) {
        workers[10]=flags;targets.clear();
        assert(rscAllowed(worker,own));assert(rscAllowed(worker,ally)==!(flags&1));
        put(ally,0x98,50.f);assert(rscAllowed(worker,ally));
        put(ally,0xa0,static_cast<unsigned char>(1));assert(rscAllowed(worker,ally)==!(flags&1));
        put(ally,0xa0,static_cast<unsigned char>(0));put(ally,0x98,100.f);
        targets[20]=1;assert(rscAllowed(worker,own)==!(flags&2));
        targets[20]=2;assert(rscAllowed(worker,own)==!flags);
    }
    workers.clear();assert(rscAllowed(worker,own));
    put(worker,0x150,uintptr_t(10));assert(rscAllowed(worker,own));
    workers[10]=2;targets[20]=1;assert(!rscAllowed(worker,own));
    put(worker,0x150,uintptr_t(20));assert(rscAllowed(worker,own));
    assert(workers.empty() && targets.empty());
    std::puts("PASS: native predicate, all restriction combinations, own/allied construction, completed repairs, silos and invisible workers");
}
