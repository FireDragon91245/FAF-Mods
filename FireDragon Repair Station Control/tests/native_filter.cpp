// The consumer mock supplies named SDK fields and method dispatch, not engine offsets.
#include "../native/TargetFilter.cpp"
#include <array>
#include <cassert>
#include <cstdio>
#include <cstring>

static_assert(__cplusplus >= 202400L, "Repair predicate tests must run in C++26 mode");

namespace {
struct FakeArmy {
    int index;
};

struct FakeSimulation {
    uint32_t tick;
};

struct FakeBlueprint {
    bool silo = false, nuke = false, antiMissile = false, insignificant = false;
};

struct FakeUnit {
    int32_t id;
    FakeArmy* army;
    FakeSimulation* simulation;
    FakeBlueprint blueprint;
    uint8_t beingBuilt = false;
    float health = 100, maxHealth = 100;
};

struct FakeTask {
    FakeUnit* worker;
};

const char* FD_CALL profile() {
    return "SDK mock";
}

const auto members = [] {
    const char* names[]{"id_",        "ArmyRef",    "SimulationRef", "mVarDat",
                        "mHealth",    "mMaxHealth", "mIsBeingBuilt", "mConstDat",
                        "mArmyIndex", "mCurTick",   "mUnit"};
    std::array<FDFieldInfo, std::size(names)> result{};
    for (size_t i = 0; i < result.size(); ++i)
        result[i].name = names[i];
    return result;
}();

const FDFieldInfo* FD_CALL findField(uint32_t, const char* name, const char*) {
    for (auto& member : members)
        if (!std::strcmp(name, member.name))
            return &member;
    return nullptr;
}

FDObjectRef FD_CALL field(FDObjectRef object, const FDFieldInfo* member) {
    if (!object.address || !member)
        return {};
    const void* address = nullptr;
    auto& unit = *static_cast<const FakeUnit*>(object.address);
    const auto name = member->name;
    if (!std::strcmp(name, "mUnit"))
        address = &static_cast<const FakeTask*>(object.address)->worker;
    else if (!std::strcmp(name, "id_"))
        address = &unit.id;
    else if (!std::strcmp(name, "ArmyRef"))
        address = &unit.army;
    else if (!std::strcmp(name, "SimulationRef"))
        address = &unit.simulation;
    else if (!std::strcmp(name, "mVarDat"))
        address = &unit;
    else if (!std::strcmp(name, "mHealth"))
        address = &unit.health;
    else if (!std::strcmp(name, "mMaxHealth"))
        address = &unit.maxHealth;
    else if (!std::strcmp(name, "mIsBeingBuilt"))
        address = &unit.beingBuilt;
    else if (!std::strcmp(name, "mConstDat"))
        address = object.address;
    else if (!std::strcmp(name, "mArmyIndex"))
        address = &static_cast<const FakeArmy*>(object.address)->index;
    else if (!std::strcmp(name, "mCurTick"))
        address = &static_cast<const FakeSimulation*>(object.address)->tick;
    return {address, 0, 0, 0};
}

FDObjectRef FD_CALL dereference(FDObjectRef object) {
    const void* target = nullptr;
    if (object.address)
        std::memcpy(&target, object.address, sizeof(target));
    return {target, 0, 0, 0};
}

int FD_CALL read(FDObjectRef object, void* result, uint32_t size) {
    if (!object.address || !result)
        return FD_FAILURE;
    std::memcpy(result, object.address, size);
    return FD_SUCCESS;
}

int FD_CALL invoke(const char* symbol, FDObjectRef object, const FDMethodValue* args,
                   uint32_t count, FDMethodValue* result) {
    assert(!std::strcmp(symbol, "Moho::Entity::IsInCategory") && count == 1);
    const auto& bp = static_cast<const FakeUnit*>(object.address)->blueprint;
    auto name = args[0].value.string;
    result->kind = FD_METHOD_BOOLEAN;
    result->value.boolean = (!std::strcmp(name, "SILO") && bp.silo) ||
                            (!std::strcmp(name, "NUKE") && bp.nuke) ||
                            (!std::strcmp(name, "ANTIMISSILE") && bp.antiMissile) ||
                            (!std::strcmp(name, "INSIGNIFICANTUNIT") && bp.insignificant);
    return FD_SUCCESS;
}

FDFieldsApi makeFields() {
    FDFieldsApi result{};
    result.structSize = sizeof(result);
    result.apiVersion = FD_NATIVE_API_VERSION;
    result.findField = findField;
    result.field = field;
    result.dereference = dereference;
    result.read = read;
    return result;
}

const FDFieldsApi fields = makeFields();
const FDEngineApi engine{sizeof(engine), FD_NATIVE_API_VERSION, profile, &fields, invoke, nullptr,
                         nullptr};

FAF::Unit unit(FakeUnit& value) {
    return {&engine, &value};
}
} // namespace

