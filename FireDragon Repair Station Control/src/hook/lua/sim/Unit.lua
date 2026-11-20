local RSCPreviousUnit=Unit
local RSCController=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Controller.lua').Export
Unit=ClassUnit(RSCPreviousUnit) {
    OnCreate=function(self)
        RSCPreviousUnit.OnCreate(self)
        RSCController.Track(self)
    end,
    SetAutoMode=function(self,enabled)
        local policy=import('/mods/FireDragon Repair Station Control/lua/RepairStationControl/Policy.lua').Export
        if policy.Managed(self) then RSCController.SetAuto(self,enabled)
        else RSCPreviousUnit.SetAutoMode(self,enabled) end
    end,
    OnAutoModeOn=function(self)
        RSCPreviousUnit.OnAutoModeOn(self)
        RSCController.AutoEvent(self,true)
    end,
    OnAutoModeOff=function(self)
        RSCPreviousUnit.OnAutoModeOff(self)
        RSCController.AutoEvent(self,false)
    end,
    OnDestroy=function(self)
        RSCController.Remove(self)
        RSCPreviousUnit.OnDestroy(self)
    end,
}
