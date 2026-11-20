table.getn=table.getn or function(t) return #t end
local P=assert(loadfile('src/lua/RepairStationControl/Policy.lua'))()
local focus,selection=1,{}
local windows={}
local function control()
    return {Show=function(self) self.Hidden=false end,Hide=function(self) self.Hidden=true end,
        Focus=function() end,Destroy=function(self) self.Destroyed=true end}
end
local UI={Fill=function() end,Label=function() end,Checkbox=function() end}
function UI.Window(_,options)
    local w=control();w.Client={};w.Options=options;windows[#windows+1]=w;return w
end
function UI.Scroll() return {Content={}} end
local env={GetFocusArmy=function() return focus end,GetSelectedUnits=function() return selection end,
    GetFrame=function() return {} end,import=function(path)
        return {Export=path:find('Policy.lua',1,true) and P or UI}
    end}
setmetatable(env,{__index=_G})
assert(loadfile('src/lua/RepairStationControl/Panel.lua','t',env))()
local function unit(id,army,cats)
    return {GetArmy=function() return army end,GetEntityId=function() return id end,
        GetBlueprint=function() return {CategoriesHash=cats} end}
end
local drone=unit(1,1,{POD=true,ENGINEER=true})
local station=unit(2,1,{ENGINEERSTATION=true,TECH3=true})
local other=unit(3,1,{ENGINEER=true})
env.Update();assert(#windows==0)
selection={drone};env.Update();local w=windows[1]
assert(w and not w.Hidden and w.Options.prefKey=='RepairStationControl.Window')
env.Update();assert(#windows==1,'Do not rebuild on every beat')
w:Hide();env.Update();assert(w.Hidden,'Close remains effective for unchanged selection')
selection={station,drone};env.Update();assert(not w.Hidden and #windows==1,'Multiple stations share army controls')
w:Hide();selection={drone,station};env.Update();assert(w.Hidden,'Selection order is irrelevant')
selection={other,drone};env.Update();assert(not w.Hidden,'Mixed selections with a drone open the panel')
selection={other};env.Update();assert(w.Destroyed,'Other units dismiss panel')
for _,cats in ipairs({{ENGINEERSTATION=true,TECH1=true},{ENGINEERSTATION=true,TECH2=true},
    {ENGINEERSTATION=true,TECH3=true},{ENGINEERSTATION=true,EXPERIMENTAL=true}}) do
    selection={unit(10,1,cats)};env.Update();assert(not windows[#windows].Destroyed)
    selection={};env.Update();assert(windows[#windows].Destroyed)
end
local count=#windows
selection={unit(9,2,{ENGINEERSTATION=true})};env.Update();assert(#windows==count,'Do not edit allied armies')
selection={unit(9,1,{POD=true,ENGINEER=true,INSIGNIFICANTUNIT=true})};env.Update()
assert(#windows==count,'Shield helpers cannot open the panel')
selection={drone};env.Update();w=windows[#windows]
focus=2;selection={unit(9,2,{ENGINEERSTATION=true})};env.Update()
assert(w.Destroyed and #windows==count+2,'Focus change recreates bindings for the new army')
focus=-1;env.Update();assert(windows[#windows].Destroyed,'Observers have no army settings')
assert(not env.Toggle,'No keyboard toggle entry point remains')
print('PASS: selection UI, multi-selection, all station levels, close, ownership and focus changes')
