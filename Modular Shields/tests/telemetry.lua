table.getn=table.getn or function(t) return #t end
local tick=100
function GetGameTick() return tick end
function IsDestroyed(s) return s.Destroyed end
local env=setmetatable({}, {__index=_G})
local T=assert(loadfile('src/lua/ModularShields/Services/Telemetry.lua','t',env))()
local count=0
local function check(value,message) count=count+1;assert(value,message) end
local s={HP=800,Max=1000,RegenRate=40,RegenThreadStartTick=105,Up=true}
function s:GetHealth() return self.HP end
function s:GetMaxHealth() return self.Max end
function s:IsUp() return self.Up end
local h={MyShield=s,ModuleStats={ShieldMaxHP=1000},Loadout={}}
T.Damage(h,100);T.Damage(h,50)
local v=T.Snapshot(h)
check(v.HP==800 and v.MaxHP==1000 and v.Damage==30,'Live HP and a five-second damage average use independent readings')
check(v.Regen==0 and v.Status=='Regen delayed','Damage-delay state reports no current regeneration')
tick=106;v=T.Snapshot(h)
check(v.Regen==40 and v.Status=='Regenerating','Actual regeneration resumes after the native damage deadline')
s.HP=1000;v=T.Snapshot(h)
check(v.Regen==0 and v.Status=='Full' and v.Damage==30,'Full shields stop reporting regeneration while recent damage remains visible')
tick=150;v=T.Snapshot(h)
check(v.Damage==0 and next(h.ModuleDamage)==nil,'Old damage expires from the rolling window')
s.Up=false;v=T.Snapshot(h)
check(v.Regen==0 and v.Status=='Offline','Collapsed shields do not report active regen')
-- The native shield hook records actual absorbed HP, including mitigation.
Shield={ApplyDamage=function(self,_,amount) self.HP=self.HP-amount*.5 end}
Class=function(base) return function(def) return setmetatable(def,{__index=base}) end end
function import() return {Export=T} end
assert(loadfile('src/hook/lua/shield.lua'))()
s.HP=800;s.Owner=h;Shield.ApplyDamage(s,nil,100,{},'Normal',true)
check(T.Snapshot(h).Damage==10,'Shield hook records actual health loss after native damage processing')
s.Destroyed=true
Shield.ApplyDamage(s,nil,200,{},'Normal',true)
check(h.ModuleDamage[tick]==800,'Destruction records remaining shield HP without querying a destroyed shield')
print('PASS: '..count..' live shield telemetry checks')
