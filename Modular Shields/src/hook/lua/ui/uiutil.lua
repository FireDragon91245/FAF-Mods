local PreviousUIFile=UIFile
local aliases={mdeb4301='ueb4301',mdeb4401='ueb4301',mdab4301='uab4301',mdab4401='uab4301',
    mdrb4301='urb4207',mdrb4401='urb4207',mdsb4301='xsb4301',mdsb4401='xsb4301'}
function UIFile(path,checkMods)
    local id=string.match(path,'/icons/units/([^/]+)_icon%.dds$')
    if id and aliases[id] then path=string.gsub(path,id..'_icon%.dds$',aliases[id]..'_icon.dds') end
    return PreviousUIFile(path,checkMods)
end
