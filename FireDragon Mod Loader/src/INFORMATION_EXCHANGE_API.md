# FireDragon Information Exchange (v9)

```lua
local Exchange = import('/mods/FireDragonModLoader/lua/FireDragon/InformationExchange.lua').Export
```

All mods importing this exact path share one exchange through FAF's import cache.
No native DLL is required. `Exchange.New({clock = function, onError = function})`
creates an isolated bus for inner-mod use; both options are optional. Bus functions
use dot syntax; returned handles use colon syntax, except message `Reply` and
`IsOpen`, `TryClaim` and `ReleaseClaim`, which are closures using dot syntax.

## Configuration

```lua
-- Publishing mod: keep the owner handle for updates and cleanup.
local settings = Exchange.PublishConfig('MyMod.settings', {
    enabled = true, display = {scale = 1},
}, 'ReadWrite', function(newValue, oldValue, change)
    -- Every committed change, including nested assignments, calls this function.
    ApplySettings(newValue)
    -- change.key, change.path (array), change.version (starts at 1)
end)

-- Any other mod:
local live = Exchange.View('MyMod.settings')
live.display.scale = 1.5
live.enabled = false
Exchange.SetPath('MyMod.settings', {'display', 'scale'}, 2)
local snapshot = Exchange.Get('MyMod.settings')
for k, value in pairs(snapshot.display) do LOG(k, value) end

-- Publishing mod may change even ReadOnly values through its owner handle.
settings:Set({enabled = true, display = {scale = 1}})
settings:SetPath({'display', 'scale'}, 3)
settings:View().display.scale = 4
settings:Close()
```

`PublishConfig(key, value, mode, callback)` rejects duplicate keys. Mode defaults
to `ReadOnly`. `ReadWrite` requires a publisher callback; ReadOnly may also have
one. `HasConfig(key)` distinguishes a missing publication from a published nil.
`Get` returns a detached snapshot. `Set(key, value)` replaces the whole value;
`SetPath(key, path, value)` changes one nested value. An empty path replaces the
root; intermediate tables must already exist. Assigning nil removes a table
field; assigning nil to the root keeps a published nil value. Equal values do
not notify. Set methods return whether a change occurred.

`View` returns an observable table proxy: normal indexed reads and assignments
at every depth work, including replacing/removing tables and editing existing
fields repeatedly. Views follow their original publication and path, so a saved
nested view sees a replacement table at that path. Access fails if the path
stops pointing to a table or the publication closes. Republishing the same key
does not revive old views/owner handles. Use `Get` for scalar roots.

FAF's Lua cannot transparently proxy `pairs`, `ipairs`, `table.getn`, `next`,
`table.insert`, `table.remove`, raw access or table identity. **Use `Get` to
iterate/copy/modify arrays, then `Set` the result**, or use indexed assignments
on the view. Do not use raw/table-library mutations on views or pass a view as
data; publish a snapshot instead. These are cooperative interop rules, not a
security boundary against mods using raw Lua operations.

Input tables are copied; changing an original input or a Get/callback snapshot
does not change the publication. Callback arguments are isolated new/old root
snapshots and change metadata. The write commits before callback invocation.
Errors are reported without rolling back the committed value. Writing or closing
the same publication inside its callback is rejected to prevent feedback loops;
changes to other publications are allowed. Close is idempotent and frees the key.

## Notifications

```lua
local listener = Exchange.Subscribe('MyMod.stockChanged', function(message)
    UpdateDisplay(message.entityID, message.stock)
end)
local inbox = Exchange.Listen('MyMod.stockChanged', 32)
Exchange.Publish('MyMod.stockChanged', {entityID = 123, stock = 7})
local message = inbox:Poll()
if message then UpdateDisplay(message.payload.entityID, message.payload.stock) end
listener:Close()
inbox:Close()
```

Notifications have two topic-wide delivery modes. Configure them **before the
first Subscribe, Listen, Publish or Pump** on that notification topic:

```lua
Exchange.ConfigureTopic('MyMod.news', {delivery = 'Broadcast', capacity = 32})
Exchange.ConfigureTopic('MyMod.work', {delivery = 'Consume', capacity = 32})
```

`Broadcast` is the default: one publish reaches every callback and each polling
inbox independently, so four listeners can all read the same message. There is
no history for later subscribers. `capacity` is the default per-inbox capacity;
an explicit `Listen(topic, capacity)` overrides it.

`Consume` uses one bounded FIFO shared by all listeners on that topic. The first
consumer to take a message removes it for everyone. Unconsumed messages remain
available even if a worker leaves or joins later. Capacity belongs to the topic;
pass no capacity to Listen, or the same value as the topic configuration. Closing
one listener does not clear shared work. Delivery settings cannot change after
the first notification operation, avoiding incompatible queues between mods.

