#pragma once
#include <windows.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <string_view>
#include <vector>
#include "nlohmann/json.hpp"

namespace fd {
namespace fs = std::filesystem;

struct Fragment {
    std::string label, source;
    std::vector<std::string> techniques;
};

struct NativeDll {
    fs::path path;
    std::string entry;
};

struct Mod {
    std::string name;
    int version = 1;
    fs::path root;
    std::vector<Fragment> shaders;
    std::vector<NativeDll> dlls;
};

struct Resources {
    std::vector<Mod> mods;
    std::vector<std::string> messages;
};

inline std::string utf8(const std::wstring& value) {
    if (value.empty())
        return {};
    int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), int(value.size()),
                                nullptr, 0, nullptr, nullptr);
    if (!n)
        throw std::runtime_error("invalid Unicode path");
    std::string out(n, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), int(value.size()), out.data(),
                        n, nullptr, nullptr);
    return out;
}

inline bool identifier(const std::string& s) {
    auto letter = [](char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    };
    if (s.empty() || s.size() > 128 || !letter(s[0]))
        return false;
    return std::all_of(s.begin(), s.end(),
                       [&](char c) { return letter(c) || (c >= '0' && c <= '9'); });
}

inline std::string symbolName(std::string_view s) {
    std::string out;
    for (char c : s)
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')
            out += c;
    if (!identifier(out))
        throw std::runtime_error("name cannot form an ASCII C identifier; specify a valid name");
    return out;
}

inline std::wstring pathKey(const fs::path& path) {
    auto key = path.wstring();
    std::transform(key.begin(), key.end(), key.begin(), [](wchar_t c) { return towlower(c); });
    return key;
}

inline std::string readText(const fs::path& path, size_t maxSize = 2 * 1024 * 1024) {
    auto size = fs::file_size(path);
    if (!size || size > maxSize)
        throw std::runtime_error("text file is empty or exceeds size limit");
    std::ifstream f(path, std::ios::binary);
    std::string data(size, '\0');
    if (!f.read(data.data(), std::streamsize(size)))
        throw std::runtime_error("cannot read text file");
    if (data.find('\0') != std::string::npos)
        throw std::runtime_error("text file contains NUL");
    return data;
}

inline fs::path resourcePath(const fs::path& root, const std::string& value) {
    if (value.empty() || value.find('\0') != std::string::npos ||
        value.find(':') != std::string::npos)
        throw std::runtime_error("invalid resource path");
    auto relative = fs::path(std::u8string(value.begin(), value.end()));
    if (relative.is_absolute() || relative.has_root_name() || relative.has_root_directory())
        throw std::runtime_error("resource path must be relative");
    auto full = fs::canonical(root / relative);
    auto inRoot = full.lexically_relative(root);
    if (inRoot.empty() || *inRoot.begin() == L".." || !fs::is_regular_file(full))
        throw std::runtime_error("resource escapes mod directory or is not a file");
    return full;
}

inline nlohmann::json parseManifest(const fs::path& path) {
    std::vector<std::set<std::string>> objects;
    auto callback = [&](int depth, nlohmann::json::parse_event_t event, nlohmann::json& value) {
        if (depth > 32)
            throw std::runtime_error("JSON nesting exceeds 32");
        using Event = nlohmann::json::parse_event_t;
        if (event == Event::object_start)
            objects.emplace_back();
        if (event == Event::key && !objects.back().insert(value.get<std::string>()).second)
            throw std::runtime_error("duplicate JSON key");
        if (event == Event::object_end)
            objects.pop_back();
        return true;
    };
    auto result = nlohmann::json::parse(readText(path, 64 * 1024), callback);
    if (!result.is_object())
        throw std::runtime_error("manifest must be a JSON object");
    return result;
}

