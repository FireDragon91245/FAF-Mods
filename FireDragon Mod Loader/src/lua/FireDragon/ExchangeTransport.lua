-- Pure transport state machine. Engine adapters live in ExchangeRuntime.lua.
local Transport={}
local function length(t) local n=0;while t[n+1]~=nil do n=n+1 end;return n end
local function integer(v,max) return type(v)=='number' and v>=1 and v<=max and v==math.floor(v) end
local function identifier(v) return type(v)=='string' and string.len(v)>0 and string.len(v)<=160 end
local function stateKey(topic,key) return tostring(string.len(topic))..':'..topic..':'..type(key)..':'..tostring(key) end
local function sorted(map) local keys={};for key in pairs(map) do table.insert(keys,key) end;table.sort(keys);return keys end
-- Enforce wire limits before touching either runtime's application state.
local function wire(value)
    local bytes,nodes=0,0
    local seen={}
    local function visit(v,depth)
        nodes=nodes+1;assert(nodes<=4096 and depth<=16,'Remote data exceeds limits')
        local kind=type(v)
        if kind=='string' then bytes=bytes+string.len(v)
        elseif kind=='number' then assert(v-v==0,'Nonfinite remote number');bytes=bytes+16
        elseif kind=='boolean' or kind=='nil' then bytes=bytes+1
        else
            assert(kind=='table' and not seen[v],'Invalid remote data')
            seen[v]=true
            for key,child in pairs(v) do
                assert(type(key)=='string' or type(key)=='number','Invalid remote key')
                visit(key,depth+1);visit(child,depth+1)
            end
            seen[v]=nil
        end
        assert(bytes<=65536,'Remote data exceeds 64 KiB')
    end
    visit(value,0)
    return value
end

