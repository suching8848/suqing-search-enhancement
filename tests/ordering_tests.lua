-- Run with ordering_bootstrap, the real SuQing proximity-selection patch, Ordering.
local M, SQ = OrderingMock, SuQingSearch
local O = assert(SQ.Ordering, "load Ordering.lua first")
local cases, assertions = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case() cases = cases + 1; M.dragReset(); M.options.sortMatches = true end
local function draw(pane, state, dragged, original, ...)
    return O.render(pane, state, dragged == true, original or ISInventoryPane.renderdetails, ...)
end
local function makeFour(kind, expanded)
    local a, b, c, d = M.item("a"), M.item("b"), M.item("c"), M.item("d")
    local ga, gb, gc, gd = M.group("A", {a}, 1), M.group("B", {b}, 2), M.group("C", {c}, 3), M.group("D", {d}, 4)
    local pane = M.pane({ga, gb, gc, gd}, kind)
    if not expanded then
        pane.collapsed = { A = true, B = true, C = true, D = true }
        M.nativeRender(pane, false)
        pane.renderCalls = 0
    end
    return pane, M.state({b, d}), {a, b, c, d}, {ga, gb, gc, gd}
end
local function selectedCount(pane)
    local count = 0
    for _ in pairs(pane.selected) do count = count + 1 end
    return count
end
local function identitySelected(pane, item)
    for _, value in pairs(pane.selected) do if value == item then return true end end
    return false
end

M.emit("OnGameStart")
case()
local realFix = assert(SuQingUIInteractionFixes and SuQingUIInteractionFixes.proximitySelection,
    "load the real deployed proximity selection patch before this test")
equal(realFix.version, "1.0.1", "reviewed real selection bridge version")
equal(realFix.installed, true, "real patch installed through OnGameStart")
local pane, state, items, groups = makeFour()
local backingItems = pane.inventory:getItems().values
local a, b = draw(pane, state, false, nil, "native argument")
equal(a, "native-render", "normal renderer first result preserved")
equal(b, 91, "normal renderer second result preserved")
equal(pane.lastRenderArguments[1], "native argument", "renderer arguments forwarded")
equal(pane.renderCalls, 1, "one original normal render")
equal(pane.searchCalls, 1, "one complete native search finalizer")
equal(pane.refreshCalls, 1, "complete finalizer has one refresh")
equal(pane.searchArguments.name, "native text", "native text finalizer input retained")
equal(pane.searchArguments.category, "native category", "native category finalizer input retained")
equal(pane.searchArguments.mode, "both", "native mode finalizer input retained")
equal(M.order(pane), "B,D,A,C", "stable partition groups hits then misses")
equal(pane.inventory:getItems().values, backingItems, "physical ItemContainer list identity untouched")
for index, item in ipairs(items) do equal(backingItems[index], item, "physical item order unchanged " .. index) end
for index, group in ipairs(groups) do equal(group.items[2], items[index], "group child identity unchanged " .. index) end
draw(pane, state)
equal(pane.searchCalls, 1, "unchanged frame performs no extra finalizer")
equal(pane.refreshCalls, 1, "unchanged frame performs no extra refresh")
equal(pane.renderCalls, 2, "unchanged frame still draws once")
equal(M.order(pane), "B,D,A,C", "stable partition idempotent")

case()
state.matches = { [items[1]] = true, [items[4]] = true }
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,D,B,C", "changed expression starts from native order rather than old partition")
equal(pane.searchCalls, 2, "changed revision finalizes once")
state.matches = {}
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "zero-hit result preserves native order")
equal(#pane.itemslist, 4, "zero-hit result never filters rows out")

case()
pane, state, items, groups = makeFour()
groups[3].pinned = true
pane.pinAfterRefresh = true
draw(pane, state)
equal(table.concat({pane.lastFinalized[1].name, pane.lastFinalized[2].name, pane.lastFinalized[3].name, pane.lastFinalized[4].name}, ","), "C,A,B,D", "complete native finalizer includes post-refresh priority")
equal(M.order(pane), "B,D,C,A", "enhanced partition uses final native priority within misses")
equal(pane.refreshCalls, 1, "post-refresh finalizer does not cause duplicate refresh")
pane.itemSortFunc = function(left, right) return left.rank > right.rank end
draw(pane, state)
equal(M.order(pane), "D,B,C,A", "column comparator change updates both stable priority groups")
equal(pane.searchCalls, 2, "comparator change finalizes once")

case()
pane, state = makeFour()
draw(pane, state)
state.compiled.active = false
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "clear restores current native order")
equal(pane.searchCalls, 2, "clear restores native order once")
draw(pane, state)
equal(pane.searchCalls, 2, "cleared state does not refresh repeatedly")
state.compiled.active, state.ready = true, true
state.revision = state.revision + 1
draw(pane, state)
state.compiled.errorKey = "UI_SQSearch_ErrorUnclosedQuote"
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "half-input error clears old ordering")
local searches = pane.searchCalls
draw(pane, state)
equal(pane.searchCalls, searches, "error state does not repeat finalizer")
state.compiled.errorKey = nil
state.revision = state.revision + 1
draw(pane, state)
M.options.sortMatches = false
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "disabling setting restores native order")
searches = pane.searchCalls
draw(pane, state)
equal(pane.searchCalls, searches, "disabled setting does not refresh repeatedly")
M.options.sortMatches = true
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "re-enabling setting reapplies stable partition")
state.ready = false
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "invalidated match snapshot removes previous ordering")

