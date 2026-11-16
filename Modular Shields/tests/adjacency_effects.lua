table.getn=table.getn or function(t) return #t end
local created,destroyed=0,0
local function trash()
    return {Empty=function(self) return self.Destroyed or false end,
        Destroy=function(self) if not self.Destroyed then destroyed=destroyed+1;self.Destroyed=true end end}
end
function import(path)
    assert(path=='/lua/EffectUtilities.lua')
    return {CreateAdjacencyBeams=function(host,unit,bag)
        created=created+1;table.insert(bag,{Unit=unit,Trash=trash()})
    end}
end
local env=setmetatable({}, {__index=_G})
local A=assert(loadfile('ModularShields/lua/ModularShields/Adapters/AdjacencyEffects.lua','t',env))()
local count=0
local function check(v,message) count=count+1;assert(v,message) end
local h={EntityId=1}
local mass,energy,power={EntityId=2},{EntityId=3},{EntityId=4}
local function fact(unit,tag) return {Id=unit.EntityId,Unit=unit,Tags={[tag]=true},Completed=true,SameArmy=true,EdgeAdjacent=true} end
local m,e,p=fact(mass,'mass_storage'),fact(energy,'energy_storage'),fact(power,'power_generator')
A.Sync(h,{m,e,p})
check(created==2 and h.ModuleStorageLinks[2] and h.ModuleStorageLinks[3] and not h.ModuleStorageLinks[4],'Both storage types gain native-style links; existing generator visuals are left alone')
A.Sync(h,{m,e,p})
check(created==2 and destroyed==0,'Repeated reconciliation cannot duplicate storage beams')
A.Sync(h,{e,p})
check(destroyed==1 and not h.ModuleStorageLinks[2] and h.ModuleStorageLinks[3],'Losing one storage removes only its own link')
e.SameArmy=false;A.Sync(h,{e})
check(destroyed==2 and next(h.ModuleStorageLinks)==nil,'Ownership loss removes the previous army link')
e.SameArmy=true;e.Completed=false;A.Sync(h,{e})
check(created==2,'Unfinished storage gets no support link')
e.Completed=true;e.EdgeAdjacent=false;A.Sync(h,{e})
check(created==2,'Corner-only or separated storage gets no support link')
A.Sync(h,{m});local native={Unit=mass,Trash=trash()};h.AdjacencyBeamsBag={native}
A.Sync(h,{m})
check(destroyed==3 and not h.ModuleStorageLinks[2].Bag,'A native link arriving later replaces the duplicate custom link')
A.Clear(h)
check(not native.Trash.Destroyed,'Clearing custom storage visuals never destroys a native-owned link')
A.Sync(h,{m})
check(created==3 and not h.ModuleStorageLinks[2].Bag,'Existing native links are reused')
native.Trash:Destroy();A.Sync(h,{m})
check(created==4 and h.ModuleStorageLinks[2].Bag,'A removed native link is replaced when storage still qualifies')
A.Clear(h);A.Clear(h)
check(destroyed==5 and next(h.ModuleStorageLinks)==nil,'Host cleanup is idempotent and clears all owned effects')
print('PASS: '..count..' storage adjacency visual checks')
