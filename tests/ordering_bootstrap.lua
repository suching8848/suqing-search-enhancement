-- Independent offline inventory/renderer model. No game, window or save is loaded.
-- Load the real SuQing_ProximitySelectionFix.lua after this file to test its chain.
OrderingMock = { options = { sortMatches = true }, buttons = {}, callbacks = {}, cleanVersion = "2.10.4", neatVersion = "1.0.2" }
local M = OrderingMock
function isServer() return false end
function isMouseButtonDown(button) return M.buttons[button] == true end
function isCtrlKeyDown() return false end
function isKeyDown(key) return false end
function instanceof(object, kind) return type(object) == "table" and object.kind == kind end
Keyboard = { KEY_A = 30 }
ISMouseDrag = {}
function getModInfoByID(id)
    if (id == "CleanUI" or id == "\\CleanUI") and M.cleanVersion then
        return { getModVersion = function() return M.cleanVersion end,
            getVersionDir = function() return M.cleanBranch end }
    end
    if (id == "NeatUI_Equipment" or id == "\\NeatUI_Equipment") and M.neatVersion then
        return { getModVersion = function() return M.neatVersion end }
    end
    return nil
end
Events = setmetatable({}, { __index = function(self, name)
    local callbacks = {}
    M.callbacks[name] = callbacks
    local event = {}
    function event.Add(callback) callbacks[#callbacks + 1] = callback end
    function event.Remove(callback)
        for index = #callbacks, 1, -1 do if callbacks[index] == callback then table.remove(callbacks, index) end end
    end
    rawset(self, name, event)
    return event
end })
function M.emit(name, ...)
    local copied = {}
    for index, callback in ipairs(M.callbacks[name] or {}) do copied[index] = callback end
    for _, callback in ipairs(copied) do callback(...) end
end
if not table.wipe then function table.wipe(values) for key in pairs(values) do values[key] = nil end end end
local function clone(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end
function M.item(name)
    local item = { name = name, kind = "InventoryItem" }
    function item:getName() return self.name end
    function item:getContainer() return self.container end
    return item
end
function M.group(name, actual, rank)
    local row = { name = name, type = "Item", rank = rank or 0, items = {}, count = #actual + 1 }
    row.items[1] = actual[1] -- the ordinary renderer's duplicated header item
    for _, item in ipairs(actual) do row.items[#row.items + 1] = item end
    row.firstItem = actual[1]
    return row
end
function M.separator(name)
    return { name = name or "section", type = "separator", items = {}, rank = 0 }
end
function M.list(values)
    local object = { values = values or {} }
    function object:size() return #self.values end
    function object:get(index) return self.values[index + 1] end
    function object:contains(value)
        for _, item in ipairs(self.values) do if item == value then return true end end
        return false
    end
    return object
end
local function actualStart(row) return row.cleanUILargeStackOptimized and 1 or 2 end
local function displayItem(row) return row and (row.cleanUIDisplayItem or row.firstItem or (row.items and row.items[1])) end
local function groupIdentity(value)
    if instanceof(value, "InventoryItem") then return value, false end
    if type(value) == "table" and value.type ~= "separator" and value.name then return value.name, true end
end
function M.semantic(pane)
    local result = { items = {}, groups = {} }
    for _, value in pairs(pane.selected or {}) do
        local key, group = groupIdentity(value)
        if key then if group then result.groups[key] = true else result.items[key] = true end end
    end
    if pane.firstSelect and pane.items then result.anchor, result.anchorGroup = groupIdentity(pane.items[pane.firstSelect]) end
    return result
end
ISInventoryPane = { MAX_ITEMS_IN_STACK_TO_RENDER = 50 }
ISInventoryPane.__index = ISInventoryPane
function ISInventoryPane.getActualItems(rows)
    local result = {}
    for _, row in ipairs(rows) do
        if instanceof(row, "InventoryItem") then result[#result + 1] = row
        elseif row.items then for index = actualStart(row), #row.items do result[#result + 1] = row.items[index] end end
    end
    return result
end
-- Models the reviewed public CleanUI selection contracts, including the important
-- mismatch: native restoreSelection counts every expanded child, while the real
-- renderer stops at 50 children and can omit equipped sections entirely.
function ISInventoryPane:saveSelection(selected)
    selected._cleanUISelectedGroups = selected._cleanUISelectedGroups or {}
    local function add(value)
        if instanceof(value, "InventoryItem") then selected[value] = selected[value] or "item"
        else
            local item = displayItem(value)
            if item then selected[item] = "group" end
            if value and value.name then selected._cleanUISelectedGroups[value.name] = true end
        end
    end
    for _, value in pairs(self.selected) do add(value) end
    if ISMouseDrag.dragging and ISMouseDrag.draggingFocus == self then for _, value in ipairs(ISMouseDrag.dragging) do add(value) end end
    return selected
end
function ISInventoryPane:restoreSelection(selected)
    local index = 1
    for _, row in ipairs(self.itemslist) do
        local item = displayItem(row)
        if (selected._cleanUISelectedGroups and selected._cleanUISelectedGroups[row.name]) or (item and selected[item] == "group") then self.selected[index] = row end
        index = index + 1
        if row.type ~= "separator" and not self.collapsed[row.name] then
            for child = actualStart(row), #row.items do
                local value = row.items[child]
                if selected[value] == "item" then self.selected[index] = value end
                index = index + 1
            end
        end
    end
end
local function nativeOrder(pane)
    local rows = clone(pane.canonical)
    -- Sort only inside explicit sections; the upstream renderer owns separators.
    local from = 1
    local function sortRange(to)
        local part = {}
        for index = from, to do part[#part + 1] = rows[index] end
        table.sort(part, pane.itemSortFunc)
        for index, value in ipairs(part) do rows[from + index - 1] = value end
    end
    for index, row in ipairs(rows) do
        if row.type == "separator" then sortRange(index - 1); from = index + 1 end
    end
    sortRange(#rows)
    return rows
end
function ISInventoryPane:refreshContainer()
    self.refreshCalls = self.refreshCalls + 1
    if self.failRefresh then error("mock native refresh failure") end
    local saved = self:saveSelection({})
    local priorAnchor, priorAnchorGroup
    if self.firstSelect and self.items then priorAnchor, priorAnchorGroup = groupIdentity(self.items[self.firstSelect]) end
    self.itemslist = nativeOrder(self)
    table.wipe(self.selected)
    self:restoreSelection(saved)
    self.firstSelect = nil
    local logicalRow = 1
    for _, row in ipairs(self.itemslist) do
        if priorAnchorGroup and row.name == priorAnchor then self.firstSelect = logicalRow end
        logicalRow = logicalRow + 1
        if row.type ~= "separator" and not self.collapsed[row.name] then
            for child = actualStart(row), #row.items do
                if not priorAnchorGroup and row.items[child] == priorAnchor then self.firstSelect = logicalRow end
                logicalRow = logicalRow + 1
            end
        end
    end
    self.refreshContainerCount = self.refreshContainerCount + 1
    self.inventory.dirty = false
    return "native-refresh-result"
end
function ISInventoryPane:searchContainer(name, category, mode)
    self.searchCalls = self.searchCalls + 1
    self.searchArguments = { name = name, category = category, mode = mode }
    if self.failSearch then error("mock native search failure") end
    self.searchText, self.searchCategoryText, self.searchMode = name, category, mode
    self:refreshContainer()
    -- A native post-refresh priority pass intentionally runs after refreshContainer.
    -- This catches a wrapper that only calls refreshContainer and misses the finalizer.
    if self.pinAfterRefresh then
        local arranged = {}
        for _, row in ipairs(self.itemslist) do if row.pinned then arranged[#arranged + 1] = row end end
        for _, row in ipairs(self.itemslist) do if not row.pinned then arranged[#arranged + 1] = row end end
        self.itemslist = arranged
    end
    self.lastFinalized = clone(self.itemslist)
    return "native-search-result"
end
local function renderNative(pane, doDragged, ...)
    pane.renderCalls = pane.renderCalls + 1
    pane.lastDragged = doDragged
    pane.lastRenderArguments = { ... }
    if doDragged then return "native-drag", 92 end
    if pane.refreshWhileRendering then
        pane.refreshWhileRendering = false
        pane:refreshContainer()
    end
    if pane.inventory:isDrawDirty() then pane:refreshContainer() end
    pane.items, pane.drawnSelected = {}, {}
    local function add(value)
        local index = #pane.items + 1
        pane.items[index] = value
        local selected = pane.selected[index]
        if selected then pane.drawnSelected[index] = selected end
    end
    for _, row in ipairs(pane.itemslist) do
        if row.type == "separator" then add(row)
        elseif not (pane.equippedCollapsed and row.equipped) then
            local count = 1
            for _, item in ipairs(row.items) do
                add(count == 1 and row or item)
                if (count == 1 and pane.collapsed[row.name]) or count == ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER + 1 then break end
                count = count + 1
            end
        end
    end
    if pane.failRender then error("mock native render failure") end
    return "native-render", 91
end
ISInventoryPane.renderdetails = renderNative
M.nativeRender = renderNative
function M.pane(rows, kind)
    local pane = setmetatable({ canonical = clone(rows), itemslist = clone(rows), items = {}, selected = {},
        collapsed = {}, refreshContainerCount = 0, refreshCalls = 0, searchCalls = 0, renderCalls = 0,
        yScroll = -100, scrollCalls = 0,
        searchText = "native text", searchCategoryText = "native category", searchMode = "both",
        player = 0, parent = { onCharacter = false, backpacks = {} }, equippedCollapsed = false }, ISInventoryPane)
    pane.itemSortFunc = function(a, b) return a.rank < b.rank end
    local actual = {}
    for _, row in ipairs(rows) do if row.type ~= "separator" then for index = actualStart(row), #row.items do actual[#actual + 1] = row.items[index] end end end
    local container = { dirty = false, kind = kind or "crate", list = M.list(actual) }
    function container:isDrawDirty() return self.dirty end
    function container:getType() return self.kind end
    function container:getItems() return self.list end
    pane.inventory = container
    function pane:setYScroll(value) self.yScroll = value; self.scrollCalls = self.scrollCalls + 1 end
    function pane:getYScroll() return self.yScroll end
    for _, item in ipairs(actual) do item.container = container end
    M.nativeRender(pane, false)
    pane.renderCalls = 0
    return pane
end
function M.state(items)
    local matches = {}
    for _, item in ipairs(items or {}) do matches[item] = true end
    return { compiled = { active = true }, active = true, ready = true, revision = 1, query = "mock query", category = "", matches = matches }
end
function M.order(pane)
    local names = {}
    for _, row in ipairs(pane.itemslist) do names[#names + 1] = row.name end
    return table.concat(names, ",")
end
function M.rowOf(pane, value)
    for row, candidate in ipairs(pane.items) do if candidate == value then return row end end
    return nil
end
function M.dragReset()
    M.buttons = {}
    ISMouseDrag.dragging, ISMouseDrag.draggingFocus = nil, nil
end
SuQingSearch = { getOptions = function() return M.options end }
function SuQingSearch.rowCount(row, state)
    if not row then return 0, 0 end
    if not row.items then return state.matches[row] and 1 or 0, 1 end
    local count, total, seen = 0, 0, {}
    for _, item in ipairs(row.items) do
        if not seen[item] then
            seen[item], total = true, total + 1
            if state.matches[item] then count = count + 1 end
        end
    end
    return count, total
end
function require(name)
    if name == "ISUI/ISInventoryPane" then return ISInventoryPane end
    if name == "SuQingSearch/Runtime" then return SuQingSearch end
    error("unexpected ordering test dependency: " .. tostring(name))
end
