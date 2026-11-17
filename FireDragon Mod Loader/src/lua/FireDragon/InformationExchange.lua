-- Shared within one Lua runtime through FAF's import cache. No background threads.
local Exchange = {}
local plainMetatable = getmetatable({})
local function size(t)
    -- Lua 5.0 table.remove caches a length which raw indexed writes do not update.
    local n = 0
    while t[n + 1] ~= nil do n = n + 1 end
    return n
end
local function remove(t, index)
    local n = size(t)
    local value = t[index]
    for i = index, n - 1 do t[i] = t[i + 1] end
    t[n] = nil
    return value
end
local function name(v) assert(type(v) == 'string' and v ~= '', 'Expected a nonempty key/topic') end
local function key(v)
    assert(type(v) == 'string' or (type(v) == 'number' and v - v == 0), 'Expected a string or finite number key')
end
local function copy(v, seen, depth)
    local kind = type(v)
    if kind == 'nil' or kind == 'string' or kind == 'boolean' then return v end
    if kind == 'number' then assert(v - v == 0, 'Numbers must be finite'); return v end
    assert(kind == 'table' and getmetatable(v) == plainMetatable, 'Expected plain data; use entity IDs instead of objects')
    seen = seen or {}; depth = depth or 0
    assert(not seen[v] and depth < 24, 'Cyclic or excessively deep data')
    seen[v] = true
    local result = {}
    for k, child in pairs(v) do key(k); result[k] = copy(child, seen, depth + 1) end
    seen[v] = nil
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function pathCopy(path)
    assert(type(path) == 'table', 'Expected an array path')
    local result = {}
    for i = 1, size(path) do key(path[i]); result[i] = path[i] end
    for k in pairs(path) do
        assert(type(k) == 'number' and k >= 1 and k <= size(path) and k == math.floor(k), 'Expected a dense array path')
    end
    return result
end
local function at(value, path)
    for i = 1, size(path) do
        assert(type(value) == 'table', 'Configuration path no longer points to a table')
        value = value[path[i]]
    end
    return value
end
local function defaultClock()
    if GetGameTimeSeconds then return GetGameTimeSeconds() end
    if GetSystemTimeSeconds then return GetSystemTimeSeconds() end
    return os.clock()
end