case()
pane, state, items = makeFour()
state.ready = false
draw(pane, state)
equal(pane.searchCalls, 0, "unready first snapshot does not finalize")
equal(M.order(pane), "A,B,C,D", "unready first snapshot leaves native order")
state.ready = true
pane.inventory.dirty = true
draw(pane, state)
equal(pane.refreshCalls, 1, "dirty normal frame finalizes once before original")
equal(pane.renderCalls, 2, "dirty frame renders once for each test invocation")
equal(pane.inventory.dirty, false, "native finalizer consumes dirty flag")
pane.canonical = { pane.canonical[1], pane.canonical[3], pane.canonical[4] }
pane.inventory.list.values = { items[1], items[3], items[4] }
state.matches = { [items[4]] = true }
state.revision = state.revision + 1
pane.inventory.dirty = true
draw(pane, state)
equal(M.order(pane), "D,A,C", "picked-up group disappears from fresh canonical source")
state.compiled.active = false
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,C,D", "clear never revives removed group from stale baseline")

case()
pane, state, items, groups = makeFour(nil, true)
local originalSelected = pane.selected
pane.selected[M.rowOf(pane, groups[1])] = groups[1]
pane.selected[M.rowOf(pane, items[2])] = items[2]
pane.firstSelect = M.rowOf(pane, items[2])
draw(pane, state)
equal(pane.selected, originalSelected, "generic ordering preserves selection table identity")
equal(getmetatable(pane.selected), nil, "generic temporary selection metatable removed")
equal(selectedCount(pane), 2, "mixed group and child selection count retained")
equal(pane.selected[M.rowOf(pane, groups[1])], groups[1], "group selection remains group, not header item")
equal(pane.selected[M.rowOf(pane, items[2])], items[2], "child selection follows physical identity")
equal(pane.items[pane.firstSelect], items[2], "Shift anchor follows physical child identity")
equal(pane.drawnSelected[M.rowOf(pane, groups[1])], groups[1], "actual draw sees selected group at new row")
equal(pane.drawnSelected[M.rowOf(pane, items[2])], items[2], "actual draw sees selected child at new row")
equal(pane.selected[M.rowOf(pane, items[1])], nil, "group selection never leaks to its physical child")

case()
pane, state, items, groups = makeFour()
pane.selected[M.rowOf(pane, groups[3])] = groups[3]
pane.firstSelect = M.rowOf(pane, groups[3])
draw(pane, state)
equal(pane.items[pane.firstSelect], groups[3], "collapsed-group Shift anchor follows named group")
equal(pane.selected[M.rowOf(pane, groups[3])], groups[3], "collapsed group selection follows partition")
equal(pane.collapsed.C, true, "collapsed flag preserved")

case()
local same1, same2, other = M.item("same"), M.item("same"), M.item("other")
local mixed = M.group("mixed", { same1, same2 }, 2)
local otherGroup = M.group("other", {other}, 1)
pane = M.pane({otherGroup, mixed})
state = M.state({same2})
local beforeChildren = { mixed.items[1], mixed.items[2], mixed.items[3] }
draw(pane, state)
equal(M.order(pane), "mixed,other", "partially matching mixed stack moves as complete group")
local hitCount, itemCount = SQ.rowCount(mixed, state)
equal(hitCount, 1, "mixed stack counts matching instance once")
equal(itemCount, 2, "dummy header does not inflate group total")
for index, child in ipairs(beforeChildren) do equal(mixed.items[index], child, "mixed stack internal order preserved " .. index) end

