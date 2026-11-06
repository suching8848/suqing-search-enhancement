-- Load runtime_bootstrap, Core, Runtime, then this file in standalone Kahlua.
local M, SQ = SQSearchMock, SuQingSearch
local cases, assertions = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case() cases = cases + 1 end
local function firstKey(values)
    for key in pairs(values) do return key end
    return nil
end
local function query(page, text, category, source)
    local scope = page.onCharacter and "inventory" or "nearby"
    SQ.setQuery(page.player, text, scope, category, source or "panel")
    SQ.refreshPage(page)
    return SQ.getState(page.player, scope)
end
local function state(page) return SQ.getState(page.player, page.onCharacter and "inventory" or "nearby") end
local function textDraws(button)
    local labels = {}
    for _, call in ipairs(button.calls) do if call.kind == "text" then labels[#labels + 1] = call.label end end
    return labels
end

local rifle = M.item("M110 Rifle", "Base.M110", "ModernFirearmsSystem", false, "Weapon")
local concealed = M.item("M110 Hidden", "Base.M110Hidden", "ModernFirearmsSystem", true, "Weapon")
local floorItem = M.item("M110 Magazine", "Base.M110Mag", "ModernFirearmsSystem", false, "Weapon")
local unseenItem = M.item("M110 Unseen", "Base.M110Unseen", "ModernFirearmsSystem", false, "Weapon")
local lockedItem = M.item("M110 Locked", "Base.M110Locked", "ModernFirearmsSystem", false, "Weapon")
local parentItem = M.item("M110 LockedParent", "Base.M110Parent", "ModernFirearmsSystem", false, "Weapon")
local virtualOnly = M.item("M110 VirtualOnly", "Base.M110Virtual", "ModernFirearmsSystem", false, "Weapon")
local chest = M.container("crate", { rifle, concealed }, true)
local floor = M.container("floor", { floorItem }, false)
local unexplored = M.container("crate", { unseenItem }, false)
local locked = M.container("crate", { lockedItem }, true, true)
local lockedParent = M.container("crate", { parentItem }, true, false, M.lockedParent(true))
local prox = M.container("proxInv", { rifle, rifle, floorItem, unseenItem, lockedItem, concealed, virtualOnly }, true)
local localTab = M.container("local", { floorItem, rifle, floorItem, parentItem, virtualOnly }, true)
local page = M.page(false, { chest, floor, unexplored, locked, lockedParent, prox, localTab, chest })
M.loot[0] = page

case()
local results = query(page, "m110")
equal(results.total, 2, "physical sources count unique visible instances")
equal(results.matches[rifle], true, "explored chest item readable")
equal(results.matches[floorItem], true, "floor readable without exploration flag")
equal(results.matches[concealed], nil, "hidden inventory item rejected")
equal(results.matches[unseenItem], nil, "unexplored item rejected")
equal(results.matches[lockedItem], nil, "locked container rejected")
equal(results.matches[parentItem], nil, "locked parent rejected")
equal(results.matches[virtualOnly], nil, "virtual-only item not revealed")
equal(chest.reads, 1, "duplicate button does not rescan physical container")
equal(unexplored.reads, 0, "unexplored item list never read")
equal(locked.reads, 0, "locked item list never read")
equal(lockedParent.reads, 0, "locked parent item list never read")
equal(results.counts[chest], 1, "chest count excludes hidden item")
equal(results.counts[floor], 1, "floor count")
equal(results.counts[prox], 2, "prox projects only readable unique physical items")
equal(results.counts[localTab], 2, "local projects only readable unique physical items")
equal(SQ.isReadableContainer(prox, page), false, "virtual container is not physical source")
equal(SQ.isReadableContainer(localTab, page), false, "local aggregation is not physical source")

case()
local ownItem = M.item("M110 Backpack", "Base.M110Bag", "ModernFirearmsSystem")
local ownContainer = M.container("bag", { ownItem }, false)
local ownPage = M.page(true, { ownContainer })
M.inventories[0] = ownPage
local ownState = query(ownPage, "m110")
equal(ownState.total, 1, "own inventory readable independent of explored flag")
equal(results.total, 2, "inventory and nearby state separate")
ownContainer.locked = true
SQ.refreshPage(ownPage)
equal(ownState.total, 0, "locks still respected for own page")
ownContainer.locked = false

case()
local renamed = M.item("M110 Rifle", "Base.Renamed", "ModernFirearmsSystem")
local otherModRifle = M.item("M110 Rifle", "OtherMod.M110", "AnotherMod")
local mfsShotgun = M.item("Shotgun", "Base.MFSShotgun", "ModernFirearmsSystem")
local rowContainer = M.container("crate", { rifle, otherModRifle, mfsShotgun, renamed }, true)
local rowPage = M.page(false, { rowContainer })
results = query(rowPage, "@ModernFirearmsSystem m110 -&Base.Renamed")
local count, total = SQ.rowCount({ items = { rifle, otherModRifle, mfsShotgun, renamed, rifle } }, results)
equal(count, 1, "whole expression applies to each instance in mixed displayed stack")
equal(total, 4, "mixed stack total deduplicates same instance")
count, total = SQ.rowCount(rifle, results)
equal(count, 1, "single row instance matched")
equal(total, 1, "single row total")
count, total = SQ.rowCount(otherModRifle, results)
equal(count, 0, "same name different source rejected")
count, total = SQ.rowCount(nil, results)
equal(count, 0, "nil row count")
equal(total, 0, "nil row total")

case()
results = query(rowPage, "m110", "Weapon")
equal(results.total, 1, "category filter AND expression")
results = query(rowPage, "m110", "武器")
equal(results.total, 1, "localized category filter")
results = query(rowPage, "m110", "Food")
equal(results.total, 0, "nonmatching category never broadens result")

case()
results = query(rowPage, "m110")
equal(results.total, 3, "initial result")
SQ.setQuery(0, "shotgun", "nearby", "", "panel")
equal(results.total, 0, "new input immediately clears previous total")
equal(firstKey(results.matches), nil, "new input immediately clears previous row hits")
equal(firstKey(results.counts), nil, "new input immediately clears previous button counts")
SQ.refreshPage(rowPage)
equal(results.total, 1, "changed query refreshed")
SQ.setQuery(0, '"unfinished', "nearby", "", "panel")
SQ.refreshPage(rowPage)
equal(results.total, 0, "incomplete quote never shows stale results")
equal(firstKey(results.matches), nil, "syntax error clears matches")
equal(type(results.compiled.errorKey), "string", "syntax error has translated key")
results = query(rowPage, "  ")
equal(results.compiled.active, false, "whitespace deactivates highlights")
equal(results.total, 0, "empty input does not report all items")
equal(firstKey(results.counts), nil, "empty input clears counts")

case()
results = query(rowPage, "m110", "", "cleanui")
SQ.clearQuery(0, "nearby", "panel")
equal(results.source, "cleanui", "other source cannot erase query owner")
equal(results.total, 3, "other source clear leaves active owned query")
SQ.clearQuery(0, "nearby", "cleanui")
equal(results.source, nil, "owner source removed")
equal(results.query, "", "owner query cleared")
equal(results.total, 0, "owner result cleared")
equal(firstKey(results.matches), nil, "owner row highlights cleared")
equal(firstKey(results.counts), nil, "owner button counts cleared")

case()
local mutable = M.item("M110 Mutable", "Base.Mutable", "ModernFirearmsSystem")
local dynamicContainer = M.container("crate", { mutable }, true)
local dynamicPage = M.page(false, { dynamicContainer })
results = query(dynamicPage, "m110")
equal(results.total, 1, "dynamic source initial hit")
mutable.name = "Renamed supply box"
SQ.refreshPage(dynamicPage)
equal(results.total, 0, "rename invalidates old name without changing object identity")
SQ.setQuery(0, "supply", "nearby", "", "panel")
SQ.refreshPage(dynamicPage)
equal(results.total, 1, "renamed text becomes searchable")
dynamicContainer.list.values = {}
SQ.refreshPage(dynamicPage)
equal(results.total, 0, "picked-up item leaves nearby result")
ownContainer.list.values = { mutable }
ownState = query(ownPage, "supply")
equal(ownState.total, 1, "same instance enters own inventory result")
dynamicContainer.list.values = { mutable }
ownContainer.list.values = {}
SQ.refreshPage(ownPage)
SQ.refreshPage(dynamicPage)
equal(ownState.total, 0, "dropping removes from own inventory")
equal(results.total, 1, "dropped source restored to nearby")
mutable.hidden = true
SQ.refreshPage(dynamicPage)
equal(results.total, 0, "item hidden after initial hit removed")
mutable.hidden = false
dynamicContainer.explored = false
SQ.refreshPage(dynamicPage)
equal(results.total, 0, "container becoming inaccessible clears results")

case()
local first = M.container("crate", { rifle }, true)
local second = M.container("crate", { rifle, floorItem }, true)
local buttonPage = M.page(false, { first })
SQ.registerPage(buttonPage)
results = query(buttonPage, "m110")
local button = buttonPage.backpacks[1]
button:render()
equal(button.nativeRenderCalls, 1, "decorator preserves native button render")
equal(textDraws(button)[1], "1", "initial button badge")
local decorated = button.render
SQ.registerPage(buttonPage)
equal(button.render, decorated, "repeat registration does not wrap button twice")
button.inventory = second
SQ.refreshPage(buttonPage)
button.calls = {}
button:render()
equal(textDraws(button)[1], "2", "reused button reads current container rather than captured source")
equal(button.nativeRenderCalls, 2, "reused button still calls native renderer once")
SQ.clearQuery(0, "nearby")
button.calls = {}
button:render()
equal(#button.calls, 0, "clear removes badge immediately")

case()
M.loot[0], M.inventories[0] = page, ownPage
M.emit("OnGameStart")
M.advance(121)
equal(SQ.rendererInstalled, true, "renderer deferred until first tick after game start")
results = query(page, '@"Modern Firearms System" m110')
equal(results.total, 2, "active mod display name registry used")
local pane = page.inventoryPane
pane.items = { { items = { rifle, floorItem, concealed } } }
pane.calls = {}
local renderResult = ISInventoryPane.renderdetails(pane, false)
equal(renderResult, "native-render-result", "renderer preserves native return value")
equal(pane.nativeRenderCalls, 1, "native row renderer called once")
local foundFraction = false
for _, call in ipairs(pane.calls) do if call.kind == "text" and call.label == "2/3" then foundFraction = true end end
equal(foundFraction, true, "mixed row displays actual matching fraction")
pane.calls = {}
ISInventoryPane.renderdetails(pane, true)
equal(#pane.calls, 0, "dragging never draws search overlays")

case()
-- Native-colored highlighting is per displayed item, including expanded mixed
-- stacks. Selection/hover keep their native backgrounds and their purple edge.
results = query(page, "m110")
pane.items = { { items = { rifle, concealed, floorItem } }, rifle, concealed, floorItem }
local function coloredCalls(kind, alpha, red, green, blue)
    local count = 0
    for _, call in ipairs(pane.calls) do
        local args = call.args
        if call.kind == kind and args[5] == alpha and args[6] == red
            and args[7] == green and args[8] == blue then count = count + 1 end
    end
    return count
end
local function yellow() return coloredCalls("rect-static", 0.3, 0.5, 0.3, 0.1) end
local function purple() return coloredCalls("border-static", 0.65, 0.82, 0.65, 1) end
pane.calls = {}
SQ.drawMatches(pane, false)
equal(yellow(), 3, "native yellow applied only to matching group and children")
equal(purple(), 3, "purple borders accompany yellow on matching rows")
pane.items[1].matchesSearch = true
pane.calls = {}
SQ.drawMatches(pane, false)
equal(yellow(), 0, "native category yellow never receives a second fill")
equal(purple(), 3, "native highlighted groups retain enhanced purple borders")
pane.items[1].matchesSearch = false
pane.selected, pane.mouseOverOption = { [1] = true }, 2
pane.calls = {}
SQ.drawMatches(pane, false)
equal(yellow(), 1, "selected and hovered rows retain native background colors")
equal(purple(), 3, "selected and hovered matches retain purple edges")
pane.mouseOverOption, pane.selected = nil, { [2] = true }
pane.dragging, pane.dragStarted, pane.calls = {}, true, {}
SQ.drawMatches(pane, false)
equal(yellow(), 2, "dragged selected item receives no background at its old position")
equal(purple(), 2, "dragged selected item receives no purple ghost border")
pane.dragging, pane.dragStarted, pane.selected, pane.calls = nil, false, {}, {}
pane.vscroll = { getWidth = function() return 11 end }
pane.isVScrollBarVisible = function() return true end
SQ.drawMatches(pane, false)
equal(pane.calls[1].args[3], pane.width - 13, "highlight leaves actual visible scrollbar width free")
pane.isVScrollBarVisible = function() return false end
pane.calls = {}
SQ.drawMatches(pane, false)
equal(pane.calls[1].args[3], pane.width - 2, "no fixed empty strip when scrollbar is hidden")
pane.selected, pane.mouseOverOption, pane.yScroll = {}, nil, -25
pane.calls = {}
SQ.drawMatches(pane, false)
equal(yellow(), 2, "scrolled-out group does not draw a background")
for _, call in ipairs(pane.calls) do
    if call.kind == "rect-static" or call.kind == "border-static" then
        equal(call.args[2] >= pane.headerHgt, true, "search overlays never cover the header")
    end
end
pane.yScroll, pane.calls = 0, {}
results.ready = false
SQ.drawMatches(pane, false)
equal(#pane.calls, 0, "pending snapshot never paints stale matches")
SQ.clearQuery(0, "nearby")
SQ.drawMatches(pane, false)
equal(#pane.calls, 0, "native-only ordinary queries receive no enhanced decoration")

case()
-- Event coalescing: multiple container signals do not delay an already due refresh.
SQ.pages = setmetatable({ [page] = true }, { __mode = "k" })
SQ.clearQuery(0, "nearby")
M.advance(1200)
SQ.setQuery(0, "m110", "nearby", "", "panel")
M.emit("OnContainerUpdate")
M.advance(60)
M.emit("OnContainerUpdate")
M.advance(59)
equal(state(page).total, 0, "debounce avoids per-keystroke scan")
M.advance(1)
equal(state(page).total, 2, "pending update not postponed by subsequent event")
page.visible = false
M.advance(1001)
equal(state(page).total, 0, "hidden page clears cached totals")
equal(firstKey(state(page).matches), nil, "hidden page clears cached highlights")
page.visible = true
M.advance(1001)
equal(state(page).total, 2, "visible page periodic refresh rebuilds result")
chest.list.values = {}
M.emit("OnContainerUpdate")
M.advance(121)
equal(state(page).total, 1, "container event removes picked-up source and virtual duplicate")
equal(state(page).counts[prox], 1, "virtual badge follows updated physical sources")
equal(state(page).counts[localTab], 1, "local badge follows updated physical sources")

case()
local oldCount = #M.callbacks.OnTick
M.emit("OnGameStart")
M.advance(121)
equal(#M.callbacks.OnTick, oldCount, "deferred install callback removes itself")
equal(SQ.rendererInstalled, true, "repeated lifecycle does not reset renderer")

case()
local revisionItem = M.item("Bolt", "Base.Bolt", "pz-vanilla")
local revisionContainer = M.container("crate", {revisionItem}, true)
local revisionPage = M.page(false, {revisionContainer})
SQ.setQuery(0, "bolt", "nearby", "", "panel")
local revisionState = SQ.getState(0, "nearby")
equal(revisionState.ready, false, "new query invalidates old ordering snapshot")
local pendingRevision = revisionState.revision
SQ.refreshPage(revisionPage)
equal(revisionState.ready, true, "completed snapshot enables result priority")
equal(revisionState.revision, pendingRevision + 1, "completed snapshot advances ordering revision")
SQ.refreshPage(revisionPage)
equal(revisionState.revision, pendingRevision + 1, "unchanged periodic snapshot does not trigger a new sort")
revisionItem.name = "Washer"
SQ.refreshPage(revisionPage)
equal(revisionState.total, 0, "renamed item leaves match set")
equal(revisionState.revision, pendingRevision + 2, "changed match set advances ordering revision")
SQ.clearQuery(0, "nearby")
equal(revisionState.ready, false, "clearing requests native-order restoration")
equal(revisionState.revision, pendingRevision + 3, "clear invalidates ordering cache")
equal((M.orderingCalls or 0) >= 2, true, "renderer dispatches both passes through ordering adapter")

case()
local replays = 0
SQ.getSearchHandlingMode = function() return M.options.searchHandling or "all" end
SQ.Integration = { refreshOptions = function() replays = replays + 1 end }
SQ.tick()
M.options.searchHandling = "special"
SQ.tick()
equal(replays, 1, "live sandbox mode change replays current field routing")
SQ.tick()
equal(replays, 1, "unchanged sandbox mode does not repeatedly replay fields")
M.options.searchHandling = "all"
SQ.tick()
equal(replays, 2, "switching back to all replays fields immediately")
return "SQSEARCH_RUNTIME cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
