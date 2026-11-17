local root = '/mods/ModularShields/lua/ModularShields/'
local R = import(root .. 'Runtime.lua').Export
local Assist = import(root .. 'Adapters/Assistance.lua').Export
local Jobs = import(root .. 'Services/InstallJobs.lua').Export
local Shield = import(root .. 'Adapters/Shield.lua').Export
local HexDome = import(root .. 'Adapters/HexDome.lua').Export
local Adjacency = import(root .. 'Adapters/Adjacency.lua').Export
local AdjacencyEffects = import(root .. 'Adapters/AdjacencyEffects.lua').Export
local Repair = import(root .. 'Behaviors/Repair.lua').Export
local Combat = import(root .. 'Services/Combat.lua').Export
local Transfer = import(root .. 'Services/Transfer.lua').Export
local Ground = import(root .. 'Behaviors/GroundBarrier.lua').Export
local Telemetry = import(root .. 'Services/Telemetry.lua').Export
local function MakeGenerator(Base)
    return ClassUnit(Base) {
        CreateShield=function(self,spec)
            Base.CreateShield(self,spec)
            HexDome.Attach(self)
            -- Leave the chassis repairable, but never expose the dome as native
            -- guard/repair work. Its HP is maintained by shield regeneration.
            if not self.ModuleUpgrading then self:ClearFocusEntity() end
        end,
        OnStopBeingBuilt = function(self, builder, layer)
            local inherited=builder and builder.Loadout and builder.ModuleUpgrading and Transfer.Snapshot(builder,true)
            Base.OnStopBeingBuilt(self,builder,layer)
            local bp = self.Blueprint
            self.Loadout = R.Core.New(bp.ModularShield.Chassis, {
                Mass = bp.Economy.BuildCostMass, Energy = bp.Economy.BuildCostEnergy,
                Upkeep = bp.Economy.MaintenanceConsumptionPerSecondEnergy,
                ShieldMaxHP = bp.Defense.Shield.ShieldMaxHealth,
                ShieldSize = bp.Defense.Shield.ShieldSize, ShieldRegen = bp.Defense.Shield.ShieldRegenRate,
            })
            self.Loadout.Rules = R.Core
            self:ReconcileModules()
            if inherited then Transfer.Restore(self,inherited) end
            Combat.Register(self)
            Jobs.Start(self,R)
            self:ForkThread(function()
                while not self.Dead do
                    local before=self.ModuleAssistantCount
                    Assist.Rate(self,R.Config)
                    Shield.TickRegen(self)
                    if math.mod(GetGameTick(),2)==0 then self.Sync.ModularShieldLive=Telemetry.Snapshot(self) end
                    if before~=self.ModuleAssistantCount then self:PublishModules() end
                    WaitTicks(1)
                end
            end)
            self:ForkThread(function()
                WaitTicks(math.mod(self.EntityId, 10) + 1)
                while not self.Dead do
                    self:ReconcileModules()
                    Repair.Tick(self,R)
                    WaitTicks(10)
                end
            end)
        end,
        ReconcileModules = function(self,excludedNeighbor)
            if not self.Loadout then return end
            local facts=Adjacency.Snapshot(self,R.Registry,R.Config,excludedNeighbor)
            AdjacencyEffects.Sync(self,facts)
            self.ModulePowerProviders=0
            self.ModuleNeighbors={Power=0,Production=0,EnergyStorage=0,MassStorage=0}
            for _,fact in ipairs(facts) do
                if fact.SameArmy and fact.Completed and fact.EdgeAdjacent then
                    if fact.Tags.power_generator then
                        self.ModuleNeighbors.Power=self.ModuleNeighbors.Power+1
                        self.ModuleNeighbors.Production=self.ModuleNeighbors.Production+(fact.EnergyProduction or 0)
                        if fact.Tier~='t1' then self.ModulePowerProviders=self.ModulePowerProviders+1 end
                    end
                    if fact.Tags.energy_storage then self.ModuleNeighbors.EnergyStorage=self.ModuleNeighbors.EnergyStorage+1 end
                    if fact.Tags.mass_storage then self.ModuleNeighbors.MassStorage=self.ModuleNeighbors.MassStorage+1 end
                end
            end
            local caps,effects = R.Neighbors.Evaluate(R.Registry,facts,self.Loadout.Installed)
            self.Loadout.Capabilities = caps
            self.ModuleNeighborEffects=effects
            self.ModuleStats = R.Stats.Calculate(self.Loadout,R.Registry,R.Config,effects)
            self.Loadout.BonusSlots=math.max(0,math.floor(self.ModuleStats.ModuleSlots-R.Config.Chassis[self.Loadout.Chassis].Slots))
            Shield.Apply(self,self.ModuleStats)
            Combat.Invalidate()
            self:UpdateBarrierState()
            self:PublishModules()
        end,
        UpdateBarrierState=function(self)
            if not self.Loadout then return end
            local reason
            if not self.ModuleStats.Capabilities.ground_barrier then
                reason=self.ModuleStats.Dormant.impenetrable or 'NotInstalled'
            elseif not Combat.Operational(self) then reason='ShieldDown'
            elseif self:GetAIBrain().EnergyDepleted or self:GetAIBrain():GetEconomyStored('ENERGY')<=0 then reason='NoPower'
            elseif not self.Loadout.Capabilities.legendary_power_support then reason='MissingAdjacentPower' end
            if reason then
                self.BarrierActive=false;self.BarrierReadyTick=nil;self.BarrierRecords=nil;self.BarrierReason=reason
            else
                self.BarrierReadyTick=self.BarrierReadyTick or (GetGameTick()+R.Config.Barrier.WarmupTicks)
                self.BarrierActive=GetGameTick()>=self.BarrierReadyTick
                self.BarrierReason=self.BarrierActive and 'Active' or 'WarmingUp'
            end
        end,
        TickBarrier=function(self)
            local before=self.BarrierReason
            self:UpdateBarrierState()
            Ground.Tick(self,R.Config.Barrier)
            if before~=self.BarrierReason then Combat.Invalidate();self:PublishModules() end
        end,
        PublishModules = function(self)
            if not self.Loadout then return end
            Jobs.UpdateProgress(self)
            local s=self.Loadout
            local rows=self.ModuleRows
            if not rows or self.ModuleRowsRevision~=s.Revision or self.ModuleRowsStats~=self.ModuleStats then
            rows={}
            for _, id in ipairs(R.Registry.Order) do
                local definition=R.Registry.Modules[id]
                local reason = R.Core.Eligible(s,id,R.Registry,R.Config,true)
                local quote = s.Installed[id] and s.Installed[id].Quote or R.Core.Quote(s,id,R.Registry,R.Config)
                local hypothetical={Base=s.Base,Chassis=s.Chassis,Installed={},Capabilities=s.Capabilities,Rules=R.Core}
                for key,value in pairs(s.Installed) do hypothetical.Installed[key]=value end
                local baseline=self.ModuleStats
                if not s.Installed[id] then
                    -- Preview the candidate after its queued prerequisites finish,
                    -- without counting unrelated queued upgrades as its benefit.
                    local function prerequisites(moduleId)
                        for _,required in ipairs((R.Registry.Modules[moduleId].Requires or {}).AllModules or {}) do
                            if not hypothetical.Installed[required] then
                                for _,pending in ipairs(s.Queue) do
                                    if pending.Kind~='Remove' and pending.ModuleId==required then
                                        prerequisites(required)
                                        hypothetical.Installed[required]={Id=required,Quote=pending.Quote}
                                    end
                                end
                            end
                        end
                    end
                    prerequisites(id)
                    baseline=R.Stats.Calculate(hypothetical,R.Registry,R.Config,self.ModuleNeighborEffects)
                    hypothetical.Installed[id]={Id=id,Quote=quote}
                else hypothetical.Installed[id]=nil end
                local preview=R.Stats.Calculate(hypothetical,R.Registry,R.Config,self.ModuleNeighborEffects)
                local deltas={}
                for _,stat in ipairs({'ShieldMaxHP','ShieldSize','ShieldRegen','RepairBudget','Upkeep'}) do
                    deltas[stat]=(preview[stat]-baseline[stat])*(s.Installed[id] and -1 or 1)
                end
                rows[table.getn(rows)+1] = { Id = id, Name = R.Registry.Modules[id].UI.Name,
                    Family=definition.Family,Level=definition.Level,Deltas=deltas,Behavior=definition.Behavior or false,Requires=definition.Requires,
                    Installed = s.Installed[id] ~= nil, Reason = reason and reason.Code or false,
                    RemoveReason=s.Installed[id] and R.Core.CanUninstall(s,id,R.Registry) or false,
                    Detail = reason and (reason.Module or reason.Behavior) or false, Quote = quote }
            end
            self.ModuleRows=rows;self.ModuleRowsRevision=s.Revision;self.ModuleRowsStats=self.ModuleStats
            end
            local job = s.Queue[1]
            self.Sync.ModularShield = { Used = R.Core.Used(s,R.Registry), Slots = R.Core.Capacity(s,R.Config),
                BaseSlots=R.Config.Chassis[s.Chassis].Slots,BonusSlots=s.BonusSlots or 0,Neighbors=self.ModuleNeighbors,
                Faction=self.Blueprint.ModularShield.Faction,RemovalSeconds=R.Config.RemovalSeconds,
                Rows = rows, Stats = self.ModuleStats, LastReason = self.ModuleReason or false,
                InstallPaused = self.InstallPaused or false, RepairPaused = self.RepairPaused or false,
                Assistants=self.ModuleAssistantCount or 0, WorkRate=self.ModuleWorkRate or R.Config.InstallRate,
                Upgrading=self.ModuleUpgrading or false, Barrier=self.BarrierReason,
                ActualEnergy=self:GetConsumptionPerSecondEnergy(),
                NativeAdjacency=self.EnergyMaintAdjMod or 1,
                PowerProviders=self.ModulePowerProviders or 0,
                Queue=table.deepcopy(s.Queue), QueueCount=table.getn(s.Queue), RepairMass=self.ModuleRepairMass or 0,
                Job = job and { Id = job.JobId, Module = job.ModuleId, State = job.State,Kind=job.Kind or 'Install',
                    Progress = job.PaidWork / job.Quote.Work, MassSpent = job.MassSpent, EnergySpent = job.EnergySpent } or false }
            self.Sync.ModularShieldLive=Telemetry.Snapshot(self)
        end,
        RequestModuleInstall = function(self,id)
            if not self.Loadout or self.Dead then return end
            if self.ModuleUpgrading then return nil,{Code='ChassisUpgrading'} end
            local job,reason = R.Core.RequestInstall(self.Loadout,id,R.Registry,R.Config)
            self.ModuleReason = reason and (reason.Code..(reason.Module and ': '..reason.Module or ''))
            Jobs.Start(self,R); self:PublishModules()
            return job,reason
        end,
        ModuleAction = function(self,action,value)
            if not self.Loadout or self.Dead then return end
            if action == 'install' and type(value) == 'string' then return self:RequestModuleInstall(value) end
            local reason
            if action == 'remove' and type(value) == 'string' then
                local blocked=self.Loadout.Queue[1] and self.Loadout.Queue[1].State=='WaitingForSlots'
                local job
                job,reason=R.Core.RequestUninstall(self.Loadout,value,R.Registry,R.Config)
                if job and blocked then
                    -- Let a removal free capacity ahead of a suspended install.
                    -- Stop first so the old coroutine cannot commit out of order.
                    Jobs.Stop(self)
                    table.remove(self.Loadout.Queue,table.getn(self.Loadout.Queue))
                    table.insert(self.Loadout.Queue,1,job)
                end
            elseif action == 'cancel' and type(value) == 'number' then
                Jobs.Stop(self); reason = R.Core.RequestCancel(self.Loadout,value,R.Registry)
            elseif action == 'pause' then
                self.InstallPaused = not self.InstallPaused
                if self.InstallPaused then Jobs.Stop(self) end
                if self.Loadout.Queue[1] then self.Loadout.Queue[1].State = self.InstallPaused and 'Paused' or 'Queued' end
            elseif action == 'repair' then
                self.RepairPaused = not self.RepairPaused
                if self.RepairPaused then self.ModuleRepairMass=0;self.Sync.ModularShieldRepairMass=0 end
            end
            self.ModuleReason = reason and (reason.Code..(reason.Module and ': '..reason.Module or ''))
            self:ReconcileModules(); Jobs.Start(self,R)
            return reason
        end,
        OnAdjacentTo = function(self,other,trigger)
            Base.OnAdjacentTo(self,other,trigger); self:ReconcileModules()
        end,
        OnNotAdjacentTo = function(self,other)
            self.BarrierActive=false;self.BarrierRecords=nil;self.BarrierReadyTick=nil
            self.AdjacentUnits=self.AdjacentUnits or {}
            other.AdjacentUnits=other.AdjacentUnits or {}
            Base.OnNotAdjacentTo(self,other); self:ReconcileModules(other)
        end,
        OnShieldDisabled=function(self)
            self.BarrierActive=false;self.BarrierRecords=nil;self.BarrierReadyTick=nil
            Base.OnShieldDisabled(self)
            if self.Loadout then self:UpdateBarrierState();self:PublishModules() end
        end,
        OnShieldEnabled=function(self)
            Base.OnShieldEnabled(self)
            if self.Loadout then self:UpdateBarrierState();self:PublishModules() end
        end,
        OnStartBuild=function(self,built,order)
            if order=='Upgrade' and built.Blueprint.ModularShield then
                Jobs.Stop(self);self.ModuleUpgrading=true;Assist.ReleaseAll(self)
                self.BarrierActive=false;self.BarrierRecords=nil
            end
            local result=Base.OnStartBuild(self,built,order)
            if result==false then self.ModuleUpgrading=false;Jobs.Start(self,R) end
            return result
        end,
        UpgradingState=State(Base.UpgradingState) {
            OnStopBuild=function(self,built,order)
                if built:GetFractionComplete()==1 and built.Loadout then
                    -- Refresh the shield snapshot at completion, not upgrade start.
                    -- Native code may finish the new unit before this callback.
                    Transfer.Restore(built,Transfer.Snapshot(self,true))
                    Jobs.Start(built,R)
                end
                Base.UpgradingState.OnStopBuild(self,built,order)
            end,
            OnFailedToBuild=function(self)
                self.ModuleUpgrading=false
                Base.UpgradingState.OnFailedToBuild(self)
                self:ReconcileModules();Jobs.Start(self,R)
            end,
        },
        OnGiven = function(self,newUnit)
            AdjacencyEffects.Clear(self)
            Jobs.Stop(self);Assist.ReleaseAll(self)
            if newUnit.Loadout then Transfer.Restore(newUnit,self.TransferSnapshot or Transfer.Snapshot(self,false)) end
            Base.OnGiven(self,newUnit)
        end,
        OnDestroy = function(self)
            AdjacencyEffects.Clear(self)
            Jobs.Stop(self);Assist.ReleaseAll(self)
            Combat.Unregister(self)
            self.BarrierActive=false;self.BarrierRecords=nil
            if self.IsBeingTransferred then self.TransferSnapshot=Transfer.Snapshot(self,false) end
            Base.OnDestroy(self)
        end,
        OnKilled = function(self,instigator,damageType,overkillRatio)
            AdjacencyEffects.Clear(self)
            Jobs.Stop(self);Assist.ReleaseAll(self)
            Combat.Unregister(self)
            self.BarrierActive=false;self.BarrierRecords=nil
            Base.OnKilled(self,instigator,damageType,overkillRatio)
        end,
    }
end
Export = { MakeGenerator = MakeGenerator }

return Export
