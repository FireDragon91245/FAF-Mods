// A private function is discoverable only through the generated PDB.
extern "C" __declspec(noinline) int DebugOnly(int value) {
    return value + 17;
}

extern "C" __declspec(dllexport) int ExportedDebugCaller(int value) {
    return DebugOnly(value);
}
