#include "../native/src/resources.hpp"
#include <iostream>
int main() {
    try {
        int checks = 0;
        auto check = [&](bool result) { ++checks; if (!result) throw std::runtime_error("resource contract check "+std::to_string(checks)); };
        check(fd::symbolName("FireDragon Modular Shields") == "FireDragonModularShields");
        check(fd::symbolName("Engine-Hooks") == "EngineHooks");
        check(fd::identifier("ModularHexDome"));
        check(!fd::identifier("4Bad"));
        check(!fd::identifier("Has Space"));
        std::string source = "BONE_MAXIMUM transPalette STAGE_POSTWATER";
        check(fd::meshSource(source.data(), source.size()));
        check(!fd::meshSource("unrelated effect", 16));
        fd::Mod mod;
        mod.name = "Fixture";
        mod.shaders.push_back({"test.fx", "technique Added {}", {"Added"}});
        auto merged = fd::append(std::string("base\0", 5), mod);
        check(merged.find('\0') == std::string::npos);
        check(merged.find("technique Added") != std::string::npos);
        check(merged.rfind("base", 0) == 0);
        std::cout << "PASS: " << checks << " native resource/naming/source contract checks\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; return 1; }
}
