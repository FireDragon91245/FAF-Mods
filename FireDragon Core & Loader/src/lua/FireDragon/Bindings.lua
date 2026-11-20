-- UI intentions are an ordered overlay, never writes to an Exchange mirror.
local B={}
local journals={}
local targetBindings={}
local serial=0
local function copy(v)
    if type(v)~='table' then return v end
    local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local function size(t) local n=0;while t[n+1]~=nil do n=n+1 end;return n end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local function at(v,path)
    for _,k in ipairs(path or {}) do if type(v)~='table' then return nil end;v=v[k] end
    return v
end
local function set(v,path,value)
    if size(path)==0 then return copy(value) end
    local parent=v
    for i=1,size(path)-1 do
        if type(parent[path[i]])~='table' then parent[path[i]]={} end
        parent=parent[path[i]]
    end
    parent[path[size(path)]]=copy(value);return v
end
-- Journals belong to the session/model. Closing a view only detaches observers.
function B.Journal(o)
    local j={Operations={},History={},State={outcomes={},data=copy(o.initialState or {})},Observers={},Drafts={},Version=0}
    local events={}
    local last,projection,dirty,lastIdentity,removed=nil,nil,true,nil,false
    local clock=o.clock or function() if GetGameTimeSeconds then return GetGameTimeSeconds() end;if os then return os.clock() end;return 0 end
    local function event(op,status,reason)
        -- Only plain intent/result metadata crosses the domain hook boundary.
        local value={ID=op.ID,RequestId=op.RequestId,Path=copy(op.Intent.Path),Intent=copy(op.Intent),
            Status=status,Reason=reason,Results=copy(op.Results),Identity=type(lastIdentity)=='table' and tostring(lastIdentity) or lastIdentity}
        table.insert(events,value)
        return value
    end
    local function finish(op,status,reason)
        op.Status=status
        local value=event(op,status,reason)
        table.insert(j.History,copy(value))
        if size(j.History)>32 then table.remove(j.History,1) end
        table.insert(j.State.outcomes,copy(value))
        if size(j.State.outcomes)>32 then table.remove(j.State.outcomes,1) end
    end
    local function metadata(op)
        local value=copy(op.Intent)
        value.ID=op.ID;value.RequestId=op.RequestId;value.Invalidated=op.Invalidated
        return value
    end
    function j:Step()
        if self.Closed then return end
        local state,revision,identity=o.read()
        local replaced=(lastIdentity~=nil and identity~=nil and identity~=lastIdentity) or (removed and state~=nil)
        if replaced or (last~=nil and state==nil) then
            for _,op in ipairs(self.Operations) do finish(op,'invalidated','target_replaced_or_removed') end
            self.Operations={};self.Drafts={};dirty=true
            if replaced then
                self.State={outcomes={},data=copy(o.initialState or {})};events={};removed=false
            else removed=true end
        end
        if identity~=nil then lastIdentity=identity end
        local authoritativeChanged=not equal(last,state)
        local changed=dirty or authoritativeChanged;dirty=false
        local kept={}
        for _,op in ipairs(self.Operations) do
            local ticket=op.Ticket
            if ticket then
                while true do
                    local reply=ticket:Poll();if not reply then break end
                    op.Replies=op.Replies+1;table.insert(op.Results,reply)
                    if not o.settle and reply.error then op.Failure=reply.error
                    elseif not o.settle and type(reply.value)=='table' and reply.value.Accepted==false then
                        op.Failure=reply.value.Reason or 'rejected'
                    else op.Accepted=true;op.Confirmation=reply.confirmation or op.Confirmation end
                end
                local status=ticket:Status()
                local failure=op.Failure
                if clock()>=op.Deadline then failure=failure or 'timeout' end
                if status~='pending' then
                    failure=failure or ticket.Error
                    if status~='complete' then failure=failure or status end
                    if op.Replies==0 then failure=failure or 'no_response' end
                    op.Complete=true
                    if o.settle and not failure then
                        local accepted,reason=o.settle(copy(op.Results),copy(state),metadata(op))
                        if accepted==false then failure=reason or 'rejected' else op.Accepted=accepted==true end
                    end
                end
                if failure then finish(op,(status=='timeout' or failure=='timeout') and 'unknown' or 'rejected',failure);changed=true
                elseif op.Complete and op.Accepted and
                    ((op.Confirmation and revision and revision>=op.Confirmation.revision) or
                     (o.confirm and o.confirm(copy(state),metadata(op)))) then
                    finish(op,'settled');changed=true
                    if o.ordered then
                        for _,earlier in ipairs(self.Operations) do
                            if earlier.ID<op.ID then earlier.Invalidated='incorporated_by_later_operation' end
                        end
                    end
                else table.insert(kept,op) end
            else finish(op,'settled');changed=true end
        end
        self.Operations=kept
        if changed then
            last=copy(state)
            local visible={}
            for _,op in ipairs(kept) do if op.Optimistic and not op.Invalidated then table.insert(visible,metadata(op)) end end
            for _,draft in pairs(self.Drafts) do table.insert(visible,copy(draft)) end
            table.sort(visible,function(a,b) return a.ID<b.ID end)
            projection=copy(state)
            if projection~=nil and o.project then
                local invalid
                projection,invalid=o.project(projection,visible)
                self.Invalid=invalid or {}
                for _,op in ipairs(kept) do
                    if self.Invalid[op.RequestId] and not op.Invalidated then
                        op.Invalidated=self.Invalid[op.RequestId]
                        local value=event(op,'projection_invalidated',op.Invalidated)
                        table.insert(self.State.outcomes,copy(value))
                        if size(self.State.outcomes)>32 then table.remove(self.State.outcomes,1) end
                    end
                end
            end
            if authoritativeChanged then table.insert(events,{Status='rebased'}) end
            for _,value in ipairs(events) do
                if o.reconcile then
                    self.State.data=o.reconcile(copy(self.State.data),copy(value),copy(state),copy(projection))
                    assert(type(self.State.data)=='table','reconcile must return journal data state')
                end
            end
            events={}
            self.Version=self.Version+1
            for _,fn in pairs(self.Observers) do fn(copy(projection),self) end
        end
        return projection
    end
    function j:Get() return copy(self:Step()) end
    function j:Submit(data,options)
        assert(not self.Closed,'Journal closed');assert(size(self.Operations)<128,'Too many pending intentions')
        options=options or {};if options.preview then self.Drafts[options.preview]=nil end;serial=serial+1
        local op=copy(data);op.Intent=copy(data);op.ID=serial;op.Deadline=clock()+(o.settlementTimeout or 30);op.Replies=0;op.Results={};op.Optimistic=options.optimistic~=false
        -- Send once. Rejections/timeouts never cause an automatic retry.
        -- Hook exceptions are programming bugs and must propagate.
        local ticket=o.send(metadata(op))
        op.Ticket=type(ticket)=='table' and ticket or nil
        op.RequestId=op.Ticket and (op.Ticket.Key or tostring(op.Ticket.ID)) or tostring(serial)
        event(op,'submitted');table.insert(self.Operations,op);dirty=true;self:Step();return op
    end
    function j:Status(path)
        self:Step()
        local result={pending=0,outcomes={},state=copy(self.State.data),version=self.Version,invalid=copy(self.Invalid)}
        local function related(other)
            if not path or not other then return true end
            for i=1,math.min(size(path),size(other)) do if path[i]~=other[i] then return false end end
            return true
        end
        for _,op in ipairs(self.Operations) do if related(op.Intent.Path) then result.pending=result.pending+1 end end
        for _,value in ipairs(self.State.outcomes) do if related(value.Path) then table.insert(result.outcomes,copy(value)) end end
        return result
    end
    function j:Dismiss(id)
        local kept={}
        for _,value in ipairs(self.State.outcomes) do
            if id==nil or value.ID==id then
                local dismissed=copy(value);dismissed.Status='dismissed';table.insert(events,dismissed)
            else table.insert(kept,value) end
        end
        self.State.outcomes=kept;dirty=true;self:Step()
    end
    function j:Preview(token,data)
        serial=serial+1;local draft=copy(data);draft.ID=serial;draft.RequestId='preview:'..tostring(serial)
        self.Drafts[token]=draft;dirty=true;self:Step()
    end
    function j:ClearPreview(token)
        if self.Drafts[token] then self.Drafts[token]=nil;dirty=true;self:Step() end
    end
    function j:Observe(fn)
        self:Step();local token={};self.Observers[token]=fn;fn(copy(projection),self)
        return function() self.Observers[token]=nil end
    end
    function j:Close()
        self.Closed=true;self.Observers={};self.Operations={};self.Drafts={}
        if o.onClose then o.onClose(self) end
        -- Do not cancel submitted commands: disposal is not a gameplay action.
    end
    table.insert(journals,j);return j
