#include "AssistanceHooks.hpp"
#include "FireDragonLua.hpp"
#include <format>
#include <mutex>
#include <optional>
#include <unordered_map>

using namespace FireDragon;

namespace {
struct Restrictions {
    bool dontHelpTeam = false;
    bool dontHelpNukes = false;

    [[nodiscard]] bool IsActive() const {
        return dontHelpTeam || dontHelpNukes;
    }
};

struct Diagnostics {
    unsigned calls = 0;
    unsigned rejected = 0;
    int32_t lastWorker = 0;
    int32_t lastTarget = 0;

    void RecordCall(int32_t workerId, int32_t targetId) {
        ++calls;
        lastWorker = workerId;
        lastTarget = targetId;
    }

    void RecordResult(bool allowed) {
        if (!allowed) {
            ++rejected;
        }
    }
};

struct FilterState {
    std::unordered_map<int32_t, Restrictions> workers;
    std::optional<FAF::Simulation> activeSimulation;
    Diagnostics diagnostics;

    void SynchronizeSimulation(std::optional<FAF::Simulation> simulation) {
        // Unit IDs can be reused between matches; discard the old match's settings.
        if (activeSimulation && activeSimulation != simulation) {
            workers.clear();
        }

        activeSimulation = simulation;
    }
};

// Every access to state, including engine reads during a check, holds this lock.
std::mutex stateMutex;
FilterState state;

bool IsStrategicMissileSilo(const FAF::Unit& target) {
    return target.IsInCategory("SILO") &&
           (target.IsInCategory("NUKE") || target.IsInCategory("ANTIMISSILE"));
}

bool IsCompletedAndDamaged(const FAF::Unit& target) {
    const auto unitData = target.VarDat();
    return !unitData.IsBeingBuilt() && unitData.Health() < unitData.MaxHealth();
}

bool MeetsRestrictions(const FAF::Unit& worker, const FAF::Unit& target,
                       const Restrictions& restrictions) {
    if (target.IsInCategory("INSIGNIFICANTUNIT")) {
        return false;
    }

    if (restrictions.dontHelpNukes && IsStrategicMissileSilo(target)) {
        return false;
    }

    if (!restrictions.dontHelpTeam) {
        return true;
    }

    if (*worker.ArmyRef() == *target.ArmyRef()) {
        return true;
    }

    // Other armies' completed units may still be repaired.
    return IsCompletedAndDamaged(target);
}

bool IsAssistanceAllowed(const FAF::Unit& worker, const FAF::Unit& target) {
    if (!worker || !target) {
        return true;
    }

    const std::lock_guard lock(stateMutex);
    state.SynchronizeSimulation(worker.SimulationRef().TryGet());

    const auto workerId = worker.Id();
    state.diagnostics.RecordCall(workerId, target.Id());

    const auto settings = state.workers.find(workerId);
    if (settings == state.workers.end()) {
        return true;
    }

    const bool allowed = MeetsRestrictions(worker, target, settings->second);
    state.diagnostics.RecordResult(allowed);
    return allowed;
}

void SetRestrictions(int32_t id, bool dontHelpTeam, bool dontHelpNukes) {
    const Restrictions settings{
        .dontHelpTeam = dontHelpTeam,
        .dontHelpNukes = dontHelpNukes,
    };

    const std::lock_guard lock(stateMutex);
    if (!settings.IsActive()) {
        state.workers.erase(id);
        return;
    }

    state.workers.insert_or_assign(id, settings);
}

void ForgetWorker(int32_t id) {
    const std::lock_guard lock(stateMutex);
    state.workers.erase(id);
}

void Reset() {
    const std::lock_guard lock(stateMutex);
    state = {};
}

Lua::Json Debug() {
    const std::lock_guard lock(stateMutex);
    const auto& diagnostics = state.diagnostics;

    return {
        std::format("{{\"calls\":{},\"rejected\":{},\"worker\":{},\"target\":{},\"workers\":{}}}",
                    diagnostics.calls, diagnostics.rejected, diagnostics.lastWorker,
                    diagnostics.lastTarget, state.workers.size())};
}

bool RegisterLuaBindings(const Lua::Bindings& bindings) {
    return bindings.Bind<SetRestrictions>("SetRestrictions") &&
           bindings.Bind<ForgetWorker>("ForgetWorker") && bindings.Bind<Reset>("Reset") &&
           bindings.Bind<Debug>("Debug");
}
} // namespace

FD_MOD_ENTRY(RepairStationControl, TargetFilter) {
    if (!HasNativeApi(context) || !context->lua || !context->native->engine->profile()) {
        return FD_FAILURE;
    }

    const bool registered =
        RepairStationControl::AssistanceHooks::Install(Patches(context), IsAssistanceAllowed) &&
        RegisterLuaBindings(Lua::Bindings(context));
    return registered ? FD_SUCCESS : FD_FAILURE;
}
