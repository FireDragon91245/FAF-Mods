table.getn = table.getn or function(t) local n = 0; while t[n + 1] ~= nil do n = n + 1 end; return n end
local time, errors = 0, {}
function GetGameTimeSeconds() return time end
local shared = assert(loadfile('src/lua/FireDragon/InformationExchange.lua'))()
local bus = shared.New({clock = function() return time end, onError = function(err) table.insert(errors, err) end})
local rejection = 0
local function rejects(fn)
    rejection = rejection + 1
    assert(not pcall(fn), 'Expected rejection ' .. rejection)
end
local changes = {}
local initial = {nested = {amount = 1}, list = {2, 3}}
local owner = bus.PublishConfig('A.settings', initial, 'ReadWrite', function(new, old, change)
    table.insert(changes, {new = new, old = old, change = change})
    new.nested.amount = -99
end)
initial.nested.amount = 99
assert(bus.Get('A.settings').nested.amount == 1)
local v = bus.View('A.settings')
v.nested.amount = 5
v.nested.amount = 6 -- existing keys must trigger every time
v.list[1] = 8
v.nested.extra = false
v.nested.extra = nil
assert(table.getn(changes) == 5 and changes[1].old.nested.amount == 1)
assert(changes[2].change.path[2] == 'amount' and changes[2].change.version == 2)
assert(bus.Get('A.settings').nested.amount == 6)
assert(not bus.SetPath('A.settings', {'nested', 'amount'}, 6))
local snapshot = bus.Get('A.settings'); snapshot.list[1] = 100
assert(bus.Get('A.settings').list[1] == 8)
local retained = v.nested
owner:Set({nested = {amount = 10}})
retained.amount = 11 -- views track paths, not obsolete table references
assert(bus.Get('A.settings').nested.amount == 11)
local ro = bus.PublishConfig('A.readonly', {child = {flag = true}})
rejects(function() bus.View('A.readonly').child.flag = false end)
rejects(function() bus.Set('A.readonly', {}) end)
ro:View().child.flag = false
assert(not bus.Get('A.readonly').child.flag)
rejects(function() bus.PublishConfig('A.settings', {}) end)
rejects(function() bus.PublishConfig('bad', {}, 'ReadWrite') end)
rejects(function() bus.SetPath('A.settings', {'missing', 'child'}, 1) end)
rejects(function() bus.SetPath('A.settings', {[2] = 'gap'}, 1) end)
local cycle = {}; cycle.self = cycle
rejects(function() owner:Set(cycle) end)
rejects(function() owner:Set({fn = function() end}) end)
rejects(function() owner:Set(1/0) end)
rejects(function() bus.Set('A.settings', v) end)
assert(owner:Close() and not owner:Close())
rejects(function() retained.amount = 12 end)
rejects(function() owner:Set(1) end)
assert(not bus.HasConfig('A.settings'))
bus.PublishConfig('A.settings', 42)
rejects(function() owner:Set(99) end)
bus.PublishConfig('nil', nil)
assert(bus.HasConfig('nil') and bus.Get('nil') == nil)
local recursive
recursive = bus.PublishConfig('recursive', 0, 'ReadWrite', function() recursive:Set(9) end)
assert(bus.Set('recursive', 1) and bus.Get('recursive') == 1 and table.getn(errors) == 1)

local received = {}
local sub = bus.Subscribe('tick', function(data) data.n = 100; table.insert(received, data) end)
local q = bus.Listen('tick', 2)
local broken = bus.Subscribe('tick', function() error('expected failure') end)
local sent = {n = 1}
local delivered, failures = bus.Publish('tick', sent)
assert(delivered == 3 and failures == 1 and sent.n == 1)
assert(q:Poll().payload.n == 1)
bus.Publish('tick', {n = 2}); bus.Publish('tick', {n = 3}); bus.Publish('tick', {n = 4})
assert(q:Count() == 2 and q:Dropped() == 1)
assert(q:Poll().payload.n == 3 and q:Poll().payload.n == 4 and q:Poll() == nil)
broken:Close(); sub:Close(); q:Close()
assert(bus.Publish('tick', {}) == 0)
local order = {}
local later
bus.Subscribe('order', function()
    table.insert(order, 'first'); if later then later:Close() end
    bus.Subscribe('order', function() table.insert(order, 'added') end)
end)
later = bus.Subscribe('order', function() table.insert(order, 'closed') end)
bus.Publish('order', {})
assert(table.getn(order) == 1)
bus.Publish('order', {})
assert(order[2] == 'first' and order[3] == 'added' and table.getn(order) == 3)
local nilQueue = bus.Listen('nil', 1)
bus.Publish('nil', nil); assert(nilQueue:Poll() ~= nil)
rejects(function() bus.Listen('bad', 0) end)
local ring = bus.Listen('ring', 3)
for i = 1, 300 do
    bus.Publish('ring', {i = i})
    if i > 2 then assert(ring:Poll().payload.i == i - 2) end
