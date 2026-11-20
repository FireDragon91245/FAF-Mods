# FireDragon bindings and managed state sources

Import UI.lua, Bindings.lua and InformationExchange.lua from the shared loader.
Exchange remains the only communication route. Authoritative snapshots are never
mutated to provide optimism.

## Ordinary configuration controls

```lua
UI.Checkbox(page, {text='Ignore resources', binding={
    config='ModularShields.Debug', path={'IgnoreResources'},
}})
UI.NumberInput(page, {min=0, max=1000, step=100, commitDelay=.3,
    binding={config='ModularShields.Debug', path={'AdditionalRegen'}}})
```

The framework resolves and shares the configuration journal. Mods need no cache,
ticket list, stale-value guard, or value refresh assignment. Set `bus=privateBus`
in the binding when using a private Exchange bus; the shared Exchange is default.
Paths are arrays; an empty path represents the whole value. Overlapping parent
and child edits replay in submission order over isolated copies.

`UI.AttachBinding(control,spec)` binds an existing control. `readOnly=true`
disables editable controls. Labels render through SetText; `apply(control,value,
status)` customizes rendering. `onStatus(control,status)` observes structured
operation state. Neither callback should resubmit the same interaction.

Bound Checkbox, Slider and NumberInput own submission. Legacy onCheck/onChange
callbacks run only on unbound controls. Editable bindings are optimistic unless
`optimistic=false` is set. Slider drafts immediately update other observers but
send only on release or commitDelay idle. Release after idle does not resend;
Enter applies valid typed numbers with the same range and step. Retargeting or
destroying a control clears its unsent draft and cancels its drag, not its
submitted gameplay command. An absent target disables normal value controls and
clears the displayed checkbox/text value until state is available again.

## Managed request/state sources

Declare the source once. The framework owns all journals, lookup, caching,
retirement, and recreation for that definition and its Exchange session.

```lua
local Economy = Bindings.DefineState(Exchange, {
    stateTopic=Messages.Economy, topic=Messages.SetResource, ordered=true,
    payload=function(op,army)
        return {Resource=op.Resource, Enabled=op.Value}
    end,
    project=function(state,operations)
        for _,op in ipairs(operations) do state[op.Key]=op.Value end
        return state
    end,
})
UI.Checkbox(page, {text='Infinite energy', binding={
    source=Economy,
    target=function() return tostring(GetFocusArmy()) end,
    path={'Energy'},
    intent=function(value) return {Key='Energy',Resource='ENERGY',Value=value} end,
}})
```

A binding automatically owns its subscription. `target` may be a constant or a
function; the framework switches subscriptions on target changes and preserves
already submitted work in its original journal. No mod rebind loop is needed.

For a custom window, use `local model=Source:Bind(window,entityId)`. This acquires
and owns a target model until the window is destroyed. `Source:For(entityId)`
returns a lightweight target handle, useful outside a view. Handles automatically
reacquire retired journals. They do not expose tickets or require Closed checks.
Multiple views of the same definition and target share pending intentions. A nil
dynamic target means no selection: the framework detaches and clears the display.

Models support Get(), Submit(intent,options), Status(path), Dismiss(operationID),
and Observe(callback). Get returns a copy of the projected state. Submit returns
ID and RequestId metadata. Observe receives projection and structured status,
and returns an unsubscribe function. No lifecycle polling belongs in the mod.

## Domain reconciliation and user-facing failures

Expected denial, validation rejection, timeout, missing targets and transport
failures are operation outcomes, not a journal-wide error string. Status returns:

- pending: pending count, filtered to overlapping paths when a path is supplied.
- outcomes: the last 32 retained outcomes, filtered by path. Each contains ID,
  RequestId, Path, Intent, Status, Reason, Results and target Identity.
- state: mod-defined journal data from the reconcile hook.
- invalid: projection dependency invalidation metadata.
- version: the current projection/outcome version.

Settled outcomes have no failure Reason. Other statuses include rejected,
unknown, invalidated and projection_invalidated. An unrelated new edit never
clears another field's outcome. Dismiss explicitly removes selected outcomes and
notifies the reconciliation hook; no argument dismisses all retained outcomes.
`Bindings.Status{config='ModularShields.Debug',path={'IgnoreResources'}}`
reads configuration outcome state without acquiring a journal in mod code.
The mod decides which outcomes deserve a message, how to format them, and when
to dismiss or replace its messages.

For complex actions, define pure domain handlers with the source:

