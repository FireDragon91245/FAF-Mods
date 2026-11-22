#pragma once
#include "FireDragonPatches.h"
#include <string>
#include <vector>

namespace fd::native {
struct Symbol {
    std::string name;
    uintptr_t address = 0;
    uint32_t size = 0;
    std::vector<unsigned char> original;
};

std::string executableHash();
bool initialize();
bool initializeEngineBindings();
bool addBinding(const char* name, uintptr_t address, uint32_t size, uint32_t fingerprint);
bool definePattern(const FDSymbolPattern& pattern, bool& inserted);
void eraseSymbol(const std::string& name);
const char* profile();
const Symbol* find(const char* name);
uint32_t symbolCount();
const Symbol* symbolAt(uint32_t index);
const FDNativeApi* api();
const FDEngineApi* engineApi();
const FDFieldsApi* fieldsApi();
void beginEntry(const FDModContext* context);
bool endEntry(bool success);
const char* lastError();

#ifdef FD_NATIVE_TESTING
void testProfile(std::vector<Symbol> symbols);
void removeTestPatches();
#endif
} // namespace fd::native