end
assert(ring:Dropped() == 0 and ring:Count() == 2)
assert(ring:Poll().payload.i == 299 and ring:Poll().payload.i == 300)
ring:Close()

-- Building 2 owns and changes its state when it handles building 1's request.
local stock = 10
local inbox = bus.ListenRequests('building.assist', 2)
local ticket = bus.Request('building.assist', {amount = 3})
assert(stock == 10 and ticket:Status() == 'pending' and ticket:Pending() == 1)
local request = inbox:Poll()
assert(request.IsOpen())
stock = stock - request.payload.amount
assert(request.Reply({amount = 3, stock = stock}))
assert(not request.Reply('twice'))
assert(ticket:Status() == 'complete' and ticket:Pending() == 0)
local response = ticket:Poll()
assert(response.responder == inbox.ID and response.value.stock == 7 and not response.error)
assert(ticket:Poll() == nil)
inbox:Close()
local a = bus.Respond('multi', function(payload) payload.n = 99; return false end)
local savedReply
local b = bus.Respond('multi', function(payload, reply) assert(payload.n == 1); savedReply = reply end)
ticket = bus.Request('multi', {n = 1})
assert(ticket:Pending() == 1 and ticket:Poll().value == false)
assert(savedReply(nil))
response = ticket:Poll(); assert(response and response.value == nil and response.error == nil)
assert(ticket:Status() == 'complete')
ticket = bus.Request('multi', {n = 1}); assert(ticket:Cancel() and not savedReply(2))
assert(ticket:Status() == 'cancelled' and ticket:Poll().value == false)
ticket = bus.Request('multi', {n = 1}, {timeout = 2})
time = 2
assert(ticket:Status() == 'timeout' and not savedReply(2))
a:Close(); b:Close()
assert(bus.Request('missing', {}):Status() == 'complete')
rejects(function() bus.Request('missing', {}, {timeout = 0}) end)
local bad = bus.Respond('bad', function() error('bad responder') end)
ticket = bus.Request('bad', {})
assert(ticket:Status() == 'complete' and ticket:Poll().error == 'handler_error')
bad:Close()
bad = bus.Respond('bad', function() return function() end end)
assert(bus.Request('bad', {}):Poll().error == 'invalid_response'); bad:Close()
local overflow = bus.ListenRequests('overflow', 1)
local t1 = bus.Request('overflow', 1)
local t2 = bus.Request('overflow', 2)
assert(t1:Status() == 'complete' and t1:Poll().error == 'queue_overflow')
assert(overflow:Dropped() == 1)
local popped = overflow:Poll()
overflow:Close()
assert(t2:Poll().error == 'responder_closed' and not popped.Reply(1))
local deferred = bus.ListenRequests('expire', 1)
ticket = bus.Request('expire', 1, {timeout = 1})
time = 4
assert(bus.Sweep() == 1 and ticket:Status() == 'timeout')
assert(not deferred:Poll().IsOpen())
deferred:Close()
local private = shared.New()
local validated=private.PublishConfig('validated',1,'ReadWrite',function() end,function(value)
    return type(value)=='number' and value>=1 and value<=10
end)
rejects(function() private.Set('validated',11) end)
assert(private.Get('validated')==1)
rejects(function() private.PublishConfig('invalidInitial',0,'ReadOnly',nil,function() return false end) end)
assert(not private.HasConfig('invalidInitial'))
validated:Set(10);assert(private.Get('validated')==10)
assert(not private.HasConfig('nil') and private.Publish('order', {}) == 0)