end
function B.Step()
    for _,update in pairs(targetBindings) do update() end
    local kept={}
    for _,j in ipairs(journals) do
        if not j.Closed then
            j:Step()
            if not next(j.Observers) and size(j.Operations)==0 then
                j.Idle=(j.Idle or 0)+1
            else j.Idle=0 end
            if j.Idle<600 then table.insert(kept,j) else j:Close() end
        end
    end
    journals=kept
end
function B.Config(bus,key)
    bus._BindingConfigs=bus._BindingConfigs or {}
    local j=bus._BindingConfigs[key]
    if j and not j.Closed then return j end
    local cached,cachedRevision,cachedEntry
    j=B.Journal{clock=bus._Clock,ordered=true,
        read=function()
            if not bus.HasConfig(key) then return nil end
            local entry=bus._Entries[key]
            local revision=bus.ConfigRevision and bus.ConfigRevision(key) or entry.version
            if entry~=cachedEntry or revision~=cachedRevision then
                cached=bus.Get(key);cachedEntry=entry;cachedRevision=revision
            end
            return cached,revision,entry
        end,
        send=function(op)
            local result,reason=bus.TrySetPath(key,op.Path,op.Value)
            if not reason then return result end
            local reply={value={Accepted=false,Reason=reason}}
            return {Status=function() return 'complete' end,Poll=function() local value=reply;reply=nil;return value end}
        end,
        onClose=function(closed) if bus._BindingConfigs[key]==closed then bus._BindingConfigs[key]=nil end end,
        project=function(state,ops)
            for _,op in ipairs(ops) do state=set(state,op.Path,op.Value) end;return state
        end,
    }
    bus._BindingConfigs[key]=j;return j
