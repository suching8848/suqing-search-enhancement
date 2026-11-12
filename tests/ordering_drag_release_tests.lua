-- Uses the source-verified CleanUI input handlers and the deployed Proximity
-- selection wrapper on a model pane. No game, UI or save is opened.
local M, O = OrderingMock, SuQingSearch.Ordering
assert(CleanUIReleaseFixture, "load the verified CleanUI release fixture first")
local cases, assertions = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case()
    cases = cases + 1
    M.dragReset()
    M.options.sortMatches = true
end
local player = { nullifyAiming = function() end }
function getSpecificPlayer() return player end
function getCore() return { getGameMode = function() return "Sandbox" end, isTutorial = function() return false end } end
function getPlayerInventory() return {} end
function getPlayerLoot() return {} end
function CleanUI_getColumnDividerAtPoint() return nil end
function isShiftKeyDown() return false end

M.cleanVersion = assert(CleanUIReleaseVersion)
local cleanDir = "D:/fixture/CleanUI/" .. assert(CleanUIReleaseBranch)
local bridgeDir = "D:/fixture/SuQingUIInteractionFixes/42"
local inputPaths = {
    [ISInventoryPane.onMouseDown] = cleanDir .. "/media/lua/client/ISUI/ISInventoryPane.lua",
    [ISInventoryPane.onMouseDoubleClick] = cleanDir .. "/media/lua/client/ISUI/ISInventoryPane.lua",
}
function getFilenameOfClosure(callback) return inputPaths[callback] end
local mockModInfo = getModInfoByID
function getModInfoByID(id)
    if id == "SuQingUIInteractionFixes" then
        return { getModVersion = function() return SuQingUIInteractionFixes.proximitySelection.version end,
            getVersionDir = function() return bridgeDir end }
    end
    local info = mockModInfo(id)
    if info and id == "CleanUI" then info.getVersionDir = function() return cleanDir end end
    return info
end
SuQingSearch.Integration = { reviewedNativeSearch = function() return true end }
M.emit("OnGameStart")
assert(SuQingUIInteractionFixes.proximitySelection.installed, "use the deployed Proximity input wrapper")
inputPaths[ISInventoryPane.onMouseDown] = bridgeDir .. "/media/lua/client/SuQing_ProximitySelectionFix.lua"
inputPaths[ISInventoryPane.onMouseDoubleClick] = bridgeDir .. "/media/lua/client/SuQing_ProximitySelectionFix.lua"

local function makePane(prefix, kind)
    prefix = prefix or ""
    local items, rows = {}, {}
    for index, name in ipairs({"A", "B", "C", "D"}) do
        items[index] = M.item(prefix .. name)
        rows[index] = M.group(prefix .. name, {items[index]}, index)
    end
    local pane = M.pane(rows, kind or "backpack")
    pane.parent.onCharacter = kind ~= "proxInv"
    pane.column2, pane.column3, pane.mouseOverOption = 10, 20, 1
    pane.draggedItems = { reset = function() end }
    function pane:isMouseOverScrollBar() return false end
    for _, row in ipairs(rows) do pane.collapsed[row.name] = true end
    M.nativeRender(pane, false)
    pane.renderCalls = 0
    return pane, M.state({items[2], items[4]}), items, rows
end
local function draw(pane, state)
    return O.render(pane, state, false, ISInventoryPane.renderdetails)
end
local function release(pane, row)
    -- Begin from an actual drag. Execute the original CleanUI method, rather
    -- than a mock release that incorrectly normalizes dragStarted to false.
    pane.dragging, pane.dragStarted = 1, true
    ISMouseDrag.dragging, ISMouseDrag.draggingFocus = {row}, pane
    pane:onMouseUp(-1, -1)
    equal(pane.dragging, nil, "real release clears pane drag")
    equal(ISMouseDrag.dragging, nil, "real release clears global drag")
    equal(ISMouseDrag.draggingFocus, nil, "real release clears global drag focus")
    equal(pane.dragStarted, true, "real release retains historical dragStarted")
