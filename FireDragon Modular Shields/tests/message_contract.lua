local Messages=assert(loadfile('src/lua/ModularShields/Messages.lua'))()
assert(Messages.ValidateAction({EntityId=3,Action='install',Value='power_1'}))
assert(Messages.ValidateAction({EntityId='3',Action='install',Value='power_1'}))
assert(Messages.ValidateAction({EntityId='1048579',Action='cancel',Value=1}))
for _,id in ipairs({'0','-3','3.5','3abc','',0,-3,3.5}) do
    assert(not Messages.ValidateAction({EntityId=id,Action='install',Value='power_1'}),'invalid entity ID accepted')
end
assert(not Messages.ValidateAction({EntityId='3',Action='unknown'}))
print('PASS: native numeric and decimal-string entity ID contracts')