end
function B.Local(value)
    local state=copy(value)
    return B.Journal{read=function() return state end,send=function(op) state=set(copy(state),op.Path or {},op.Value) end}
end
-- A request must declare its authoritative retained-state target. All replies
-- settle together; callers may supply an explicit application confirmation hook.
function B.State(bus,topic,key,definition)
    definition=definition or {}
    assert(definition.replyMode~='All' or definition.settle,'Multiple replies require an explicit settlement policy')
    local cached,cachedRevision,cachedIdentity
    return B.Journal{
        read=function()
            local revision=bus.StateRevision and bus.StateRevision(topic,key)
            local identity=bus.StateIdentity and bus.StateIdentity(topic,key)
            if revision==nil or revision~=cachedRevision or identity~=cachedIdentity then
                cached=bus.GetState(topic,key);cachedRevision=revision;cachedIdentity=identity
            end
            return cached,revision,identity
        end,
        send=function(op)
            return (bus.Sim or bus).Request(definition.topic,definition.payload(op,key),
                {replyMode=definition.replyMode or 'First',confirmation={topic=topic,key=key},timeout=definition.timeout})
        end,
        project=definition.project,confirm=definition.confirm,settle=definition.settle,ordered=definition.ordered,
        reconcile=definition.reconcile,initialState=definition.initialState,onClose=definition.onClose,
        clock=definition.clock or bus._Clock,settlementTimeout=definition.settlementTimeout,
    }
end
-- A definition owns the registry. Views receive handles, never cache journals.
function B.DefineState(bus,definition)
    assert(type(definition)=='table' and type(definition.stateTopic)=='string','Expected state definition')
    assert(type(definition.payload)=='function','Expected action payload hook')
    local source={}
    local entries,handles={},setmetatable({},{__mode='v'})
    function source:_Journal(key)
        assert(type(key)=='string' or type(key)=='number','Expected target key')
        local j=entries[key]
        if not j then
            local settings={};for k,v in pairs(definition) do settings[k]=v end
            settings.onClose=function(closed)
                if entries[key]==closed then entries[key]=nil end
            end
            j=B.State(bus,definition.stateTopic,key,settings);entries[key]=j
        end
        return j
    end
    function source:For(key)
        assert(type(key)=='string' or (type(key)=='number' and key-key==0),'Expected target key')
        if handles[key] then return handles[key] end
        local model={}
        function model:Get() return source:_Journal(key):Get() end
        function model:Status(path) return source:_Journal(key):Status(path) end
        function model:Submit(intent,options)
            local op=source:_Journal(key):Submit(intent,options)
            return {ID=op.ID,RequestId=op.RequestId}
        end
        function model:Dismiss(id) source:_Journal(key):Dismiss(id) end
        function model:Observe(fn)
            return source:_Journal(key):Observe(function(state,j) fn(state,j:Status()) end)
        end
        function model:_Journal() return source:_Journal(key) end
        handles[key]=model;return model
    end
    function source:Bind(owner,key)
        local model=self:For(key);B.Own(owner,model);return model
    end
    return source