int main() {
    FakeArmy ownArmy{0}, alliedArmy{1};
    FakeSimulation first{1}, second{1};
    FakeUnit worker{10, &ownArmy, &first, {}}, own{20, &ownArmy, &first, {}},
        ally{30, &alliedArmy, &first, {}};
    for (bool team : {false, true})
        for (bool nukes : {false, true}) {
            Reset();
            SetRestrictions(worker.id, team, nukes);
            assert(IsAssistanceAllowed(unit(worker), unit(own)));
            assert(IsAssistanceAllowed(unit(worker), unit(ally)) == !team);
            ally.health = 50;
            assert(IsAssistanceAllowed(unit(worker), unit(ally)));
            ally.beingBuilt = true;
            assert(IsAssistanceAllowed(unit(worker), unit(ally)) == !team);
            ally.beingBuilt = false;
            ally.health = 100;
            own.blueprint = {true, true, false, false};
            assert(IsAssistanceAllowed(unit(worker), unit(own)) == !nukes);
            own.blueprint = {true, false, true, false};
            assert(IsAssistanceAllowed(unit(worker), unit(own)) == !nukes);
            own.blueprint = {false, false, false, true};
            assert(IsAssistanceAllowed(unit(worker), unit(own)) == !(team || nukes));
            own.blueprint = {};
        }
    SetRestrictions(worker.id, false, true);
    own.blueprint = {true, true, false, false};
    assert(!IsAssistanceAllowed(unit(worker), unit(own)));
    worker.simulation = &second;
    assert(IsAssistanceAllowed(unit(worker), unit(own)));
    assert(state.workers.empty());
    SetRestrictions(worker.id, true, true);
    worker.simulation = nullptr;
    assert(IsAssistanceAllowed(unit(worker), unit(own)));
    assert(!state.activeSimulation && state.workers.empty());
    worker.simulation = &second;
    SetRestrictions(worker.id, true, true);
    ForgetWorker(worker.id);
    assert(state.workers.empty());
    assert(unit(worker).ArmyRef().Get().ConstDat().ArmyIndex() == 0 &&
           unit(worker).SimulationRef().Get().CurTick() == 1);
    Reset();
    assert(state.diagnostics.calls == 0);

    // Invalid handles bypass both the policy and diagnostics.
    assert(IsAssistanceAllowed({}, unit(own)));
    assert(IsAssistanceAllowed(unit(worker), {}));
    assert(state.diagnostics.calls == 0);
    assert(!state.activeSimulation);

    // Unmanaged workers bypass restrictions, even for insignificant targets.
    own.blueprint = {false, false, false, true};
    assert(IsAssistanceAllowed(unit(worker), unit(own)));
    assert(state.diagnostics.calls == 1);
    assert(state.diagnostics.rejected == 0);
    assert(state.diagnostics.lastWorker == worker.id);
    assert(state.diagnostics.lastTarget == own.id);

    SetRestrictions(worker.id, true, false);
    assert(!IsAssistanceAllowed(unit(worker), unit(own)));
    assert(state.diagnostics.calls == 2);
    assert(state.diagnostics.rejected == 1);

    // Updating restrictions replaces the previous values; disabling removes them.
    SetRestrictions(worker.id, false, true);
    assert(!state.workers.at(worker.id).dontHelpTeam);
    assert(state.workers.at(worker.id).dontHelpNukes);
    SetRestrictions(worker.id, false, false);
    assert(state.workers.empty());
    assert(IsAssistanceAllowed(unit(worker), unit(own)));
    assert(state.diagnostics.calls == 3);
    assert(state.diagnostics.rejected == 1);

    assert(Debug().text ==
           "{\"calls\":3,\"rejected\":1,\"worker\":10,\"target\":20,\"workers\":0}");
    Reset();
    assert(state.workers.empty());
    assert(!state.activeSimulation);
    assert(state.diagnostics.calls == 0 && state.diagnostics.rejected == 0);
    std::puts("PASS: readable SDK policy, every restriction combination, live categories, "
              "ownership, repairs, construction, sessions and removal");
}