inline Mod parseMod(const fs::path& folder) {
    Mod mod;
    mod.root = fs::canonical(folder);
    auto json = parseManifest(mod.root / "firedragonmod.json");
    for (auto it = json.begin(); it != json.end(); ++it)
        if (it.key() != "schemaVersion" && it.key() != "version" && it.key() != "name" &&
            it.key() != "dlls" && it.key() != "shaders")
            throw std::runtime_error("unknown manifest field: " + it.key());
    if (json.contains("schemaVersion") &&
        (!json["schemaVersion"].is_number_integer() || json["schemaVersion"] != 1))
        throw std::runtime_error("unsupported schemaVersion");
    mod.name = json.contains("name") ? json.at("name").get<std::string>()
                                     : symbolName(utf8(folder.filename().wstring()));
    if (!identifier(mod.name))
        throw std::runtime_error("name must be an ASCII C identifier");
    if (json.contains("version")) {
        if (!json["version"].is_number_integer() || json["version"] < 1 ||
            json["version"] > 16777215)
            throw std::runtime_error("version must be an integer in 1..16777215");
        mod.version = json["version"].get<int>();
    }
    if (json.contains("shaders")) {
        const auto& shaders = json["shaders"];
        if (!shaders.is_object() || shaders.size() > 128)
            throw std::runtime_error("shaders must map up to 128 technique names to paths");
        std::map<std::wstring, size_t> files;
        size_t total = 0;
        for (auto it = shaders.begin(); it != shaders.end(); ++it) {
            if (!identifier(it.key()) || !it.value().is_string())
                throw std::runtime_error("invalid shader technique name/path");
            auto path = resourcePath(mod.root, it.value().get<std::string>());
            auto key = pathKey(path);
            if (!files.count(key)) {
                auto source = readText(path);
                total += source.size();
                if (total > 8 * 1024 * 1024)
                    throw std::runtime_error("shader sources exceed 8 MiB per mod");
                files[key] = mod.shaders.size();
                mod.shaders.push_back(
                    {mod.name + "/" + utf8(path.lexically_relative(mod.root).wstring()),
                     std::move(source),
                     {}});
            }
            mod.shaders[files.at(key)].techniques.push_back(it.key());
        }
    }
    if (json.contains("dlls")) {
        const auto& dlls = json["dlls"];
        if (!dlls.is_array() || dlls.size() > 32)
            throw std::runtime_error("dlls must be an array of up to 32 relative paths");
        std::set<std::wstring> files;
        std::set<std::string> entries;
        for (const auto& item : dlls) {
            if (!item.is_string())
                throw std::runtime_error("DLL path must be a string");
            auto path = resourcePath(mod.root, item.get<std::string>());
            if (pathKey(path.extension()) != L".dll")
                throw std::runtime_error("DLL path must end in .dll");
            auto entry = "FDEntry" + mod.name + symbolName(utf8(path.stem().wstring()));
            if (!files.insert(pathKey(path)).second || !entries.insert(entry).second)
                throw std::runtime_error("duplicate DLL path or entry symbol");
            mod.dlls.push_back({path, entry});
        }
    }
    return mod;
}

inline Resources discover(const fs::path& mods) {
    Resources out;
    if (!fs::is_directory(mods)) {
        out.messages.push_back("ERROR mods directory not found");
        return out;
    }
    std::vector<fs::path> folders;
    for (auto& e : fs::directory_iterator(mods))
        if (e.is_directory() && fs::is_regular_file(e.path() / "firedragonmod.json"))
            folders.push_back(e.path());
    std::sort(folders.begin(), folders.end(),
              [](const auto& a, const auto& b) { return pathKey(a) < pathKey(b); });
    if (folders.size() > 128) {
        out.messages.push_back("ERROR more than 128 manifests; refusing batch");
        return out;
    }
    std::set<std::string> names, techniques;
    size_t total = 0;
    for (const auto& folder : folders) {
        try {
            auto mod = parseMod(folder);
            if (names.count(mod.name))
                throw std::runtime_error("duplicate mod name");
            size_t added = 0;
            for (auto& f : mod.shaders) {
                added += f.source.size();
                for (auto& t : f.techniques)
                    if (techniques.count(t))
                        throw std::runtime_error("duplicate shader technique: " + t);
            }
            if (total + added > 32 * 1024 * 1024)
                throw std::runtime_error("global shader source limit exceeds 32 MiB");
            total += added;
            names.insert(mod.name);
            for (auto& f : mod.shaders)
                for (auto& t : f.techniques)
                    techniques.insert(t);
            out.messages.push_back("MOD " + mod.name +
                                   " shaders=" + std::to_string(mod.shaders.size()) +
                                   " dlls=" + std::to_string(mod.dlls.size()));
            out.mods.push_back(std::move(mod));
        } catch (const std::exception& e) {
            out.messages.push_back("REJECT " + utf8(folder.filename().wstring()) + ": " + e.what());
        }
    }
    return out;
}

inline bool meshSource(const char* data, size_t size) {
    if (!data || size > 8 * 1024 * 1024)
        return false;
    std::string_view s(data, size);
    return s.find("BONE_MAXIMUM") != s.npos && s.find("transPalette") != s.npos &&
           s.find("STAGE_POSTWATER") != s.npos;
}

inline std::string append(const std::string& base, const Mod& mod) {
    std::string out(base);
    while (!out.empty() && out.back() == '\0')
        out.pop_back();
    for (const auto& f : mod.shaders) {
        out += "\n// FireDragon mod: " + mod.name + "\n#line 1\n";
        out += f.source;
        out += '\n';
    }
    return out;
}
} // namespace fd