end
function B.Status(spec)
    if spec.config then
        local bus=spec.bus or import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
        return B.Config(bus,spec.config):Status(spec.path)
    end
    local target=spec.target
    if type(target)=='function' then target=target() end
    return assert(spec.source,'Expected state source'):For(target):Status(spec.path)
end
function B.Own(owner,model)
    local close=model:Observe(function() end)
    local destroy=owner.OnDestroy
    owner.OnDestroy=function(self) close();if destroy then destroy(self) end end
end
function B.Attach(control,spec)
    if control.Binding then control.Binding:Close() end
    local path=spec.path or {}
    local closed=false
    local journal,close,currentTarget
    local changing,resolved=false,false
    local binding={}
    local function render(state,j)
        if closed then return end
        -- Step has already reconciled before notifying observers.
        control.BindingStatus=j and j:Status(path) or {pending=0,outcomes={},state={}}
        local v=at(state,path)
        control.BindingStatus.available=state~=nil
        if not spec.apply and control.SetEnabled then
            if state==nil and control.FDBindingAvailable~=false then
                control.FDBindingEnabled=control.FDEnabled~=false;control:SetEnabled(false)
            elseif state~=nil and control.FDBindingAvailable==false then
                control:SetEnabled(control.FDBindingEnabled and not spec.readOnly)
            end
            control.FDBindingAvailable=state~=nil
        end
        if spec.apply then spec.apply(control,v,control.BindingStatus)
        elseif v~=nil then
            if control.SetCheck then control:SetCheck(v,true)
            elseif control.SetValue then control:SetValue(v,true)
            elseif control.SetText then control:SetText(tostring(v)) end
        elseif state==nil then
            if control.SetCheck then control:SetCheck(false,true)
            elseif control.Input then control.Input:SetText('')
            elseif control.SetText then control:SetText('') end
        end
        if spec.onStatus then spec.onStatus(control,control.BindingStatus) end
    end
    local function resolve()
        if closed or changing then return end
        local target=spec.target
        if type(target)=='function' then target=target() end
        if resolved and target==currentTarget then return end
        resolved=true
        changing=true
        if close then
            close();close=nil;journal:ClearPreview(binding)
            local slider=control.Slider or control
            if slider.FDSliderDrag then slider.FDSliderDrag:OnCancel() end
        end
        currentTarget=target
        if spec.source then journal=target~=nil and spec.source:_Journal(target) or nil
        elseif spec.config then
            local bus=spec.bus or import('/mods/FireDragon Core & Loader/lua/FireDragon/InformationExchange.lua').Export
            journal=B.Config(bus,spec.config)
        else journal=assert(spec.journal,'Expected config or state source binding') end
        if journal then close=journal:Observe(render) else render(nil,nil) end
        changing=false
    end
    function binding:Submit(value)
        resolve();if closed or spec.readOnly or not journal then return end
        return journal:Submit(spec.intent and spec.intent(value) or {Path=path,Value=value},{optimistic=spec.optimistic,preview=binding})
    end
    function binding:Refresh() resolve();if not closed then render(journal and journal:Get(),journal) end end
    function binding:Preview(value)
        resolve()
        if not closed and journal and not spec.readOnly and spec.optimistic~=false then
            journal:Preview(binding,spec.intent and spec.intent(value) or {Path=path,Value=value})
        end
    end
    function binding:ClearPreview() if journal then journal:ClearPreview(binding) end end
    function binding:Close()
        closed=true;targetBindings[binding]=nil
        if close then close();close=nil;journal:ClearPreview(binding) end
    end
    if not control.FDBindingDestroy then
        control.FDBindingDestroy=true
        local destroy=control.OnDestroy
        control.OnDestroy=function(self)
            if self.Binding then self.Binding:Close();self.Binding=nil end
            if destroy then destroy(self) end
        end
    end
    control.Binding=binding
    if type(spec.target)=='function' then targetBindings[binding]=resolve end
    resolve()
    if spec.readOnly and control.SetEnabled and not spec.apply then control:SetEnabled(false) end
    return binding
end
Export=B
return B