```lua
local worker = Exchange.Listen('MyMod.work')
local candidate = worker:Peek() -- detached snapshot, does not consume
if candidate and stock >= candidate.payload.amount then
    local message = worker:Poll(candidate.messageID)
    if message then
        -- Taking succeeded: this worker exclusively owns this message.
        stock = stock - message.payload.amount
    end
end -- insufficient stock leaves the message available to another worker
```

Every notification envelope includes `messageID`. `Peek()` never consumes and
copies the payload. `Poll()` takes the current head; `Poll(messageID)` takes it
only if that exact message is still at the head, returning nil otherwise. This
prevents an old peek from accidentally taking a newer message. Both modes
support these operations. FIFO ordering means unhandled work at the front stays
at the front until taken or dropped by overflow.

Consume callback subscriptions receive `(payload, context)`. Return true to
consume; false/nil declines and lets the next callback or polling worker try.
For handlers that change state or publish recursively, take **before** doing work:

```lua
Exchange.Subscribe('MyMod.work', function(payload, context)
    if stock < payload.amount then return false end
    if not context.Take() then return false end
    stock = stock - payload.amount
end)
```

`context.Take()` returns true once, only while that message is still available.
A callback error before taking leaves the message for the next handler; an error
after taking does not restore it. Publish runs callbacks in registration order
until one takes the head message, then tries the next queued message. If all
decline, it stops at that head. `Pump(topic)` retries queued Consume messages
without publishing a new one, useful after resources become available. Callback
and polling consumers share the same queue; inline callbacks get their chance
during Publish/Pump before those calls return. Nested dispatch on that topic is
deferred until the outer dispatch resumes.

`Publish(topic, payload)` returns delivery count and callback error count. In
Broadcast the count is recipients invoked/enqueued; in Consume it is callback
takes during that dispatch (possibly including backlog), and may be zero while
the message waits for polling. `Pump` returns the same counts for its dispatch.
Every reader receives its own payload copy. Subscription order determines callback order.
Listeners added during dispatch join the next dispatch; listeners closed before
their turn are skipped. Nested publishing is allowed; avoid feedback cycles.

`Listen(topic, capacity)` defaults to 64 messages unless configured; capacity must be an integer
from 1 to 65536. Its constant-time ring buffer discards the oldest item on
overflow. `Poll()` removes one `{payload = ...}` envelope or returns nil when
empty, so even a nil payload is distinguishable from an empty queue. `Count()`
and cumulative `Dropped()` expose queue state (shared in Consume mode).
`Close()` unsubscribes and clears a Broadcast inbox; a Consume queue remains for
other workers. Callback subscriptions also have `Close()`. Close handles when their
owning mod/entity/display stops using them.

## Requests and replies (nonblocking dialogs)

A request captures the current responders. Each may reply once. It returns a
ticket immediately after dispatching callbacks; it never waits for polling
responders. This preserves state ownership: the receiving building changes its
own stock, then reports what it supplied.

```lua
-- Building 2 registers a polling responder; retain this handle for cleanup.
local assistance = Exchange.ListenRequests('MyMod.needAssistance', 16)

-- Building 1 initiates a dialog and keeps its ticket across update ticks.
local ticket = Exchange.Request('MyMod.needAssistance', {
    requesterID = building1:GetEntityId(), amount = 3,
}, {timeout = 5})

-- Building 2's regular update (no waiting loop):
local message = assistance:Poll()
if message and message.IsOpen() then
    local amount = math.min(stock, message.payload.amount)
    stock = stock - amount
    message.Reply({amount = amount, stock = stock})
end

-- Building 1's regular update:
local response = ticket:Poll()
if response and not response.error then
    received = received + response.value.amount
end
if ticket:Status() ~= 'pending' then
    -- Drain any remaining responses, then release the ticket.
end

-- Alternatively, Building 2 can handle the request immediately:
local responder = Exchange.Respond('MyMod.otherRequest', function(payload, reply, context)
    return {done = true} -- a non-nil return automatically replies
end)
```

Callback responders receive `(payload, reply, context)`. Return a non-nil plain
value for an immediate reply (false is valid), call `reply(value)` explicitly,
or return nil and retain `reply` for a later update. `reply(nil)` is a valid reply.
`context.IsOpen()` checks whether that responder can still reply;
`context.Fail(reason)` sends an error response. `context.requestID` identifies
the dialog. A polling message exposes `payload`, `Reply`, `IsOpen`, `requestID`.
Callbacks execute inline and must return promptly without yielding. A slow
callback still blocks the calling Lua thread; tickets enable delayed work but
do not make callback execution parallel.

Ticket methods:

| Method | Result |
| --- | --- |
| `Status()` | `pending`, `complete`, `timeout`, or `cancelled` |
| `Pending()` | Number of outstanding responders while pending, otherwise zero |
| `Poll()` | Next `{responder = subscriptionID, value = ..., error = ...}` or nil |
| `Cancel()` | Close outstanding replies; returns true only on transition |