function Transport.Attach(bus,options)
    assert(not bus._transport,'Transport is already attached')
    assert(options.realm=='Sim' or options.realm=='UI','Invalid transport realm')
    local realm,clock,send=options.realm,assert(options.clock),assert(options.send)
    local copy=bus._Copy
    local transport={}
    bus._transport=transport
    local pending,mirrors,lastWrites,active,seen={},{},{},{},{}
    local outbox,dirty,exported,lastIDs,sessions,sessionOwners={},{},{},{},{},{}
    local sequence,revision=0,0
    local retained,stateDirty,stateMirrors,stateIdentities={},{},{},{}
    local stateRevision,batchSerial,lastSerial=0,0,0
    local stateEpoch,deliveredStates=0,{}
    local lastFocus
    local session=options.session or 'test'
    assert(identifier(session),'Invalid UI session')
    local function nextID() sequence=sequence+1;assert(sequence<=16777215,'Transport ID space exhausted');return sequence end
    local function report(err) if options.onError then options.onError(tostring(err)) elseif WARN then WARN(tostring(err)) end end
    local function enqueue(record)
        -- Backpressure: do not remove a reply from its Sim ticket without room.
        if length(outbox)>=512 then return false end
        table.insert(outbox,record);return true
    end
    local function checked(value) return wire(copy(value)) end
    local function operationKey(source,packet)
        return tostring(source.player or source.army)..'/'..packet.session..'/'..tostring(packet.id)
    end
    local function allowed(rule,source,operation,payload)
        if not source.actor then return false end
        if rule=='Army' then return true end
        if rule=='Cheats' then return source.cheats==true end
        if type(rule)=='function' then
            local ok,result=pcall(rule,copy(source),operation,copy(payload))
            if not ok then report('Exchange authorization callback failed: '..tostring(result)) end
            return ok and result==true
        end
        return false -- Remote mutation requires an explicit authorization policy.
    end
    local function response(packet,source,kind,data)
        data=data or {};data.kind=kind;data.session=packet.session;data.id=packet.id
        data.player=source.player;data.army=source.army
        return enqueue(data)
    end
    local function newTicket(op,name,value,opts)
        opts=opts or {}
        local timeout=opts.timeout or 5
        assert(type(timeout)=='number' and timeout-timeout==0 and timeout>0,'Invalid remote timeout')
        local capacity=opts.responseCapacity or 256
        assert(integer(capacity,1024),'Response capacity must be 1..1024')
        assert(length(sorted(pending))<256,'Too many pending remote operations')
        local packet={protocol=1,session=session,id=nextID(),op=op,name=name,value=value,timeout=timeout,
            replyMode=opts.replyMode or 'All',confirmation=opts.confirmation}
        checked(packet)
        local state={id=packet.id,status='pending',responses={},deadline=clock()+timeout,capacity=capacity}
        local ticket={ID=packet.id,Key=session..'/'..tostring(packet.id)}
        local function refresh()
            if state.status=='pending' and clock()>=state.deadline then
                state.status='timeout';pending[state.id]=nil
                send({protocol=1,session=session,id=state.id,op='cancel'})
            end
            return state.status
        end
        function ticket:Status() return refresh() end
        function ticket:Pending() if refresh()=='pending' then return state.remaining or 1 end;return 0 end
        function ticket:Poll()
            refresh()
            if length(state.responses)==0 then return nil end
            return table.remove(state.responses,1)
        end
        function ticket:Cancel()
            if refresh()~='pending' then return false end
            state.status='cancelled';pending[state.id]=nil
            send({protocol=1,session=session,id=state.id,op='cancel'});return true
        end
        state.ticket=ticket;pending[state.id]=state
        return ticket,packet,state
    end
    local function submit(op,name,value,opts)
        assert(realm=='UI','UI-to-Sim operations require UI')
        assert(identifier(name),'Invalid remote key/topic')
        value=checked(value)
        if opts and opts.replyMode then assert(opts.replyMode=='All' or opts.replyMode=='First','Invalid replyMode') end
        local ticket,packet,state=newTicket(op,name,value,opts)
        local ok,err=pcall(send,packet)
        if not ok then pending[state.id]=nil;state.status='failed';ticket.Error=tostring(err);table.insert(state.responses,{error=tostring(err)}) end
        return ticket
    end
    if realm=='UI' then
        bus.ConfigRevision=function(key) return mirrors[key] and mirrors[key].revision end
        bus.StateRevision=function(topic,key)
            local entry=stateMirrors[stateKey(topic,key)];return entry and entry.revision
        end
        bus.StateIdentity=function(topic,key)
            local entry=stateMirrors[stateKey(topic,key)]
            return entry and tostring(entry.identity)..':'..tostring(entry.army)
        end
        bus.UI=bus
        bus.Sim={Publish=function(topic,payload,opts) return submit('publish',topic,payload,opts) end,
            Request=function(topic,payload,opts) return submit('request',topic,payload,opts) end}
        bus._remoteWrite=function(key,path,value)
            local ticket=submit('set',key,{path=path,value=value})
            lastWrites[key]=ticket;return ticket
        end
        function bus.ConfigStatus(key)
            local ticket=lastWrites[key]
            if not ticket then return {status='idle'} end
            local state=ticket:Status()
            return {status=state,error=ticket.Error,denied=ticket.Error=='denied'}
        end
        function transport.Receive(packet)
            assert(type(packet)=='table' and packet.protocol==1,'Unsupported exchange sync packet')
            if packet.serial then
                if packet.serial<=lastSerial then return end
                lastSerial=packet.serial
            end
            if packet.stateReset then
                local present={}
                for _,entry in ipairs(packet.states or {}) do present[stateKey(entry.name,entry.key)]=true end
                for tag,entry in pairs(stateMirrors) do
                    if not present[tag] then bus.PublishState(entry.name,entry.key,nil,{realm='Sim'});stateMirrors[tag]=nil end
                end
            end
            for _,entry in ipairs(packet.states or {}) do
                local tag=stateKey(entry.name,entry.key)
                local previous=stateMirrors[tag]
                if packet.stateReset or not previous or entry.revision>previous.revision then
                    bus.PublishState(entry.name,entry.key,entry.value,{realm='Sim',army=entry.army})
                    stateMirrors[tag]=entry
                end
            end
            -- Config updates are received before acknowledgements from the same Sim tick.
            for _,entry in ipairs(packet.configs or {}) do
                local existing=mirrors[entry.key]
                if not existing or entry.revision>existing.revision then
                    if not entry.exists then
                        if existing and existing.owner then existing.owner:Close() end
                        mirrors[entry.key]={revision=entry.revision}
                    else
                        if existing and existing.owner and existing.mode~=entry.mode then existing.owner:Close();existing.owner=nil end
                        if not existing or not existing.owner then
                            assert(not bus.HasConfig(entry.key),'Sim config conflicts with a UI-local key: '..entry.key)
                            existing={owner=bus.PublishConfig(entry.key,entry.value,entry.mode,
                                entry.mode=='ReadWrite' and function() end or nil),mode=entry.mode}
                            bus._Entries[entry.key].remote=true
                        else existing.owner:Set(entry.value) end
                        existing.revision=entry.revision;mirrors[entry.key]=existing
                    end
                end
            end
            for _,record in ipairs(packet.records or {}) do
                if record.kind=='event' then bus.Publish(record.name,record.value,{realm='Sim'})
                elseif record.session==session then
                    local state=pending[record.id]
                    if state and state.ticket:Status()=='pending' then
                        if record.kind=='reply' or record.kind=='ack' then
                            if length(state.responses)>=state.capacity then
                                state.ticket:Cancel();state.status='failed';state.ticket.Error='response_overflow'
                            else table.insert(state.responses,copy(record.response)) end
                        elseif record.kind=='done' then
                            state.status=record.status;state.ticket.Error=record.error;pending[record.id]=nil
                        elseif record.kind=='progress' then state.remaining=record.remaining
                        end
                    end
                end
            end
        end
        function transport.Tick()
            for _,id in ipairs(sorted(pending)) do pending[id].ticket:Status() end
        end
        function transport.Hello() send({protocol=1,session=session,id=nextID(),op='hello'}) end
        return transport
    end

    bus.Sim=bus
    bus.UI={Publish=function(topic,payload)
        assert(identifier(topic),'Invalid UI topic')
        assert(enqueue(checked({kind='event',name=topic,value=payload})),'UI notification outbox is full')
    end}
    function bus.UI.PublishState(topic,key,value,settings)
        assert(identifier(topic),'Invalid state topic')
        assert(type(key)=='string' or (type(key)=='number' and key-key==0),'Invalid state key')
        settings=settings or {}
        if settings.army~=nil then
            assert(type(settings.army)=='number' and settings.army-settings.army==0 and settings.army>=0
                and settings.army==math.floor(settings.army),'Invalid retained-state army')
        end
        if stateRevision>=1000000 then stateEpoch=stateEpoch+1;stateRevision=0 end
        stateRevision=stateRevision+1
        local version=string.format('%08d:%08d',stateEpoch,stateRevision)
        local tag=stateKey(topic,key)
        if not retained[tag] then stateIdentities[tag]=version end
        local record=checked({name=topic,key=key,value=value,army=settings.army,revision=version,identity=stateIdentities[tag]})
        local tag=stateKey(topic,key)
        retained[tag]=value~=nil and record or nil;stateDirty[tag]=record
        if value==nil then stateIdentities[tag]=nil end
    end
    bus._configChanged=function(key)
        local entry=bus._Entries[key]
        if entry and entry.declaration.scope=='Sim' then exported[key]=true end
        if exported[key] then
            revision=revision+1;dirty[key]=revision
        end
    end
    bus._configValidate=function(value,key,mode)
        assert(identifier(key),'Invalid Sim configuration key')
        checked({key=key,exists=true,revision=0,mode=mode,value=value})
    end
    for key,entry in pairs(bus._Entries) do
        if entry.declaration.scope=='Sim' then bus._configValidate(entry.value,key,entry.mode);bus._configChanged(key) end
    end
    local full=true
    local function fail(packet,source,err)
        response(packet,source,'ack',{response={error=err}})
        response(packet,source,'done',{status='failed',error=err})
    end
    function transport.Receive(packet,source)
        -- Source identity is supplied by the engine adapter, never the UI packet.
        if type(packet)~='table' or packet.protocol~=1 or not identifier(packet.session) or not integer(packet.id,16777215) then return false end
        local client=tostring(source.player or source.army)
        if sessionOwners[packet.session] and sessionOwners[packet.session]~=client then return false end
        if source.actor and not sessionOwners[packet.session] then
            if (sessions[client] or 0)>=64 then return false end
            sessions[client]=(sessions[client] or 0)+1;sessionOwners[packet.session]=client
        end
        if packet.op=='hello' then full=true;return true end
        local key=operationKey(source,packet)
        if packet.op=='cancel' then
            if active[key] then active[key].ticket:Cancel();active[key]=nil end
            return true
        end
        local clientSession=client..'/'..packet.session
        if active[key] or packet.id<=(lastIDs[clientSession] or 0) then return false end
        lastIDs[clientSession]=packet.id
        if not identifier(packet.name) or not source.actor then fail(packet,source,'denied');return false end
        local ok=pcall(checked,packet)
        if not ok then fail(packet,source,'invalid_data');return false end
        -- Bound per-sync-beat traffic and active dialogs independently of inbox limits.
        local usage=seen[client] or 0
        if usage>=64 or length(sorted(active))>=256 or length(outbox)>508 then return false end
        seen[client]=usage+1
        local contract
        if packet.op=='set' then
            local entry=bus._Entries[packet.name]
            if entry and entry.declaration.scope=='Sim' and entry.mode=='ReadWrite' then contract=entry.declaration end
        else
            local exposed=bus._Exposures[packet.name]
            if exposed and ((packet.op=='publish' and exposed.notifications) or (packet.op=='request' and exposed.requests)) then contract=exposed end
        end
        if not contract or not allowed(contract.authorize,source,packet.op,packet.value) then fail(packet,source,'denied');return false end
        local trusted={realm='UI',army=source.army,player=source.player,requestKey=packet.session..'/'..tostring(packet.id)}
        if packet.op=='set' then
            local accepted,err=pcall(function()
                assert(type(packet.value)=='table','Invalid config update')
                bus._SetRemote(packet.name,packet.value.path,packet.value.value,trusted)
            end)
            if not accepted then fail(packet,source,'invalid_value');report(err);return false end
            -- Even a no-op write needs an authoritative revision fence.
            bus._configChanged(packet.name)
            response(packet,source,'ack',{response={value=true,confirmation={config=packet.name,revision=dirty[packet.name]}}})
            response(packet,source,'done',{status='complete'})
        elseif packet.op=='publish' then
            local accepted,delivered,errors=pcall(bus.Publish,packet.name,packet.value,trusted)
            if not accepted then fail(packet,source,'handler_error');report(delivered);return false end
            response(packet,source,'ack',{response={value={delivered=delivered,errors=errors}}})
            response(packet,source,'done',{status='complete'})
        elseif packet.op=='request' then
            local c=packet.confirmation
            if c~=nil and (type(c)~='table' or not identifier(c.topic) or
                not (type(c.key)=='string' or (type(c.key)=='number' and c.key-c.key==0))) then
                fail(packet,source,'invalid_confirmation');return false
            end
            local before=c and (retained[stateKey(c.topic,c.key)] or stateDirty[stateKey(c.topic,c.key)])
            local baseline=before and before.revision
            local accepted,ticket=pcall(bus.Request,packet.name,packet.value,
                {timeout=packet.timeout,replyMode=packet.replyMode,source=trusted})
            if not accepted then fail(packet,source,'invalid_request');report(ticket);return false end
            active[key]={ticket=ticket,packet=copy(packet),source=copy(source),baseline=baseline}
        end
        return true
    end
    local configVersions={}
    function transport.Flush(forceFull)
        bus.Sweep()
        for _,key in ipairs(sorted(active)) do
            local state=active[key]
            while length(outbox)<510 do
                local result=state.ticket:Poll()
                if not result then break end
                local valid,encoded=pcall(checked,result)
                if valid and state.packet.confirmation then
                    local c=state.packet.confirmation
                    local snapshot=retained[stateKey(c.topic,c.key)] or stateDirty[stateKey(c.topic,c.key)]
                    if snapshot and (not state.baseline or snapshot.revision>state.baseline) then encoded.confirmation={topic=c.topic,key=c.key,revision=snapshot.revision} end
                end
                response(state.packet,state.source,'reply',{response=valid and encoded or {error='invalid_remote_response'}})
            end
            if length(outbox)<510 and state.ticket:Status()~='pending' then
                response(state.packet,state.source,'done',{status=state.ticket:Status()});active[key]=nil
            elseif length(outbox)<510 then
                local remaining=state.ticket:Pending()
                if state.remaining~=remaining then
                    response(state.packet,state.source,'progress',{remaining=remaining});state.remaining=remaining
                end
            end
        end
        local updates={}
        if full or forceFull then
            for key in pairs(exported) do
                if not dirty[key] then dirty[key]=configVersions[key] or revision end
            end
        end
        for _,key in ipairs(sorted(dirty)) do
            local entry=bus._Entries[key]
            local record={key=key,exists=entry~=nil and entry.declaration.scope=='Sim',revision=dirty[key]}
            if record.exists then record.mode=entry.mode;record.value=entry.value end
            local valid,encoded=pcall(checked,record)
            if valid then table.insert(updates,encoded);configVersions[key]=record.revision
            else report(encoded) end
        end
        local focus=options.focus and options.focus() or nil
        local reset=full or forceFull or focus~=lastFocus
        local stateUpdates={}
        local candidates=reset and retained or stateDirty
        if reset then deliveredStates={} end
        for _,tag in ipairs(sorted(candidates)) do
            local entry=candidates[tag]
            if focus==nil or focus==-1 or entry.army==nil or entry.army==focus then
                table.insert(stateUpdates,copy(entry));deliveredStates[tag]=entry.value~=nil and entry or nil
            elseif deliveredStates[tag] then
                table.insert(stateUpdates,{name=entry.name,key=entry.key,revision=entry.revision})
                deliveredStates[tag]=nil
            end
        end
        if length(updates)>0 or length(outbox)>0 or length(stateUpdates)>0 or reset then
            batchSerial=batchSerial+1
            send({protocol=1,serial=batchSerial,configs=updates,records=outbox,states=stateUpdates,stateReset=reset})
        end
        stateDirty={};lastFocus=focus
        outbox={};dirty={};full=false;seen={}
    end
    return transport
end
Export=Transport
return Export