case()
pane, state, items, groups = makeFour()
local separator = M.separator("equipment-section")
pane.canonical = { groups[1], groups[2], separator, groups[3], groups[4] }
pane.itemslist = { groups[1], groups[2], separator, groups[3], groups[4] }
M.nativeRender(pane, false)
pane.renderCalls = 0
draw(pane, state)
equal(M.order(pane), "B,A,equipment-section,D,C", "unknown separator preserves independent group sections")
equal(pane.itemslist[3], separator, "unknown separator remains boundary")

case()
pane, state = makeFour()
local firstList = pane.itemslist
pane.dragging = 1
draw(pane, state)
equal(pane.itemslist, firstList, "mouse-down pending drag does not replace/reorder row list")
equal(pane.searchCalls, 0, "pre-drag gesture defers finalizer")
pane.dragging = nil
pane.dragStarted = true
draw(pane, state)
equal(pane.searchCalls, 0, "active drag flag defers finalizer")
pane.dragStarted = false
pane.draggingMarquis = true
draw(pane, state)
equal(pane.searchCalls, 0, "marquee multi-selection defers finalizer")
pane.draggingMarquis = false
ISMouseDrag.dragging = {}
draw(pane, state)
equal(pane.searchCalls, 0, "global drag session defers even when current list empty")
ISMouseDrag.dragging = nil
for mouseButton = 0, 2 do
    M.buttons[mouseButton] = true
    draw(pane, state)
    equal(pane.searchCalls, 0, "held mouse gesture defers finalizer for button " .. mouseButton)
    M.buttons[mouseButton] = false
end
draw(pane, state)
equal(pane.searchCalls, 1, "released gesture triggers pending ordering once")
equal(M.order(pane), "B,D,A,C", "released gesture result order")
draw(pane, state)
equal(pane.searchCalls, 1, "released gesture does not repeat refresh")

case()
pane, state = makeFour()
a, b = draw(pane, state, true)
equal(a, "native-drag", "dragged pass renderer result preserved")
equal(b, 92, "dragged pass second result preserved")
equal(pane.searchCalls, 0, "dragged pass never finalizes")
equal(M.order(pane), "A,B,C,D", "dragged pass never reorders")

case()
pane, state = makeFour()
pane.searchContainer = false
draw(pane, state)
equal(pane.refreshCalls, 1, "vanilla without searchContainer falls back to native refresh")
equal(M.order(pane), "B,D,A,C", "vanilla fallback stable partition")
draw(pane, state)
equal(pane.refreshCalls, 1, "vanilla unchanged frame no duplicate refresh")

case()
pane, state, items = makeFour()
local ownerMetatable = { __index = function() return nil end }
setmetatable(pane.selected, ownerMetatable)
local ownerTable = pane.selected
draw(pane, state)
equal(pane.searchCalls, 0, "foreign selection owner defers finalizer")
equal(getmetatable(pane.selected), ownerMetatable, "foreign metatable preserved exactly")
equal(pane.selected, ownerTable, "foreign selected table identity preserved")
equal(M.order(pane), "A,B,C,D", "foreign selection owner leaves base row order")
setmetatable(pane.selected, nil)
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "ordering resumes when foreign owner releases selection")

case()
pane, state, items, groups = makeFour()
pane.selected[1], pane.firstSelect = groups[1], 1
local originalTable = pane.selected
pane.failSearch = true
local ok, message = pcall(draw, pane, state)
equal(ok, false, "native finalizer exception propagated")
equal(tostring(message):find("mock native search failure", 1, true) ~= nil, true, "native finalizer exception not hidden")
equal(getmetatable(pane.selected), nil, "native finalizer exception leaves no shadow metatable")
equal(pane.selected, originalTable, "native finalizer exception preserves selected identity")
pane.failSearch = false
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "native finalizer error does not poison subsequent render")

case()
pane, state, items, groups = makeFour()
pane.selected[1], pane.firstSelect = groups[1], 1
originalTable = pane.selected
pane.failRender = true
ok, message = pcall(draw, pane, state)
equal(ok, false, "native renderer exception propagated")
equal(tostring(message):find("mock native render failure", 1, true) ~= nil, true, "native renderer exception not hidden")
equal(getmetatable(pane.selected), nil, "native renderer exception removes shadow metatable")
equal(pane.selected, originalTable, "native renderer exception restores selected identity")
pane.failRender = false
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "renderer exception does not leave reentry guard stuck")