end

case()
local pane, state, items, rows = makePane()
release(pane, rows[2])
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "first inventory query promotes matches after real drag release")
equal(pane.searchCalls, 1, "released search reaches native finalizer once")
equal(pane.dragStarted, true, "search leaves the native drag history intact")
draw(pane, state)
equal(pane.searchCalls, 1, "unchanged released search uses cached order")

case()
state.query, state.matches, state.revision = "another query", {[items[3]] = true}, state.revision + 1
draw(pane, state)
equal(M.order(pane), "C,A,B,D", "different query works with the same retained drag history")
state.compiled.active, state.revision = false, state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "clear restores native order after released drag")
equal(pane.dragStarted, true, "clearing does not alter native historical drag flag")

case()
pane, state, items, rows = makePane()
release(pane, rows[2])
draw(pane, state)
local other, nextState, nextItems, nextRows = makePane("next")
-- The player-inventory pane persists when another backpack tab is selected.
pane.inventory, pane.canonical, pane.itemslist = other.inventory, other.canonical, other.itemslist
pane.inventory.dirty = true
state.query, state.matches, state.revision = "query in next bag", {[nextItems[3]] = true}, state.revision + 1
draw(pane, state)
equal(M.order(pane), "nextC,nextA,nextB,nextD", "changing backpack reorders new physical container")
equal(pane.inventory, other.inventory, "ordering retains newly selected container")
equal(pane.dragStarted, true, "container switch does not require clearing native drag history")
state.compiled.active, state.revision = false, state.revision + 1
draw(pane, state)
equal(M.order(pane), "nextA,nextB,nextC,nextD", "clear in another backpack restores its native rows")

case()
pane, state, items, rows = makePane()
pane.dragging, pane.dragStarted = 1, true
pane:onMouseDownOutside(-1, -1)
pane:onMouseUpOutside(-1, -1)
equal(pane.dragging, nil, "real outside click clears pane drag")
equal(pane.dragStarted, true, "real outside handlers retain historical dragStarted")
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "search works after clicking outside the item list")

case()
pane, state, items, rows = makePane()
pane.dragging, pane.dragStarted = 1, true
draw(pane, state)
equal(pane.searchCalls, 0, "actual pane drag remains deferred")
equal(M.order(pane), "A,B,C,D", "actual pane drag keeps rows stable")
pane.dragging = nil
ISMouseDrag.dragging = {rows[2]}
draw(pane, state)
equal(pane.searchCalls, 0, "actual global drag remains deferred")
ISMouseDrag.dragging = nil
pane.draggingMarquis = true
draw(pane, state)
equal(pane.searchCalls, 0, "marquee selection remains deferred")
pane.draggingMarquis = false
for button = 0, 2 do
    M.buttons[button] = true
    draw(pane, state)
    equal(pane.searchCalls, 0, "held mouse button remains deferred " .. button)
    M.buttons[button] = false
end
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "released interactions allow ordering while drag history remains true")
equal(pane.searchCalls, 1, "released interactions finalize only once")

case()
state.compiled.active, state.revision = false, state.revision + 1
M.buttons[0] = true
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "clear defers native restoration during mouse gesture")
M.buttons[0] = false
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "clear restores native order after releasing mouse")

case()
pane, state, items, rows = makePane()
release(pane, rows[2])
draw(pane, state)
M.options.sortMatches = false
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "disable sorting restores native order after real drag release")
M.options.sortMatches = true
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "enable sorting promotes matches without resetting drag history")

local function makeStackPane(kind, preview)
    local stackPane, stackState, stackItems, groups = makePane("", kind)
    local child = M.item("B second")
    child.container = stackPane.inventory
    groups[2].items[3] = child
    groups[2].count = 3
    stackPane.inventory:getItems().values[5] = child
    stackState.matches[child] = true
    stackPane.searchText, stackPane.searchCategoryText, stackPane.searchMode = nil, nil, "name"
    stackPane.headerHgt, stackPane.itemHgt = 20, 20
    if preview then
        stackState.ready = false
        stackState.preview = { matches = { [stackItems[2]] = true, [child] = true },
            counts = { [stackPane.inventory] = 2 }, total = 2, virtualSources = {} }
    end
    draw(stackPane, stackState)
    return stackPane, stackState, stackItems, groups, child
