-- Loaded after ordering_bootstrap, Ordering and a source-verified fixture of
-- the current CleanUI release handlers. No game, UI or save is opened.
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
function getSpecificPlayer() return {} end
function isShiftKeyDown() return false end

local function makePane(prefix)
    prefix = prefix or ""
    local items, rows = {}, {}
    for index, name in ipairs({"A", "B", "C", "D"}) do
        items[index] = M.item(prefix .. name)
        rows[index] = M.group(prefix .. name, {items[index]}, index)
    end
    local pane = M.pane(rows, "backpack")
    pane.parent.onCharacter = true
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

return "SQSEARCH_DRAG_RELEASE cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
