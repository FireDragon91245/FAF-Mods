# FireDragon UI library

Enable **FireDragon Mod Loader** in FAF's normal mod manager. It is a shared simulation-mod dependency as well as the independently installed native loader. Lua UI use does not require the DLL to initialize. The native bootstrap still loads shader/DLL resources separately.

All FireDragon gameplay mods require UID `3f98ee06-c20c-4fd6-a29e-d7e306fd2026`. Keep the folder name `FireDragonModLoader`. Install the loader package before its consumers. Its installer installs both the ordinary mod (including this library) and native bootstrap.

```lua
local UI = import('/mods/FireDragonModLoader/lua/FireDragon/UI.lua').Export
local window = UI.Window(GetFrame(0), {
    title='My tools', x=100, y=120, width=500, height=360,
    minWidth=300, minHeight=200, draggable=true, resizable=true,
})
local tabs = UI.Tabs(window.Client)
UI.Fill(tabs, window.Client)
local page = tabs:Add('stats', 'Statistics')
local scroll = UI.Scroll(page, {contentWidth=450, contentHeight=800})
UI.Fill(scroll, page)
local column = UI.Column(scroll.Content, {cellWidth=420, cellHeight=28, gap=8})
local label = column:Add(UI.Label(column, {text='Waiting for data'}))
UI.Bind(label, function() return MyLatestValue end,
    function(value, control) control:SetText(tostring(value)) end, 0.1)
tabs:Add('settings', 'Settings')
```

## Geometry and hierarchy

Tabs are opt-in. A single-page window should put its content directly in `window.Client`; use `Tabs` only for multiple pages.

Windows, buttons, checkboxes and scrollbars use vanilla skinnable textures. Checkboxes have a separate box and text label. Buttons activate on release inside their clipped hit surface; releasing outside cancels. Hover, pressed and disabled states use the corresponding vanilla graphics.

Components are native Maui groups with `Left`, `Top`, `Width`, `Height`, `Depth`, `Show`, `Hide`, `Destroy` and a `FDParent`/`FDChildren` hierarchy. Create children under their actual owner; destroying it cleans up the entire native tree. Sizes/positions accept numbers or lazy functions. `At(control,parent,x,y,width,height)` sets absolute offsets; `Fill` follows the parent with an optional inset.

`Row`, `Column`, `Grid` expose `Add(child)`. Construct children under that layout. Options include `columns`, `cellWidth`, `cellHeight`, `gap`, `padding`. Cells retain their sizes when the viewport becomes smaller. A row or column should specify a common cell size. `clip=true` creates a clipping boundary; windows, tab bodies and scroll viewports do this automatically.

Clipping changes rendered primitive bounds and bitmap UVs, preserving the logical component dimensions. Interactive hit regions are clipped too. Maui cannot crop glyphs vertically: partially visible text lines are omitted; horizontal text is cropped to whole glyphs. This avoids drawing outside a viewport without shrinking text or content.

## Components

- `Panel`: hierarchy/group, optional `color` and `clip`.
- `Label`: `text`, `size`, `font`, ARGB `color`; `SetText` / `SetColor`.
- `Icon` / `Rect`: `texture` or solid ARGB `color`; `SetTexture` / `SetSolidColor`.
- `Button`: `text`, `onClick(self,event)`, `SetSelected(bool)`. Selection uses the
  native down texture and is preserved across hover/press transitions.
- `Checkbox`: `text`, `checked`, `onCheck(self,checked)`; `SetCheck(value,silent)`.
- `TextInput`: native Maui keyboard entry; `text`, `maxChars`, `onCommit(self,text)`;
  `GetText`, `SetText`, `Commit`, `SetEnabled`. Enter commits, Escape restores the
  last committed text. Returning false from onCommit rejects the edit. A partially
  clipped field is hidden so native text and input cannot escape its viewport.
- `Slider`: `min`, `max`, `step`, `value`, `onChange(self,value)`, `onPreview(self,value)`;
  `SetValue(value,silent)`, `SetEnabled`. Dragging snaps to steps; programmatic
  values are clamped without snapping. Preview updates are immediate; onChange
  commits on release or after `commitDelay` seconds without motion (default .3).
  Release does not repeat an already committed idle value. Captured drag ends on
  hide or destruction. Thumb/track textures use the native options slider skin.
- `NumberInput`: integer text field plus slider bound to one `Value`; `min`, `max`,
  `step`, `value`, `onChange(self,value)`, `SetValue(value,silent)`, `SetEnabled`.
  Exposes `Input` and `Slider`. Enter applies typed values, rounding/clamping to
  the integer range; invalid text resets. Slider steps do not restrict text entry.
  `commitDelay` is forwarded to its slider. Text entry commits immediately on Enter.
