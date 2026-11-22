#include "../native/src/resources.hpp"
#include <iostream>

int main() {
    try {
        int checks = 0;
        auto check = [&](bool result) {
            ++checks;
            if (!result)
                throw std::runtime_error("resource contract check " + std::to_string(checks));
        };
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
        // C++20+ filesystem strings use char8_t. Verify both directions of the
        // UTF-8 boundary used for manifests and exposed DLL status names.
        auto unicodeName = fd::fs::path(u8"unicode_\u00e9_\u96ea.fx");
        const std::string encodedName = "unicode_\xc3\xa9_\xe9\x9b\xaa.fx";
        check(fd::utf8(unicodeName.generic_wstring()) == encodedName);
        auto root = fd::fs::temp_directory_path() /
                    (L"FireDragonUnicode-" + std::to_wstring(GetCurrentProcessId()));
        if (!fd::fs::create_directory(root))
            throw std::runtime_error("Unicode test directory already exists");

        struct Cleanup {
            fd::fs::path file, directory;

            ~Cleanup() {
                std::error_code error;
                fd::fs::remove(file, error);
                fd::fs::remove(directory, error);
            }
        } cleanup{root / unicodeName, root};

        std::ofstream(cleanup.file, std::ios::binary) << "test";
        check(fd::resourcePath(root, encodedName) == fd::fs::canonical(cleanup.file));
        std::cout << "PASS: " << checks << " native resource/naming/source contract checks\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n';
        return 1;
    }
}