-- New is useful for private, inner-mod buses and deterministic test clocks.
function Exchange.New(options)
    options = options or {}
    local clock = options.clock or defaultClock
    local onError = options.onError or function(message) if WARN then WARN(message) end end
    assert(type(clock) == 'function' and type(onError) == 'function', 'Invalid exchange options')
    local bus = {}
    local configs, topics, requests = {}, {}, {}
    local eventSettings, eventStates = {}, {}
    local nextID = 0
    local function id() nextID = nextID + 1; return nextID end
    local function report(err) pcall(onError, tostring(err)) end
    local function invoke(fn, a, b, c)
        local ok, result = pcall(fn, a, b, c)
        if not ok then report(result) end
        return ok, result
    end
    local function current(k)
        local entry = configs[k]; assert(entry, 'Configuration key is not published: ' .. tostring(k)); return entry
    end
    local function write(entry, path, value, owner)
        assert(configs[entry.key] == entry, 'Publication is closed')
        assert(owner or entry.mode == 'ReadWrite', 'Configuration is ReadOnly')
        assert(not entry.notifying, 'Cannot write the same publication from its change callback')
        value = copy(value)
        local old = entry.value
        local updated = value
        if size(path) > 0 then
            updated = copy(old)
            local parent = updated
            for i = 1, size(path) - 1 do
                assert(type(parent) == 'table', 'Invalid configuration path'); parent = parent[path[i]]
            end
            assert(type(parent) == 'table', 'Invalid configuration path')
            parent[path[size(path)]] = value
            updated = copy(updated) -- validate final depth before committing
        end
        if equal(old, updated) then return false end
        entry.value = updated; entry.version = entry.version + 1
        if entry.callback then
            entry.notifying = true
            invoke(entry.callback, copy(updated), copy(old), {key = entry.key, path = copy(path), version = entry.version})
            entry.notifying = false
        end
        return true
    end
    local function view(entry, path, owner)
        return setmetatable({}, {
            __index = function(_, k)
                key(k); assert(configs[entry.key] == entry, 'Publication is closed')
                local value = at(entry.value, path)
                assert(type(value) == 'table', 'Configuration view no longer points to a table')
                if type(value[k]) ~= 'table' then return value[k] end
                local child = copy(path); child[size(child) + 1] = k
                return view(entry, child, owner)
            end,
            __newindex = function(_, k, value)
                key(k); local child = copy(path); child[size(child) + 1] = k
                write(entry, child, value, owner)
            end,
            __metatable = 'InformationExchange view',
        })
    end
    function bus.PublishConfig(k, value, mode, callback)
        name(k); assert(not configs[k], 'Configuration key already published')
        mode = mode or 'ReadOnly'
        assert(mode == 'ReadOnly' or mode == 'ReadWrite', 'Expected ReadOnly or ReadWrite')
        assert(callback == nil or type(callback) == 'function', 'Invalid configuration callback')
        assert(mode ~= 'ReadWrite' or callback, 'ReadWrite requires a publisher callback')
        local entry = {key = k, value = copy(value), mode = mode, callback = callback, version = 0}
        configs[k] = entry
        local owner = {}
        function owner:Set(value) return write(entry, {}, value, true) end
        function owner:SetPath(path, value) return write(entry, pathCopy(path), value, true) end
        function owner:View() assert(configs[k] == entry, 'Publication is closed'); return view(entry, {}, true) end
        function owner:Close()
            assert(not entry.notifying, 'Cannot close a publication from its change callback')
            if configs[k] ~= entry then return false end
            configs[k] = nil; return true
        end
        return owner
    end
    function bus.HasConfig(k) name(k); return configs[k] ~= nil end
    function bus.Get(k) name(k); return copy(current(k).value) end
    function bus.View(k) name(k); return view(current(k), {}, false) end
    function bus.Set(k, value) name(k); return write(current(k), {}, value, false) end
    function bus.SetPath(k, path, value) name(k); return write(current(k), pathCopy(path), value, false) end

    local function subscribe(topic, kind, callback)
        name(topic)
        local list = topics[topic] or {}; topics[topic] = list
        local entry = {id = id(), kind = kind, callback = callback, active = true}
        list[size(list) + 1] = entry
        local function close()
            if not entry.active then return false end
            entry.active = false
            for i = size(list), 1, -1 do if list[i] == entry then remove(list, i) end end
            if size(list) == 0 then topics[topic] = nil end
            -- Outstanding requests cannot wait forever for a removed responder.
            local pending = {}
            for _, ticket in pairs(requests) do pending[size(pending) + 1] = ticket end
            for _, ticket in ipairs(pending) do ticket._fail(entry.id, 'responder_closed') end
            return true
        end
        return entry, close
    end
    local function listeners(topic, kind)
        name(topic); local result = {}
        for _, entry in ipairs(topics[topic] or {}) do
            if entry.active and entry.kind == kind then result[size(result) + 1] = entry end
        end
        return result
    end
    local function queue(limit)
        assert(type(limit) == 'number' and limit >= 1 and limit <= 65536 and limit == math.floor(limit), 'Queue capacity must be 1..65536')
        local items, dropped, head, count = {}, 0, 1, 0
        local q = {}
        local function pop()
            local item = items[head]; items[head] = nil
            head = head + 1; if head > limit then head = 1 end
            count = count - 1
            return item
        end
        function q.push(value, discard)
            if count == limit then
                local old = pop(); dropped = dropped + 1
                if old.discard then old.discard() end
            end
            local tail = head + count
            if tail > limit then tail = tail - limit end
            items[tail] = {value = value, discard = discard}; count = count + 1
        end
        function q:Poll(expectedID)
            if count == 0 then return nil end
            if expectedID ~= nil and items[head].value.messageID ~= expectedID then return nil end
            return pop().value
        end
        function q:Peek()
            if count == 0 then return nil end
            local result = {}
            for k, value in pairs(items[head].value) do
                if k == 'payload' then result[k] = copy(value) else result[k] = value end
            end
            return result
        end
        function q:Count() return count end
        function q:Dropped() return dropped end
        function q.clear()
            while count > 0 do
                local old = pop()
                if old.discard then old.discard() end
            end
        end
        return q
    end
    -- Configure notification semantics before the first event operation on a topic.
    function bus.ConfigureTopic(topic, settings)
        name(topic); assert(type(settings) == 'table', 'Expected topic settings')
        assert(not eventStates[topic], 'Configure a topic before subscribing or publishing notifications')
        local delivery = settings.delivery or 'Broadcast'
        assert(delivery == 'Broadcast' or delivery == 'Consume', 'Expected Broadcast or Consume delivery')
        local capacity = settings.capacity or 64
        queue(capacity) -- validate without changing topic state
        for k in pairs(settings) do assert(k == 'delivery' or k == 'capacity', 'Unknown topic setting') end
        eventSettings[topic] = {delivery = delivery, capacity = capacity}
    end
    local function eventState(topic)
        name(topic)
        if not eventStates[topic] then
            local settings = eventSettings[topic] or {delivery = 'Broadcast', capacity = 64}
            eventStates[topic] = {delivery = settings.delivery, capacity = settings.capacity, queue = queue(settings.capacity)}
        end
        return eventStates[topic]
    end
    function bus.Subscribe(topic, callback)
        assert(type(callback) == 'function', 'Expected notification callback')
        eventState(topic)
        local entry, close = subscribe(topic, 'event', callback)
        return {Close = function() return close() end, ID = entry.id}
    end
    function bus.Listen(topic, capacity)
        local state = eventState(topic)
        if state.delivery == 'Consume' then
            assert(capacity == nil or capacity == state.capacity, 'Consume capacity is configured on the topic')
            local entry, close = subscribe(topic, 'event', nil)
            local handle = {ID = entry.id}
            function handle:Peek() if entry.active then return state.queue:Peek() end end
            function handle:Poll(expectedID) if entry.active then return state.queue:Poll(expectedID) end end
            function handle:Count() if entry.active then return state.queue:Count() end; return 0 end
            function handle:Dropped() return state.queue:Dropped() end
            function handle:Close() return close() end
            return handle
        end
        local q = queue(capacity or state.capacity)
        local entry, close = subscribe(topic, 'event', function(payload, context)
            q.push({payload = payload, messageID = context.messageID})
        end)
        q.ID = entry.id
        function q:Close() local changed = close(); q.clear(); return changed end
        return q
    end
    local function dispatchConsume(state, entries)
        local delivered, errors = 0, 0
        if state.dispatching then return 0, 0 end
        state.dispatching = true
        while state.queue:Count() > 0 do
            local message = state.queue:Peek()
            for _, entry in ipairs(entries) do
                local head = state.queue:Peek()
                if not head or head.messageID ~= message.messageID then break end
                if entry.active and entry.callback then
                    local taken = false
                    local context = {messageID = message.messageID}
                    function context.Take()
                        if taken then return false end
                        taken = state.queue:Poll(message.messageID) ~= nil
                        if taken then delivered = delivered + 1 end
                        return taken
                    end
                    local ok, accepted = invoke(entry.callback, copy(message.payload), context)
                    if not ok then errors = errors + 1
                    elseif accepted == true then context.Take() end
                end
            end
            local head = state.queue:Peek()
            if head and head.messageID == message.messageID then break end
        end
        state.dispatching = false
        return delivered, errors
    end
    function bus.Pump(topic)
        local state = eventState(topic)
        assert(state.delivery == 'Consume', 'Pump requires a Consume topic')
        return dispatchConsume(state, listeners(topic, 'event'))
    end
    function bus.Publish(topic, payload)
        payload = copy(payload)
        local state = eventState(topic)
        local entries = listeners(topic, 'event')
        if state.delivery == 'Consume' then
            state.queue.push({payload = payload, messageID = id()})
            return dispatchConsume(state, entries)
        end
        local delivered, errors = 0, 0
        local messageID = id()
        for _, entry in ipairs(entries) do
            if entry.active then
                local ok = invoke(entry.callback, copy(payload), {messageID = messageID})
                delivered = delivered + 1; if not ok then errors = errors + 1 end
            end
        end
        return delivered, errors
    end
    function bus.Respond(topic, callback)
        assert(type(callback) == 'function', 'Expected request callback')
        local entry, close = subscribe(topic, 'request', callback)
        return {Close = function() return close() end, ID = entry.id}
    end
    function bus.ListenRequests(topic, capacity)
        local q = queue(capacity or 64)
        local entry, close = subscribe(topic, 'request', function(payload, reply, context)
            q.push({payload = payload, Reply = reply, IsOpen = context.IsOpen,
                TryClaim = context.TryClaim, ReleaseClaim = context.ReleaseClaim,
                requestID = context.requestID, messageID = context.requestID},
                function() context.Fail('queue_overflow') end)
        end)
        q.ID = entry.id
        function q:Close() local changed = close(); q.clear(); return changed end
        return q
    end
    function bus.Request(topic, payload, requestOptions)
        payload = copy(payload); requestOptions = requestOptions or {}
        local replyMode = requestOptions.replyMode or 'All'
        assert(replyMode == 'All' or replyMode == 'First', 'Expected All or First replyMode')
        local timeout = requestOptions.timeout or 5
        assert(type(timeout) == 'number' and timeout - timeout == 0 and timeout > 0, 'Timeout must be positive and finite')
        local entries = listeners(topic, 'request')
        local ticket = {ID = id()}
        local pending, remaining, responses, status = {}, size(entries), {}, 'pending'
        local deadline = clock() + timeout
        local claimedBy
        for _, entry in ipairs(entries) do pending[entry.id] = true end
        local function refresh()
            if status == 'pending' and clock() >= deadline then status = 'timeout'; requests[ticket.ID] = nil end
            return status
        end
        local function finish(responder, value, err)
            if refresh() ~= 'pending' or not pending[responder] then return false end
            if replyMode == 'First' and not err and claimedBy and claimedBy ~= responder then return false end
            value = copy(value)
            pending[responder] = nil; remaining = remaining - 1
            if claimedBy == responder then claimedBy = nil end
            if replyMode == 'All' or not err or remaining == 0 then
                responses[size(responses) + 1] = {responder = responder, value = value, error = err}
            end
            if remaining == 0 or (replyMode == 'First' and not err) then status = 'complete'; requests[ticket.ID] = nil end
            return true
        end
        function ticket._fail(responder, err) return finish(responder, nil, err) end
        function ticket:Status() return refresh() end
        function ticket:Pending() refresh(); if status ~= 'pending' then return 0 end; return remaining end
        function ticket:Poll() refresh(); if size(responses) == 0 then return nil end; return remove(responses, 1) end
        function ticket:Cancel()
            if refresh() ~= 'pending' then return false end
            status = 'cancelled'; requests[ticket.ID] = nil; return true
        end
        if remaining == 0 then status = 'complete' else requests[ticket.ID] = ticket end
        for _, entry in ipairs(entries) do
            if refresh() == 'pending' and pending[entry.id] then
                local responder = entry.id
                if not entry.active then finish(responder, nil, 'responder_closed')
                else
                    local function reply(value) return finish(responder, value, nil) end
                    local context = {
                        requestID = ticket.ID,
                        IsOpen = function()
                            return refresh() == 'pending' and pending[responder] == true
                                and (replyMode == 'All' or not claimedBy or claimedBy == responder)
                        end,
                        TryClaim = function()
                            if refresh() ~= 'pending' or not pending[responder] then return false end
                            if replyMode == 'All' then return true end
                            if claimedBy and claimedBy ~= responder then return false end
                            claimedBy = responder; return true
                        end,
                        ReleaseClaim = function()
                            if refresh() ~= 'pending' or claimedBy ~= responder then return false end
                            claimedBy = nil; return true
                        end,
                        Fail = function(err) return finish(responder, nil, tostring(err)) end,
                    }
                    local ok, value = invoke(entry.callback, copy(payload), reply, context)
                    if not ok then finish(responder, nil, 'handler_error')
                    elseif value ~= nil then
                        local valid, err = pcall(reply, value)
                        if not valid then report(err); finish(responder, nil, 'invalid_response') end
                    end
                end
            end
        end
        return ticket
    end
    -- Call periodically if abandoned tickets should release the bus's references.
    function bus.Sweep()
        local expired = 0
        local tickets = {}
        for _, ticket in pairs(requests) do tickets[size(tickets) + 1] = ticket end
        for _, ticket in ipairs(tickets) do if ticket:Status() == 'timeout' then expired = expired + 1 end end
        return expired
    end
    return bus
end

local shared = Exchange.New()
shared.New = Exchange.New
Export = shared
return shared