-- A single broadcast reaches all four readers; peeking never mutates queued data.
local readers = {}
for i = 1, 4 do readers[i] = bus.Listen('broadcast.four', 2) end
assert(bus.Publish('broadcast.four', {amount = 4}) == 4)
for _, reader in ipairs(readers) do
    local peek = reader:Peek(); peek.payload.amount = -1
    assert(reader:Count() == 1 and reader:Peek().payload.amount == 4)
    assert(reader:Poll(peek.messageID).payload.amount == 4)
    assert(reader:Peek() == nil); reader:Close()
end

-- One shared consumable message; incapable readers leave it for a capable one.
bus.ConfigureTopic('work', {delivery = 'Consume', capacity = 2})
for i = 1, 4 do readers[i] = bus.Listen('work') end
bus.Publish('work', {amount = 4})
local observed = readers[1]:Peek()
assert(observed.payload.amount == 4 and readers[2]:Count() == 1)
local taken = readers[2]:Poll(observed.messageID)
assert(taken.payload.amount == 4)
assert(readers[1]:Poll(observed.messageID) == nil and readers[3]:Poll() == nil and readers[4]:Poll() == nil)
bus.Publish('work', {amount = 5})
assert(readers[1]:Poll(observed.messageID) == nil) -- stale peek cannot take a newer message
assert(readers[1]:Count() == 1)
readers[1]:Close() -- leaving a shared queue must preserve pending work
assert(readers[2]:Poll().payload.amount == 5)
bus.Publish('work', 1); bus.Publish('work', 2); bus.Publish('work', 3)
assert(readers[2]:Dropped() == 1 and readers[3]:Poll().payload == 2 and readers[4]:Poll().payload == 3)
for _, reader in ipairs(readers) do reader:Close() end
bus.Publish('work', 6) -- bounded backlog exists even before a new polling worker joins
local replacement = bus.Listen('work')
assert(replacement:Poll().payload == 6); replacement:Close()
rejects(function() bus.ConfigureTopic('work', {delivery = 'Broadcast'}) end)
rejects(function() bus.ConfigureTopic('invalid', {delivery = 'Invalid'}) end)
rejects(function() bus.ConfigureTopic('invalid', {capacity = 0}) end)
rejects(function() bus.ConfigureTopic('invalid', {unknown = true}) end)
rejects(function() bus.Listen('work', 99) end)

bus.ConfigureTopic('callback.work', {delivery = 'Consume'})
local declines, handled, skipped = 0, 0, 0
bus.Subscribe('callback.work', function() declines = declines + 1; return false end)
bus.Subscribe('callback.work', function(payload, context)
    assert(context.Take()); assert(not context.Take())
    handled = handled + payload
end)
bus.Subscribe('callback.work', function() skipped = skipped + 1; return true end)
assert(bus.Publish('callback.work', 3) == 1)
assert(declines == 1 and handled == 3 and skipped == 0)
bus.ConfigureTopic('callback.return', {delivery = 'Consume'})
bus.Subscribe('callback.return', function() return true end)
bus.Subscribe('callback.return', function() error('must not reach second handler') end)
assert(bus.Publish('callback.return', 1) == 1)
bus.ConfigureTopic('callback.fallback', {delivery = 'Consume'})
bus.Subscribe('callback.fallback', function() error('leave for polling') end)
local fallback = bus.Listen('callback.fallback')
local d, e = bus.Publish('callback.fallback', false)
assert(d == 0 and e == 1 and fallback:Poll().payload == false)
fallback:Close()
-- Reentrant publishing cannot redeliver a message already taken by a handler.
bus.ConfigureTopic('reentrant.work', {delivery = 'Consume'})
local total = 0
bus.Subscribe('reentrant.work', function(payload, context)
    assert(context.Take()); total = total + 1
    if payload == 1 then bus.Publish('reentrant.work', 2) end
end)
assert(bus.Publish('reentrant.work', 1) == 2 and total == 2)
bus.ConfigureTopic('retry.work', {delivery = 'Consume'})
local available, retried = false, 0
bus.Subscribe('retry.work', function(_, context)
    if not available then return false end
    if context.Take() then retried = retried + 1 end
end)
assert(bus.Publish('retry.work', 1) == 0)
available = true
assert(bus.Pump('retry.work') == 1 and retried == 1 and bus.Pump('retry.work') == 0)
rejects(function() bus.Pump('broadcast.four') end)
bus.ConfigureTopic('small.broadcast', {delivery = 'Broadcast', capacity = 1})
local small = bus.Listen('small.broadcast')
bus.Publish('small.broadcast', 1); bus.Publish('small.broadcast', 2)
assert(small:Count() == 1 and small:Dropped() == 1 and small:Poll().payload == 2)
small:Close()