Configure each request independently with `Request(topic, payload, options)`:

| `options.replyMode` | Behavior |
| --- | --- |
| `'All'` (default) | Each captured responder may reply once; collect all replies/errors. |
| `'First'` | First successful reply completes the ticket and rejects every later reply. |

Both modes support callback and polling responders. In First mode later inline
callbacks are skipped once a reply completes the ticket. Deferred/polling workers
must reserve the request **before changing state**, so several buildings cannot
all spend resources and then compete to reply:

```lua
local ticket = Exchange.Request('MyMod.needAssistance', {amount = 3}, {
    timeout = 5, replyMode = 'First',
})

-- Each building has its own ListenRequests inbox for this topic.
local candidate = assistance:Peek()
if candidate and stock >= candidate.payload.amount and candidate.TryClaim() then
    local message = assistance:Poll(candidate.messageID)
    stock = stock - message.payload.amount
    message.Reply({amount = message.payload.amount})
end
```

Request inboxes expose `Peek()` and conditional `Poll(messageID)` too. Peeking
does not consume or claim. First mode delivers candidate envelopes to each
responder's inbox, but `TryClaim()` grants exclusive permission to help. Other
responders' `TryClaim`, `IsOpen`, and successful Reply calls return false while
the claim is held. A repeated TryClaim by the owner returns true. It may use
`ReleaseClaim()` to let another candidate try again, or reply to finish. Closing
or failing that responder releases its claim. Cancellation/expiration invalidates
the claim. These methods also exist on callback `context`; use
`context.TryClaim()` before state changes in callbacks which defer their reply.
In All mode TryClaim simply checks whether that responder may still reply.
There is no automatic retry of callback handlers after releasing a claim;
deferred handlers may retry their saved context, or use polling workers.

In First mode false and explicit nil are successful replies, just like any other
value. To decline, call `context.Fail('cannot_help')`, or leave an unclaimed
polling candidate for later. Returning nil from a callback defers. Failures do
not win First mode: it continues until one success or all candidates fail. Only
the winning reply is queued; if every candidate fails, one final error envelope
is queued. All mode retains every candidate's reply/error. Thus First produces
at most one response envelope. No responders completes with no responses.

Route topics or inspect payload entity IDs when only one building is eligible.
A reply returns false if already answered, closed, cancelled, expired, or blocked
by another responder's claim. Check `IsOpen()` and claim before deferred state changes. Cancellation/timeout
does not undo work already performed; protocols requiring reservations or
exactly-once transfers must implement acknowledgement/idempotency themselves.

Replies are available in arrival order, including before Request returns for
immediate handlers. Successful nil replies still have an envelope. In All mode,
completion means every responder answered or failed; in First it means one
success or all failures. Inspect each response's `error`.
Handler exceptions produce `handler_error`, invalid returned data produces
`invalid_response`, closed responders produce `responder_closed`, and dropping
an unanswered queued request produces `queue_overflow`. Unsubscribing fails even
requests already polled by that responder. Reply data validation errors in an
explicit call throw before accepting the reply, allowing retry with valid data.

Timeout defaults to 5 seconds, measured by `GetGameTimeSeconds`, then
`GetSystemTimeSeconds`, then `os.clock` outside the game. Supply a monotonic
`clock` in `New` for other timing requirements. Expiration is lazy: ticket
methods/reply checks enforce it. Call `Exchange.Sweep()` periodically from the
mod's existing update loop to release bus references to abandoned timed-out
tickets; it returns the number expired. Timeout/cancellation preserve replies
already received. Polling queues retain expired envelopes until polled, dropped
or closed, always bounded by capacity.

## Scope and data contract

Keys/topics are nonempty, exact, case-sensitive strings. Prefix them with a
stable mod name/UID. Dots have no special meaning. Configuration, notification
and request channels are separate. Handles have stable numeric `ID`s for
subscriptions/responders and tickets, local to the bus.

Payloads/config/replies accept nil, booleans, strings, finite numbers and plain
tables with string/finite-number keys, up to 24 table levels. Cycles, functions,
userdata, objects and custom metatables are rejected. Use entity IDs and resolve
them in the receiving mod rather than passing live entities. Normal FAF float
number precision applies. Errors in consumer callbacks are isolated and reported
through `WARN` by default or the bus's `onError(message)` function.

The shared exchange lives only in the current Lua runtime. UI and Sim, players,
recreated runtimes and separate private buses do not share messages/state. Nothing
is persisted, synchronized over the network or automatically bridged across
UI/Sim. Keep synchronized gameplay producers/handlers and their registration
order deterministic on every simulation peer. Use existing FAF synchronization
mechanisms when crossing those boundaries. No game scheduler/thread is installed.