end

case()
local child
pane, state, items, rows, child = makeStackPane()
for _, collapsed in ipairs({false, true}) do
    local previousRefreshes = pane.refreshCalls
    pane.mouseOverOption = 1
    pane.selected[1] = rows[2]
    M.buttons[0] = true
    pane:onMouseDown(3, 24)
    equal(pane.collapsed.B, collapsed, "real stack arrow toggles the group")
    draw(pane, state)
    equal(M.order(pane), "B,D,A,C", "the first held frame keeps the matches first")
    equal(pane.items[2], collapsed and rows[4] or items[2], "row map immediately follows stack layout")
    equal(pane.items[3], collapsed and rows[1] or child, "expanded stack exposes its physical child")
    local hasSelection = false
    for _ in pairs(pane.selected) do hasSelection = true; break end
    equal(hasSelection, false, "original stack click clears selection")
    equal(pane.refreshCalls, previousRefreshes + 1, "stack click rebuild is reused on the held frame")
    M.buttons[0] = false
    pane:onMouseUp(3, 24)
    draw(pane, state)
    equal(M.order(pane), "B,D,A,C", "release keeps the same order")
    equal(pane.refreshCalls, previousRefreshes + 1, "release does not rebuild the stack again")
end

case()
pane, state, items, rows, child = makeStackPane("proxInv")
local selected = M.rowOf(pane, rows[3])
pane.selected[selected], pane.firstSelect = rows[3], selected
pane.mouseOverOption, pane.previousMouseUp = 1, 1
pane.yScroll = -20
M.buttons[0] = true
local previousRefreshes = pane.refreshCalls
pane:onMouseDoubleClick(3, 24)
draw(pane, state)
equal(pane.collapsed.B, false, "real double-click expands a Proximity group")
equal(M.order(pane), "B,D,A,C", "Proximity group remains prioritized while held")
equal(pane.items[3], child, "Proximity expanded row map follows the new children")
equal(pane.selected[M.rowOf(pane, rows[3])], rows[3], "Proximity selection follows the original group")
equal(pane.items[pane.firstSelect], rows[3], "Proximity Shift anchor follows the original group")
equal(pane.yScroll, -20, "expansion does not reset scroll")
equal(pane.refreshCalls, previousRefreshes + 1, "Proximity expansion reuses the click rebuild")

case()
local originalTimestamp = getTimestampMs
getTimestampMs = function() return 1000 end
pane, state, items, rows, child = makeStackPane(nil, true)
equal(M.order(pane), "B,A,C,D", "partial matches are prioritized before the stack click")
local beforeCompletion = pane.refreshCalls
M.buttons[0] = true
pane:onMouseDown(3, 24)
state.ready, state.preview = true, nil
draw(pane, state)
equal(pane.collapsed.B, false, "the real stack handler expands while the search is completing")
equal(M.order(pane), "B,D,A,C", "the first held frame applies the final matches without flashing native order")
equal(pane.items[3], child, "the first held frame draws the expanded child")
equal(pane.refreshCalls, beforeCompletion + 1, "search completion reuses the stack click rebuild")
getTimestampMs = originalTimestamp

case()
pane, state, items, rows = makeStackPane()
M.buttons[0] = true
pane:onMouseDown(3, 24)
state.revision, state.matches = state.revision + 1, {[items[3]] = true}
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "stack gesture cannot apply a different query while held")
M.buttons[0] = false
pane:onMouseUp(3, 24)
draw(pane, state)
equal(M.order(pane), "C,A,B,D", "new query applies after release")

return "SQSEARCH_DRAG_RELEASE cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
