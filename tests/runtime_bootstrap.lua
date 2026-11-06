-- Deterministic offline model. Does not initialize any PZ game/world/save.
SQSearchMock = { time = 10000, callbacks = {}, inventories = {}, loot = {}, options = { pinyin = false, showCounts = true } }
local M = SQSearchMock
function M.list(values)
    local object = { values = values or {} }
    function object:size() return #self.values end
    function object:get(index) return self.values[index + 1] end
    function object:contains(value)
        for _, candidate in ipairs(self.values) do if candidate == value then return true end end
        return false
    end
    return object
end
M.mods = M.list({ "ModernFirearmsSystem" })
function getTimestampMs() return M.time end
function getText(key)
    local translations = {
        UI_SQSearch_Vanilla = "原版", UI_SQSearch_Unknown = "未知来源",
        IGUI_ItemCat_Food = "食物", IGUI_ItemCat_Weapon = "武器",
    }
    return translations[key] or key
end
function instanceof(object, kind) return object and object.kind == kind end
function getSpecificPlayer(index) return index == 0 and M.player or nil end
function getNumActivePlayers() return 1 end
function getPlayerInventory(index) return M.inventories[index] end
function getPlayerLoot(index) return M.loot[index] end
function getActivatedMods() return M.mods end
function getModInfoByID(id)
    if id == "ModernFirearmsSystem" then return { getName = function() return "Modern Firearms System" end } end
end
M.player = { index = 0 }
Events = setmetatable({}, { __index = function(self, name)
    local callbacks = {}
    M.callbacks[name] = callbacks
    local event = {}
    function event.Add(callback)
        for _, existing in ipairs(callbacks) do if existing == callback then return end end
        callbacks[#callbacks + 1] = callback
    end
    function event.Remove(callback)
        for index = #callbacks, 1, -1 do if callbacks[index] == callback then table.remove(callbacks, index) end end
    end
    rawset(self, name, event)
    return event
end })
function M.emit(name, ...)
    local copy = {}
    for index, callback in ipairs(M.callbacks[name] or {}) do copy[index] = callback end
    for _, callback in ipairs(copy) do callback(...) end
end
ISInventoryPane = { renderdetails = function(self, dragged)
    self.nativeRenderCalls = (self.nativeRenderCalls or 0) + 1
    return "native-render-result"
end }
UIFont = { Small = "Small" }
function getTextManager() return { MeasureStringX = function(self, font, text) return #text * 6 end } end
SuQingSearch = SuQingSearch or {}
SuQingSearch.getOptions = function() return M.options end
-- Ordering has its own native-chain regression suite. Runtime tests verify the
-- dispatch and query revisions without replacing their deterministic row map.
SuQingSearch.Ordering = { render = function(pane, state, dragged, original, ...)
    M.orderingCalls = (M.orderingCalls or 0) + 1
    return original(pane, dragged, ...)
end }
-- Files are loaded explicitly into one standalone Kahlua environment by the runner.
function require(name)
    if name == "SuQingSearch/Core" then return SuQingSearch.Core end
    if name == "SuQingSearch/Text" then return assert(SuQingSearch.Text, "load Text first") end
    if name == "SuQingSearch/Settings" then return SuQingSearch end
    if name == "SuQingSearch/Ordering" then return SuQingSearch.Ordering end
    if name == "ISUI/ISInventoryPane" then return ISInventoryPane end
    if name == "pinyin" then
        M.pinyinRequires = (M.pinyinRequires or 0) + 1
        return assert(M.pinyinProvider, "set test pinyin provider before activation")
    end
    error("unexpected test dependency: " .. tostring(name))
end

function M.item(name, fullType, modID, hidden, category)
    local object = { name = name, fullType = fullType, modID = modID or "pz-vanilla", hidden = hidden == true, category = category or "Item" }
    function object:getName() return self.name end
    function object:getFullType() return self.fullType end
    function object:getModID() return self.modID end
    function object:isVanilla() return self.modID == "pz-vanilla" end
    function object:isHidden() return self.hidden end
    function object:getDisplayCategory() return self.category end
    function object:getCategory() return self.category end
    return object
end
function M.container(kind, values, explored, locked, parent)
    local object = { kind = kind, list = M.list(values), explored = explored == true, locked = locked == true, parent = parent, reads = 0 }
    function object:getType() return self.kind end
    function object:getItems() self.reads = self.reads + 1; return self.list end
    function object:isLockedToCharacter(player) return self.locked end
    function object:isExplored() return self.explored end
    function object:getParent() return self.parent end
    return object
end
function M.lockedParent(locked)
    return { kind = "IsoThumpable", locked = locked, isLockedToCharacter = function(self, player) return self.locked end }
end
function M.button(container)
    local object = { inventory = container, width = 40, height = 40, calls = {}, nativeRenderCalls = 0 }
    function object:render() self.nativeRenderCalls = self.nativeRenderCalls + 1 end
    function object:drawRectBorder(...) self.calls[#self.calls + 1] = { kind = "border", args = { ... } } end
    function object:drawRect(...) self.calls[#self.calls + 1] = { kind = "rect", args = { ... } } end
    function object:drawTextCentre(label, ...) self.calls[#self.calls + 1] = { kind = "text", label = label, args = { ... } } end
    return object
end
function M.page(onCharacter, containers)
    local page = { onCharacter = onCharacter, player = 0, backpacks = {}, visible = true }
    for _, container in ipairs(containers or {}) do page.backpacks[#page.backpacks + 1] = M.button(container) end
    function page:isReallyVisible() return self.visible end
    local pane = { parent = page, player = 0, items = {}, headerHgt = 20, itemHgt = 20, width = 320, height = 200, yScroll = 0, calls = {} }
    function pane:getWidth() return self.width end
    function pane:getHeight() return self.height end
    function pane:getYScroll() return self.yScroll end
    function pane:drawRect(...) self.calls[#self.calls + 1] = { kind = "rect", args = { ... } } end
    function pane:drawRectBorder(...) self.calls[#self.calls + 1] = { kind = "border", args = { ... } } end
    function pane:drawRectStatic(...) self.calls[#self.calls + 1] = { kind = "rect-static", args = { ... } } end
    function pane:drawRectBorderStatic(...) self.calls[#self.calls + 1] = { kind = "border-static", args = { ... } } end
    function pane:drawTextRight(label, ...) self.calls[#self.calls + 1] = { kind = "text", label = label, args = { ... } } end
    page.inventoryPane = pane
    return page
end
function M.advance(milliseconds)
    M.time = M.time + milliseconds
    M.emit("OnTick")
end