case()
-- The real Proximity bridge owns a correct private pending snapshot after a
-- native refresh has restored a numerically wrong anchor beyond the render cap.
local many = {}
for index = 1, 80 do many[index] = M.item("many" .. index) end
local target = M.item("target")
local large, targetGroup = M.group("large", many, 1), M.group("target", {target}, 2)
pane = M.pane({large, targetGroup}, "proxInv")
local actualAnchor = M.rowOf(pane, target)
equal(actualAnchor, 53, "renderer caps large group to header plus 50 children")
pane.selected[actualAnchor], pane.firstSelect = target, actualAnchor
originalTable = pane.selected
pane:refreshContainer()
equal(pane.firstSelect, 83, "native restoration reproduces uncapped wrong numeric anchor")
equal(pane.items[pane.firstSelect], nil, "wrong native anchor absent from actual displayed row map")
local restoredBefore = realFix.stats.restored
state = M.state({target})
draw(pane, state)
equal(M.order(pane), "target,large", "prox physical group promoted")
equal(pane.selected, originalTable, "prox compatibility keeps real bridge selected table")
equal(pane.items[pane.firstSelect], target, "real bridge pending snapshot restores target Shift anchor")
equal(pane.selected[M.rowOf(pane, target)], target, "real bridge preserves target physical selection")
equal(realFix.stats.restored > restoredBefore, true, "real bridge performed actual row-map restoration")
equal(getmetatable(pane.selected), nil, "real bridge temporary metatable removed")
equal(pane.drawnSelected[M.rowOf(pane, target)], target, "real bridge renderer highlighted intended physical item")

case()
local hiddenItems = {}
for index = 1, 4 do hiddenItems[index] = M.item("equipped" .. index) end
local equipped, visibleItem = M.group("equipped", hiddenItems, 1), M.item("visible target")
equipped.equipped = true
local visibleGroup = M.group("visible", {visibleItem}, 2)
pane = M.pane({equipped, visibleGroup}, "proxInv")
pane.equippedCollapsed = true
M.nativeRender(pane, false)
actualAnchor = M.rowOf(pane, visibleItem)
equal(actualAnchor, 2, "equipped collapsed groups absent from actual row map")
pane.selected[actualAnchor], pane.firstSelect = visibleItem, actualAnchor
pane:refreshContainer()
equal(pane.firstSelect, 7, "native restoration reproduces hidden-section anchor shift")
state = M.state({visibleItem})
draw(pane, state)
equal(pane.items[pane.firstSelect], visibleItem, "real bridge pending preserves anchor around collapsed equipped section")
equal(pane.selected[M.rowOf(pane, visibleItem)], visibleItem, "real bridge pending preserves child around collapsed equipped section")
equal(M.rowOf(pane, hiddenItems[1]), nil, "ordering never injects omitted equipped physical rows")
equal(pane.equippedCollapsed, true, "ordering does not expand equipped section")

case()
pane, state, items, groups = makeFour("proxInv", true)
pane.selected[M.rowOf(pane, groups[1])] = groups[1]
pane.selected[M.rowOf(pane, items[4])] = items[4]
pane.firstSelect = M.rowOf(pane, groups[1])
pane:refreshContainer()
draw(pane, state)
equal(pane.selected[M.rowOf(pane, groups[1])], groups[1], "real prox bridge retains whole-stack selection")
equal(pane.selected[M.rowOf(pane, items[4])], items[4], "real prox bridge retains child selected with whole stack")
equal(pane.items[pane.firstSelect], groups[1], "real prox bridge retains group Shift anchor")
equal(selectedCount(pane), 2, "real prox bridge does not select whole mixed row accidentally")

