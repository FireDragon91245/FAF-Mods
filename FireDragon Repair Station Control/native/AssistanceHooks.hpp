#pragma once
#include "FireDragonPatches.hpp"

namespace RepairStationControl::AssistanceHooks {
using namespace FireDragon;

inline constexpr const char* Nearby = "Moho::CUnitPodAssist::TryIssueNearbyAssistTask";
inline constexpr const char* Focused = "Moho::CUnitPodAssist::TryIssueFocusedAssistTask";

// These verified FAF 3841 signatures and register conventions implement this
// mod's assistance policy. Core has no knowledge of them.
inline bool DefineFunctions(const Patches& patches) {
    return patches.DefineSymbol(
               Nearby,
               "6A FF 68 ?? ?? ?? ?? 64 A1 00 00 00 00 50 64 89 25 00 00 00 00 81 EC 54 02 00 00 "
               "53 55 33 ED 89 6C 24 0C 8B 4F 1C 8B 01 8B 50 60 56 FF D2 84 C0",
               0x448, 0x4b4c322f) &&
           patches.DefineSymbol(
               Focused,
               "64 A1 00 00 00 00 6A FF 68 ?? ?? ?? ?? 50 64 89 25 00 00 00 00 8B "
               "4E 1C 8B 01 8B 50 60 83 EC 20 53 57 FF D2 84 C0 0F 84 83 01 00 00 8B 46 34 85",
               0x1c2, 0xdbffd9ae);
}

inline constexpr unsigned char NearbyCandidateBytes[]{
    0x8b, 0x16, 0x8b, 0x42, 0x3c, 0x6a, 0x0f, 0x8b, 0xce, 0xff, 0xd0, 0x84, 0xc0, 0x0f, 0x85};
inline constexpr unsigned char NearbyResolvedBytes[]{0x8b, 0x16, 0x8b, 0x42, 0x14, 0x8b,
                                                     0xce, 0xff, 0xd0, 0x8b, 0x4f, 0x1c};
inline constexpr unsigned char NearbyContinueBytes[]{0x83, 0x44, 0x24, 0x14, 0x18, 0x83,
                                                     0x6c, 0x24, 0x10, 0x01, 0x0f, 0x85};
inline constexpr unsigned char FocusedHostBytes[]{0x8b, 0x01, 0x8b, 0x50, 0x3c, 0x6a, 0x26,
                                                  0xff, 0xd2, 0x84, 0xc0, 0x74, 0x36};
// Select after mov edi,eax: EDI now contains the resolved Unit*, including null.
inline constexpr unsigned char FocusedResolvedBytes[]{0x85, 0xff, 0x74, 0x5b, 0x83, 0xbf,
                                                      0x58, 0x05, 0x00, 0x00, 0x00};
inline constexpr unsigned char FocusedContinueBytes[]{0x8b, 0x4c, 0x24, 0x28, 0x5f, 0x32, 0xc0,
                                                      0x64, 0x89, 0x0d, 0x00, 0x00, 0x00, 0x00};

template <class Predicate> inline bool Install(const Patches& patches, Predicate predicate) {
    if (!DefineFunctions(patches)) {
        return false;
    }

    const auto nearbyWorker =
        From<FAF::CCommandTask>(Register::Edi).Member<&FAF::CCommandTask::Unit>().Dereference();
    const auto focusedWorker =
        From<FAF::CCommandTask>(Register::Esi).Member<&FAF::CCommandTask::Unit>().Dereference();

    return patches.Filter(Nearby, AtBytes(NearbyCandidateBytes),
                          CallWith(predicate, nearbyWorker, From<FAF::Unit>(Register::Esi))
                              .OnFalse(ContinueAt(NearbyContinueBytes))) &&
           patches.Filter(Nearby, AtBytes(NearbyResolvedBytes),
                          CallWith(predicate, nearbyWorker, From<FAF::Unit>(Register::Esi))
                              .OnFalse(ContinueAt(NearbyContinueBytes))) &&
           patches.Filter(Focused, AtBytes(FocusedHostBytes),
                          CallWith(predicate, focusedWorker, From<FAF::Unit>(Register::Ecx))
                              .OnFalse(ContinueAt(FocusedContinueBytes))) &&
           patches.Filter(Focused, AtBytes(FocusedResolvedBytes),
                          CallWith(predicate, focusedWorker, From<FAF::Unit>(Register::Edi))
                              .OnFalse(ContinueAt(FocusedContinueBytes)));
}
} // namespace RepairStationControl::AssistanceHooks
