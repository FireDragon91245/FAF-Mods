cmake_minimum_required(VERSION 3.25)
project(FireDragonModLoader VERSION 3.0 LANGUAGES C CXX)
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "Build with a Windows x86 toolchain (32-bit MinGW-w64).")
endif()
set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
add_compile_options(-Wall -Wextra -Wno-cast-function-type)
add_link_options(-static -static-libgcc -static-libstdc++ -Wl,--no-insert-timestamp)
include_directories(native/include)
include_directories(SYSTEM native/third_party)
add_library(fd_minhook STATIC native/third_party/minhook/src/buffer.c native/third_party/minhook/src/hook.c
    native/third_party/minhook/src/trampoline.c native/third_party/minhook/src/hde/hde32.c)
target_include_directories(fd_minhook PUBLIC native/third_party/minhook/include)
set(FD_NATIVE_SOURCES native/src/engine_profile.cpp native/src/native_symbols.cpp native/src/native_engine.cpp native/src/native_fields.cpp native/src/native_patches.cpp)
add_library(FireDragonLoader SHARED native/src/loader.cpp native/src/lua_bridge.cpp native/src/lua_runtime.cpp ${FD_NATIVE_SOURCES} native/src/loader.def)
target_link_libraries(FireDragonLoader PRIVATE fd_minhook bcrypt)
add_executable(native-test tests/native_runtime.cpp ${FD_NATIVE_SOURCES})
target_compile_definitions(native-test PRIVATE FD_NATIVE_TESTING)
target_compile_options(native-test PRIVATE -msse2 -UNDEBUG)
target_link_libraries(native-test PRIVATE fd_minhook bcrypt)
set_target_properties(FireDragonLoader PROPERTIES PREFIX "")
add_library(fd_dsound SHARED native/src/proxy_dsound.cpp native/src/dsound.def)
set_target_properties(fd_dsound PROPERTIES PREFIX "" OUTPUT_NAME dsound)
add_executable(loader-test tests/integration.cpp)
target_link_libraries(loader-test PRIVATE d3dx9_35 d3d9 dsound dxguid)
add_executable(resource-test tests/resources.cpp)
add_library(FixtureDependency SHARED tests/dependency.cpp)
set_target_properties(FixtureDependency PROPERTIES PREFIX "")
add_library(EngineHooks SHARED tests/plugin.cpp)
target_link_libraries(EngineHooks PRIVATE FixtureDependency)
set_target_properties(EngineHooks PROPERTIES PREFIX "")
add_library(Failing SHARED tests/plugin.cpp)
target_compile_definitions(Failing PRIVATE FD_FIXTURE_FAIL=1)
set_target_properties(Failing PROPERTIES PREFIX "")
add_library(Probe SHARED tests/lua_probe.cpp)
set_target_properties(Probe PROPERTIES PREFIX "")
add_library(NativePatches SHARED examples/NativePatches.cpp)
set_target_properties(NativePatches PROPERTIES PREFIX "")

# Only this test executable links a Lua runtime. Production always calls the
# fingerprint-verified host Lua functions; test_lua is never shipped or linked in.
file(GLOB FD_TEST_LUA_CORE CONFIGURE_DEPENDS native/third_party/test_lua/src/*.c)
add_library(fd_test_lua STATIC ${FD_TEST_LUA_CORE} native/third_party/test_lua/src/lib/lauxlib.c
    native/third_party/test_lua/src/lib/lbaselib.c native/third_party/test_lua/src/lib/ltablib.c
    native/third_party/test_lua/src/lib/lstrlib.c native/third_party/test_lua/src/lib/lmathlib.c)
target_include_directories(fd_test_lua PUBLIC native/third_party/test_lua/include)
target_compile_definitions(fd_test_lua PUBLIC LUA_NUMBER=float)
add_executable(lua-test tests/lua_bridge.cpp native/src/lua_bridge.cpp)
target_link_libraries(lua-test PRIVATE fd_test_lua)
add_executable(lua-script-test tests/lua_script.cpp)
target_link_libraries(lua-script-test PRIVATE fd_test_lua)

# Optional LLVM fixture verifies real PDB lookup of a non-exported function.
find_program(FD_CLANG NAMES clang)
find_program(FD_LLD_LINK NAMES lld-link)
if(FD_CLANG AND FD_LLD_LINK)
    set(FD_PDB_FIXTURE "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/SymbolFixture.dll")
    add_custom_command(OUTPUT "${FD_PDB_FIXTURE}"
        COMMAND "${FD_CLANG}" --target=i686-pc-windows-msvc -g -gcodeview -O0
            -fno-stack-protector -c "${CMAKE_CURRENT_SOURCE_DIR}/tests/pdb_fixture.cpp"
            -o "${CMAKE_CURRENT_BINARY_DIR}/pdb_fixture.obj"
        COMMAND "${FD_LLD_LINK}" /dll /noentry /debug /opt:noref /machine:x86
            "/out:${FD_PDB_FIXTURE}" "/pdb:${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/SymbolFixture.pdb"
            "${CMAKE_CURRENT_BINARY_DIR}/pdb_fixture.obj"
        DEPENDS tests/pdb_fixture.cpp VERBATIM)
    add_custom_target(pdb-fixture ALL DEPENDS "${FD_PDB_FIXTURE}")
endif()
