-- Cosmetic storage links use the same faction-specific nodes/beams as vanilla
-- adjacency. Own the extra effects separately from native buff-generated links.
local function Destroy(link)
    for _,info in ipairs(link.Bag or {}) do info.Trash:Destroy() end
end
local function Clear(host)
    for _,link in pairs(host.ModuleStorageLinks or {}) do Destroy(link) end
    host.ModuleStorageLinks={}
end
local function NativeLink(a,b)
    for _,info in pairs(a.AdjacencyBeamsBag or {}) do
        if info.Unit==b and not info.Trash:Empty() then return true end
    end
    return false
end
local function Sync(host,facts)
    host.ModuleStorageLinks=host.ModuleStorageLinks or {}
    local wanted={}
    for _,fact in ipairs(facts) do
        local unit=fact.Unit
        if unit and fact.Completed and fact.SameArmy and fact.EdgeAdjacent
            and (fact.Tags.mass_storage or fact.Tags.energy_storage) then wanted[fact.Id]=unit end
    end
    for id,link in pairs(host.ModuleStorageLinks) do
        if wanted[id]~=link.Unit or (not link.Bag and not NativeLink(host,link.Unit) and not NativeLink(link.Unit,host)) then
            Destroy(link);host.ModuleStorageLinks[id]=nil
        elseif link.Bag and (NativeLink(host,link.Unit) or NativeLink(link.Unit,host)) then
            Destroy(link);link.Bag=nil
        end
    end
    -- Facts are in entity-ID order; native faction effects may consume sim RNG.
    for _,fact in ipairs(facts) do
        local unit=wanted[fact.Id]
        if unit and not host.ModuleStorageLinks[fact.Id] then
            local link={Unit=unit}
            if not NativeLink(host,unit) and not NativeLink(unit,host) then
                link.Bag={}
                import('/lua/EffectUtilities.lua').CreateAdjacencyBeams(host,unit,link.Bag)
            end
            host.ModuleStorageLinks[fact.Id]=link
        end
    end
end
Export={Sync=Sync,Clear=Clear}
return Export