- `Bar`: `value` in [0,1], `track`, `color`; `SetValue(value,max)` follows parent resize.
- `Shape`: rectangle, `kind='border'` (`thickness`), `circle`, `triangle` (`segments`, default 48), or custom alpha `texture`.
- `Dim`: fills its parent; default translucent black, configurable ARGB `color`.
- `Blur`: requires `texture`; nine offset alpha samples with configurable `radius`. This is image-space softening, not a live game-scene/backdrop blur. FAF's exposed Maui API does not provide framebuffer sampling.

All accept `x`, `y`, `width`, `height`, `depth`, `name` where relevant. A primitive's native renderer is `FDVisual`. Decorative controls can `DisableHitTest()`. For custom clickable icons assign `HandleEvent` and call `UI.Interactive(control)` to create a clipped native hit surface. Unhandled events return false and bubble to their parent.

Checkbox onCheck and slider/numeric onChange callbacks may return their existing request
ticket (`Status()` method). While that latest ticket is pending, silent setters
retain the user's displayed value instead of repainting an older confirmed one.
Once it completes, fails or times out, the next silent setter reconciles with
confirmed state. A newer edit replaces the tracked ticket, so older acknowledgements
cannot reset it. This is control behavior; it does not change Exchange's confirmed
Get values or introduce a new UI/config binding system. Numeric text fields use
native skinnable text-entry borders.

## Windows, tabs and scrolling

Windows expose `Client`, `Title`, `TitleBar`, `CloseButton`, `ResizeGrip`, `Focus()`, `SetSize(w,h)`, `SetMinimumSize(w,h)`, `SetDraggable(bool)`, `SetResizable(bool)` and `Close()`. The title bar drags; the lower-right grip resizes. Minimums apply to the outer window. Draggers capture movement until release/cancel and are destroyed with their window. Closing hides by default; `onClose(window)` can change this. `onResize(window)` is optional. Windows focus on clicks on their controls; tooltips should derive depth from their owning window.

Tabs expose `Add(id,title)` returning an owned page, `Select(id)` and `Remove(id)`. Removing a tab destroys its page/button and selects the first remaining page if needed. Hidden pages preserve state. Tabs retain a fixed button width (`tabWidth`, default 136); extra buttons clip if their header is too narrow.

Scroll exposes `Content`, `ScrollTo(x,y)`, `OffsetX`, `OffsetY`, plus Maui's `GetScrollValues`, `IsScrollable`, `ScrollSetTop`, `ScrollLines`, `ScrollPages`. Resize `Content.Width/Height` when content changes; viewport resize and shrinking content clamp offsets. Wheel scrolls vertically, Shift-wheel horizontally. The vertical track and thumb support clicking/dragging and hide automatically when no vertical overflow exists. Content never scales to fit.

`Bind(owner,read,apply,interval)` performs an initial read and polls while its owner is alive, only applying changed values. It returns an unsubscribe function. Bind to a primitive (e.g. a label) or dedicated owner; preserve `OnFrame` if you customize it afterward. Sync-driven menus can call setters directly and avoid polling. Keep simulation requests in the consuming mod; the library does not issue simulation callbacks.

## Validation

From the loader directory, run `lua tests/ui.lua` for shared UI and real debug-panel integration checks, or `test.ps1` for native/installer/UI coverage. Modular Shields' `tests/ui.lua` exercises the migrated window and secured installation/removal callbacks. Actual visual appearance, glyph handling, mouse routing and game-session transitions still require an in-game playtest.

Run `python -B tests/ui_game_smoke.py` for a disposable check in the actual FAF UI runtime (native hit testing, clipping, lazy-variable scrolling, lifecycle and vanilla asset resolution). It launches its own game process and closes it afterward; close any existing game first.

Window geometry can be persisted with `prefKey='my_mod_window'`. Drag/resize release, close, hide and destruction save the geometry through the [shared storage API](STORAGE_API.md) in namespace `FireDragon.UI`; recreation restores it and clamps it into the current screen. Dimensions follow UI scaling. `SaveGeometry()` can save programmatic changes explicitly. Keys are exact strings, including dots. Version 7 is a breaking change: old flat profile preferences are not migrated.

Scroll components now expose `Viewport`, `HorizontalScrollbar` and `HorizontalThumb` alongside the vertical `Scrollbar` and `Thumb`. Each axis appears only when needed; the viewport reserves room for visible tracks so they do not cover content. Both thumbs can be dragged and both tracks accept clicks. Without vertical overflow, the regular wheel also scrolls horizontal content. `Content` is owned by `Viewport`; create children under `Content` as before.