```lua
local Shields=Bindings.DefineState(Exchange, {
    stateTopic=Messages.Status, topic=Messages.Action, ordered=true,
    payload=function(op,id)
        return {EntityId=id,Action=op.Action,Value=op.Value,
            CancelRequestId=op.CancelRequestId}
    end,
    project=Model.Project,
    initialState={Problems={}},
    reconcile=Model.Reconcile,
})
local model=Shields:Bind(window,entityId)
model:Submit{Action='install',ModuleId='power_1',Value='power_1'}
local displayState=model:Status().state
```

`project(authoritativeCopy,orderedIntentMetadata)` returns projection and an
optional RequestId-to-reason invalidation map. Invalidating a projection does
not cancel its submitted Sim command. Operations receive independent results.

`reconcile(data,event,authoritativeCopy,projectedCopy)` must return the new
mod-defined data table. Events include submitted, settled, rejected, unknown,
projection_invalidated, invalidated, dismissed, and rebased. A rebased event has
no Intent and means authoritative data changed. Handlers receive plain intent
and result metadata, never transport tickets. They must not send messages, create
controls, or mutate shared snapshots. The framework performs mechanical rollback
and ordered replay; the mod controls dependencies and domain reconciliation in
project, and user-facing outcome state in reconcile.

Shields records problems per module/action, checks operation order before
replacing a problem, and renders them through Model.Problem. An older result
cannot clear a newer problem, nor can success on another module. Debug Tools
interprets the structured outcomes per configuration path/resource and supplies
its own messages. Neither mod manages journal storage or transaction lifetimes.

Hook exceptions are programming bugs. They propagate and are not caught or
converted into user rejection messages. Fix the hook or framework bug; there is
no protective fallback rendering. Expected local configuration failures use
Exchange.TrySetPath and explicit reasons such as invalid_value, missing_config
and read_only. A throwing validator is still a programming error.

## Transaction confirmation

Acceptance and authoritative incorporation are separate conditions; either may
arrive first. Config replies carry a revision fence, including no-op writes.
State requests declare a retained topic and target. The responder must publish
the resulting snapshot through Exchange.UI.PublishState before replying,
including successful no-ops. Transport captures the target revision before
dispatch and attaches a later revision to the response. A pre-request snapshot
cannot confirm an accepted operation. Accepted=false is a rejection even when
the transport completed successfully.

`ordered=true` declares synchronous application in transport order. Confirmation
of a later operation suppresses earlier projections while their tickets complete
independently. Asynchronous actions must use an explicit identity/revision
confirmation hook instead of assuming that contract. `confirm(authoritativeCopy,
intentMetadata)` must use domain identity/revision evidence, not value equality
or fixed delays. A notification receipt alone never confirms application success.

State requests default to replyMode='First'. replyMode='All' requires an explicit
settle(replies,authoritativeCopy,intentMetadata) policy returning accepted boolean
and an optional reason. Every collected reply participates. The authoritative
confirmation fence is still required. Programming errors in these hooks propagate.

Rejections remove their projections and rebase remaining intentions over current
authority. No old UI snapshot is restored. Timeout is unknown, never proof that
Sim did not execute the action; nothing retries automatically. Late authority
still applies. Transport timeout defaults to five seconds; settlementTimeout
(default 30 seconds) bounds waiting after acceptance without its snapshot.

## Ownership and bounds

Bindings and Source:Bind own subscriptions through view destruction. Hiding a
window keeps its bindings. Destroying it detaches observers and unsent previews;
pending submitted commands continue in the framework. Reopened views immediately
obtain the shared projection through their source.

The registry strongly retains active journals, then releases unobserved settled
journals after 600 maintenance steps. Target handles are weakly cached and remain
usable after retirement. Config journal entries are also removed on retirement.
Pending operations are limited to 128; outcome and diagnostic history each retain
32 entries. Revision caches avoid full snapshot copies on every maintenance beat.

Removal invalidates old pending projections and reports structured outcomes to
the old target's model. A new target incarnation resets mod-defined outcome data;
old results cannot leak into reused IDs or another army. Publish target removal
on destruction. A new game UI Lua session creates fresh registries and transport
identities. Nothing is persisted to disk.

Bindings.Config, State, Journal, Local and Own remain low-level APIs for private
models and tests. Local({flag=false}) requires no transport; ordinary local
Exchange configuration works through declarative config bindings in either realm.
Exchange broadcast/consume, peek, notifications and single/multiple reply APIs
remain unchanged.