local called = 0
bus.Respond('first.immediate', function() called = called + 1; return false end)
bus.Respond('first.immediate', function() error('first reply must stop later callbacks') end)
ticket = bus.Request('first.immediate', {}, {replyMode = 'First'})
assert(called == 1 and ticket:Status() == 'complete' and ticket:Poll().value == false and ticket:Poll() == nil)
bus.Respond('first.failure', function() error('skip broken candidate') end)
bus.Respond('first.failure', function(_, reply) reply(nil) end)
ticket = bus.Request('first.failure', {}, {replyMode = 'First'})
response = ticket:Poll()
assert(response and not response.error and response.value == nil and ticket:Poll() == nil)
bus.Respond('first.failed', function() error('one') end)
bus.Respond('first.failed', function() error('two') end)
ticket = bus.Request('first.failed', {}, {replyMode = 'First'})
    assert(ticket:Status() == 'complete' and ticket:Poll().error == 'handler_error' and ticket:Poll() == nil)

local workers = {}
for i = 1, 4 do workers[i] = bus.ListenRequests('first.polled', 2) end
ticket = bus.Request('first.polled', {amount = 3}, {replyMode = 'First'})
local peek1 = workers[1]:Peek()
local peek2 = workers[2]:Peek()
peek1.payload.amount = 100
assert(workers[1]:Peek().payload.amount == 3 and workers[1]:Count() == 1)
-- Worker 1 cannot help; it does not claim. Worker 2 reserves the request.
assert(peek2.TryClaim() and peek2.TryClaim())
assert(not peek1.TryClaim() and not peek1.IsOpen() and not peek1.Reply('unclaimed'))
assert(peek2.ReleaseClaim() and not peek2.ReleaseClaim() and peek1.IsOpen())
assert(peek2.TryClaim())
local selected = workers[2]:Poll(peek2.messageID)
assert(selected.Reply({amount = selected.payload.amount}))
assert(ticket:Status() == 'complete' and ticket:Pending() == 0)
assert(ticket:Poll().value.amount == 3 and ticket:Poll() == nil)
assert(not peek1.TryClaim() and not workers[3]:Poll().Reply('late'))
for _, worker in ipairs(workers) do worker:Close() end

local claimA = bus.ListenRequests('first.claim', 2)
local claimB = bus.ListenRequests('first.claim', 2)
ticket = bus.Request('first.claim', 1, {replyMode = 'First', timeout = 1})
local claimMessage = claimA:Poll()
assert(claimMessage.TryClaim())
claimA:Close() -- closing the claim owner releases the surviving candidate
assert(claimB:Peek().TryClaim() and claimB:Poll().Reply('replacement'))
assert(ticket:Poll().value == 'replacement' and ticket:Poll() == nil)
ticket = bus.Request('first.claim', 2, {replyMode = 'First', timeout = 1})
claimMessage = claimB:Poll(); assert(claimMessage.TryClaim())
time = time + 2
assert(not claimMessage.ReleaseClaim() and not claimMessage.Reply('late') and ticket:Status() == 'timeout')
ticket = bus.Request('first.claim', 3, {replyMode = 'First'})
claimMessage = claimB:Poll(); assert(claimMessage.TryClaim())
assert(ticket:Cancel() and not claimMessage.TryClaim())
claimB:Close()
rejects(function() bus.Request('invalid', {}, {replyMode = 'Invalid'}) end)
print('PASS: configuration observation, isolation, notifications, queues and nonblocking request/reply')