case()
pane, state = makeFour()
equal(pane.yScroll, -100, "new query starts while user is scrolled into list")
draw(pane, state)
equal(pane.yScroll, 0, "first completed query sorting scrolls to visible top results")
equal(pane.scrollCalls, 1, "first query scrolls once")
pane.yScroll = -60
draw(pane, state)
equal(pane.yScroll, -60, "ordinary redraw preserves user's new scroll")
state.revision = state.revision + 1
draw(pane, state)
equal(pane.yScroll, -60, "same query refreshed hits do not reset scroll")
pane.inventory.dirty = true
draw(pane, state)
equal(pane.yScroll, -60, "physical transfer/dirty rebuild does not reset scroll")
pane.itemSortFunc = function(left, right) return left.rank > right.rank end
draw(pane, state)
equal(pane.yScroll, -60, "native column-sort change does not reset scroll")
equal(pane.scrollCalls, 1, "no incidental update repeatedly scrolls to top")
state.query, state.revision = "changed query", state.revision + 1
draw(pane, state)
equal(pane.yScroll, 0, "different query scrolls to new result top")
equal(pane.scrollCalls, 2, "different query scrolls exactly once")
pane.yScroll = -80
state.category, state.revision = "Food", state.revision + 1
draw(pane, state)
equal(pane.yScroll, 0, "changed category scrolls to its result top")
equal(pane.scrollCalls, 3, "changed category scrolls once")
state.compiled.active = false
state.revision = state.revision + 1
pane.yScroll = -90
draw(pane, state)
equal(pane.yScroll, -90, "clearing query does not force scroll movement")

case()
for _, version in ipairs({ "2.10.4", "2.10.5", "missing" }) do
    M.cleanVersion = version == "missing" and nil or version
    pane, state, items, groups = makeFour()
    local marker = M.separator(".")
    pane.canonical = { groups[1], groups[2], marker, groups[3], groups[4] }
    pane.itemslist = { groups[1], groups[2], marker, groups[3], groups[4] }
    M.nativeRender(pane, false)
    pane.renderCalls = 0
    draw(pane, state)
    if version == "2.10.4" then
        equal(M.order(pane), "B,D,A,C", "only audited CleanUI decorative separator removed")
        equal(#pane.itemslist, 4, "audited decorative separator removal keeps all physical groups")
    else
        equal(M.order(pane), "B,A,.,D,C", "unknown CleanUI version keeps decorative separator as section boundary " .. version)
        equal(pane.itemslist[3], marker, "unknown version keeps exact separator identity " .. version)
    end
end
M.cleanVersion = "2.10.4"

case()
pane, state, items, groups = makeFour("proxInv", true)
pane.doController = true
pane.selected[M.rowOf(pane, items[1])] = items[1]
pane.firstSelect = M.rowOf(pane, items[1])
draw(pane, state)
equal(pane.selected[M.rowOf(pane, items[1])], items[1], "controller pane uses generic actual-row selection adapter")
equal(pane.items[pane.firstSelect], items[1], "controller pane generic adapter preserves child anchor")
equal(getmetatable(pane.selected), nil, "controller generic adapter clears temporary owner")
pane, state, items, groups = makeFour("proxInv", true)
realFix.enabled = false
pane.selected[M.rowOf(pane, groups[4])] = groups[4]
pane.firstSelect = M.rowOf(pane, groups[4])
draw(pane, state)
equal(pane.selected[M.rowOf(pane, groups[4])], groups[4], "disabled bridge falls back to generic semantic selection")
equal(pane.items[pane.firstSelect], groups[4], "disabled bridge generic adapter preserves group anchor")
realFix.enabled = true

case()
pane, state = makeFour()
pane.failRender = true
ok = pcall(draw, pane, state)
equal(ok, false, "first sorted draw failure propagated")
equal(M.order(pane), "B,D,A,C", "draw failure occurred after stable partition")
pane.failRender = false
state.compiled.active = false
state.revision = state.revision + 1
draw(pane, state)
equal(M.order(pane), "A,B,C,D", "clear after failed first draw still restores native ordering")
equal(getmetatable(pane.selected), nil, "clear after failed draw leaves no shadow owner")

case()
pane, state, items, groups = makeFour("proxInv", true)
pane.doController = true
pane.joyselection = M.rowOf(pane, items[1]) - 1
pane.mouseOverOption = 3
draw(pane, state)
equal(pane.items[pane.joyselection + 1], items[1], "controller cursor follows actual child identity after top ordering")
equal(pane.mouseOverOption, 3, "mouse hover remains at physical pointer row")
state.compiled.active = false
state.revision = state.revision + 1
draw(pane, state)
equal(pane.items[pane.joyselection + 1], items[1], "controller cursor follows child through native order restoration")

case()
pane, state, items, groups = makeFour()
pane.joyselection = M.rowOf(pane, groups[4]) - 1
ISMouseDrag.draggingFocus = {} -- an abandoned focus without a drag payload is not an active drag
draw(pane, state)
equal(M.order(pane), "B,D,A,C", "stale focus alone does not permanently defer ordering")
equal(pane.items[pane.joyselection + 1], groups[4], "controller cursor follows group identity")
M.dragReset()

return "SQSEARCH_ORDERING cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
