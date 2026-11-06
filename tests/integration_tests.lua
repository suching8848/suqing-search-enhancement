-- Isolated Lua tests; no game, Java objects, containers or saves are opened.
local count = 0
local Core = assert(SuQingSearch and SuQingSearch.Core, "load Core before integration tests")
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    count = count + 1
end
local function ownSlot(object, name)
    for key, value in pairs(object) do if key == name then return value end end
end
local function event()
    local callbacks = {}
    return {
        callbacks = callbacks,
        Add = function(fn) callbacks[#callbacks + 1] = fn end,
        Remove = function(fn)
            for i = #callbacks, 1, -1 do
                if callbacks[i] == fn then table.remove(callbacks, i) end
            end
        end,
    }
end
Events = {
    OnGameStart = event(), OnTick = event(), OnContainerUpdate = event(),
    OnRefreshInventoryWindowContainers = event(),
}
isServer = function() return false end
local settings = { integrate = true, clickPopup = false }
local active, opened, dirty, queryWrites = {}, {}, 0, 0
local notifications = {}
local function key(player, scope) return tostring(player) .. ":" .. scope end
SuQingSearch = {
    getOptions = function() return settings end,
    shouldHandleQuery = function(value)
        return tostring(value or ""):find("%S") ~= nil
            and (settings.searchHandling ~= "special" or Core.hasSpecialSyntax(value))
    end,
    setQuery = function(player, text, scope, category, source)
        queryWrites = queryWrites + 1
        active[key(player, scope)] = { text = text, category = category, source = source }
    end,
    clearQuery = function(player, scope, source)
        local k = key(player, scope)
        if active[k] and (source == nil or active[k].source == source) then active[k] = nil end
    end,
    open = function(player, scope, text, category) opened[#opened + 1] = { player, scope, text, category } end,
    panelQueryChanged = function(player, scope, text, category)
        notifications[#notifications + 1] = { player, scope, text, category }
    end,
    markDirty = function() dirty = dirty + 1 end,
}
local H = {}
function H:getWindow() return self.inventoryWindow or self.lootWindow end
function H:getSearchMode() return self.mode or "name" end
function H:getSearchTexts()
    if self.mode == "category" then return "", self.text end
    return self.text, self.mode == "both" and (self.category or "") or ""
end
function H:getControl() return self.control end
function H:onSearchTextChange()
    if self.fail then error("native callback failure") end
    local name, category = self:getSearchTexts()
    self.native = { name, category, self:getSearchMode() }
    self.calls = (self.calls or 0) + 1
    return "native-result"
end
function H:clearSearch()
    self.text = ""
    self.category = ""
    self.clearCalls = (self.clearCalls or 0) + 1
    return "native-clear"
end
ISInventoryCommonHandler_InventorySearch = H
local existing = setmetatable({
    text = "", control = {}, playerNum = 2,
    inventoryWindow = { player = 2, onCharacter = true, inventoryPane = {} },
    searchField = { onMouseDown = function() return "existing-click" end },
}, { __index = H })
local existingWindow = { controlsUI = { handlers = { [H] = existing } } }
getSpecificPlayer = function(player) return player == 2 and {} or nil end
getPlayerInventory = function(player) return player == 2 and existingWindow or nil end
getPlayerLoot = function() return nil end

dofile("mods/SuQingSearchEnhancement/42/media/lua/client/SuQingSearch/Integration.lua")
local M = SuQingSearch.Integration
equal(#Events.OnGameStart.callbacks, 1, "startup registered")
Events.OnGameStart.callbacks[1]()
Events.OnGameStart.callbacks[1]()
equal(#Events.OnTick.callbacks, 1, "deferred installation once")
Events.OnTick.callbacks[1]()
equal(#Events.OnTick.callbacks, 0, "tick removed after install")
local installedChange = H.onSearchTextChange
M.install()
equal(H.onSearchTextChange, installedChange, "install idempotent")
settings.clickPopup = true
equal(existing.searchField:onMouseDown(1, 1), "existing-click", "class-keyed existing handler bound")
equal(opened[1][1], 2, "existing handler popup player")
opened = {}
settings.clickPopup = false

local function handler(scope, player)
    local h = setmetatable({ text = "", category = "", control = {}, playerNum = player or 0 }, { __index = H })
    local window = { player = player or 0, onCharacter = scope == "inventory", inventoryPane = {} }
    h[scope == "inventory" and "inventoryWindow" or "lootWindow"] = window
    h.searchField = {
        onMouseDown = function() h.clicked = (h.clicked or 0) + 1; return "original-click" end,
        setText = function(_self, value)
            h.text = value
            if not h.suppressSearchUpdate then h:onSearchTextChange() end
        end,
    }
    h.categorySearchField = {
        setText = function(_self, value)
            h.category = value
            if not h.suppressSearchUpdate then h:onSearchTextChange() end
        end,
    }
    h:getControl()
    return h
end
local inv = handler("inventory")
local loot = handler("nearby", 1)
local orphan = setmetatable({ text = "@Brita hammer", control = {} }, { __index = H })
orphan:onSearchTextChange()
equal(orphan.native[1], "@Brita hammer", "missing window safely delegates raw text")
inv.text = "hammer"
equal(inv:onSearchTextChange(), "native-result", "native return retained")
equal(inv.native[1], "", "plain name withheld from native literal matcher")
equal(active["0:inventory"].text, "hammer", "plain word enters shared matcher")
equal(active["0:inventory"].source, "cleanui", "plain word has field ownership")
equal(notifications[#notifications][1], 0, "plain callback carries player")
equal(notifications[#notifications][2], "inventory", "plain callback carries scope")
equal(notifications[#notifications][3], "hammer", "plain callback carries text")

inv.text = '@Brita hammer -broken | &Base.Axe'
inv.category = "Weapon"
inv.mode = "both"
inv:onSearchTextChange()
equal(active["0:inventory"].text, inv.text, "advanced query unchanged")
equal(active["0:inventory"].source, "cleanui", "source isolated")
equal(active["0:inventory"].category, "Weapon", "category passed to enhanced query")
equal(inv.native[1], "", "advanced name withheld from native matcher")
equal(inv.native[2], "Weapon", "native category preserved")
equal(inv.native[3], "both", "native mode preserved")
equal(rawget(inv, "getSearchTexts"), nil, "inherited method restored exactly")
equal(notifications[#notifications][3], inv.text, "advanced callback carries unmodified text")
equal(notifications[#notifications][4], "Weapon", "advanced callback carries category")

loot.text = "axe saw"
loot:onSearchTextChange()
equal(active["1:nearby"].text, "axe saw", "per-player nearby scope")
equal(active["0:inventory"].text, inv.text, "other scope remains")

inv.mode = "category"
inv.text = "Weapon Tool"
inv:onSearchTextChange()
equal(active["0:inventory"], nil, "category mode clears integrated source")
equal(inv.native[2], "Weapon Tool", "category-only mode delegates without parsing")

inv.mode = "name"
inv.text = "hammer"
active["0:inventory"] = { text = "panel query", source = "panel" }
inv:onSearchTextChange()
equal(active["0:inventory"].text, "hammer", "ordinary field edit replaces panel query")
equal(active["0:inventory"].source, "cleanui", "ordinary field edit owns shared query")

inv.text = "@Brita hammer"
inv:onSearchTextChange()
settings.integrate = false
M.refreshOptions()
equal(active["0:inventory"], nil, "disable clears enhanced ownership")
equal(inv.native[1], "@Brita hammer", "disable restores original raw text")
equal(loot.native[1], "axe saw", "disable replays every existing handler")
active["0:inventory"] = { text = "panel query", source = "panel" }
M.refreshOptions()
equal(active["0:inventory"].text, "panel query", "disable retains panel ownership")
settings.integrate = true
M.refreshOptions()
equal(active["0:inventory"].text, inv.text, "reenable resumes current advanced text")
equal(inv:clearSearch(), "native-clear", "native clear return retained")
equal(active["0:inventory"], nil, "clear button removes integrated query")
equal(inv.clearCalls, 1, "native clear executes exactly once")
equal(notifications[#notifications][3], "", "native clear notifies empty name")
equal(notifications[#notifications][4], "", "native clear notifies empty category")
active["0:inventory"] = { text = "panel query", source = "panel" }
inv:clearSearch()
equal(active["0:inventory"], nil, "integrated clear button clears panel query")
inv.text = "@Brita hammer"
inv:onSearchTextChange()

equal(inv.searchField:onMouseDown(2, 3), "original-click", "normal click result retained")
equal(#opened, 0, "click popup default disabled")
settings.clickPopup = true
loot.mode, loot.category = "both", "Weapon"
equal(loot.searchField:onMouseDown(4, 5), "original-click", "popup click still calls original")
equal(loot.clicked, 1, "native focus click called exactly once")
equal(opened[1][1], 1, "popup player")
equal(opened[1][2], "nearby", "popup scope")
equal(opened[1][3], loot.text, "popup raw query")
equal(opened[1][4], "Weapon", "popup carries native combined category")
local categoryPopup = handler("nearby", 3)
categoryPopup.mode, categoryPopup.text = "category", "Food"
categoryPopup.searchField:onMouseDown(4, 5)
equal(opened[2][3], "", "category-only popup has no name query")
equal(opened[2][4], "Food", "category-only popup carries category")
settings.integrate = false
loot.searchField:onMouseDown(4, 5)
equal(#opened, 2, "disabled integration suppresses click popup")
equal(loot.clicked, 2, "disabled popup preserves native click")
settings.integrate = true

inv.fail = true
local ok = pcall(H.onSearchTextChange, inv)
equal(ok, false, "native errors are surfaced")
equal(rawget(inv, "getSearchTexts"), nil, "method restored even when callback throws")
inv.fail = false
local ownGetter = function(self) return self.text, self.category end
inv.getSearchTexts = ownGetter
inv:onSearchTextChange()
equal(rawget(inv, "getSearchTexts"), ownGetter, "custom instance getter restored")
inv.getSearchTexts = nil

inv.mode = "both"
inv.category = "Weapon"
SuQingSearch.setQuery(0, "@Brita axe", "inventory", "Weapon", "panel")
local oldWrites, oldCalls, oldNotifications = queryWrites, inv.calls, #notifications
equal(M.syncPanel(0, "inventory", "@Brita axe", "Weapon"), true, "panel synchronizes existing field")
equal(inv.text, "@Brita axe", "panel text shown in native field")
equal(inv.category, "Weapon", "panel category shown in native category field")
equal(inv.native[1], "", "panel synchronization suppresses native name highlighting")
equal(inv.native[2], "Weapon", "panel synchronization preserves native category")
equal(active["0:inventory"].source, "panel", "panel sync keeps panel ownership")
equal(queryWrites, oldWrites, "setText does not duplicate enhanced queries")
equal(inv.calls, oldCalls + 1, "panel sync calls native filter exactly once")
equal(inv.suppressSearchUpdate, nil, "panel sync restores nil suppress flag")
equal(#notifications, oldNotifications, "panel sync does not reenter panel callback")
M.refreshOptions()
equal(active["0:inventory"].source, "panel", "option replay preserves synchronized ownership")
equal(#notifications, oldNotifications, "option replay does not notify panel")
inv.searchField:setText("hammer")
equal(active["0:inventory"].text, "hammer", "ordinary edit replaces synchronized panel query")
equal(active["0:inventory"].source, "cleanui", "ordinary edit uses shared matcher ownership")
equal(inv.native[1], "", "ordinary edit avoids duplicate native name highlighting")
equal(inv.native[2], "Weapon", "ordinary edit retains category")
equal(notifications[#notifications][3], "hammer", "ordinary edit updates open panel text")
equal(notifications[#notifications][4], "Weapon", "ordinary edit updates open panel category")

SuQingSearch.setQuery(0, "@Brita axe", "inventory", "Weapon", "panel")
M.syncPanel(0, "inventory", "@Brita axe", "Weapon")
inv.searchField:setText("@Other saw")
equal(active["0:inventory"].source, "cleanui", "advanced edit takes native field ownership")
equal(active["0:inventory"].text, "@Other saw", "advanced edit changes enhanced query")

SuQingSearch.setQuery(0, "axe", "inventory", "Weapon", "panel")
inv.suppressSearchUpdate = true
M.syncPanel(0, "inventory", "axe", nil)
equal(inv.category, "Weapon", "nil panel category retains current category")
equal(inv.suppressSearchUpdate, true, "panel sync restores true suppress flag")
inv.suppressSearchUpdate = nil
SuQingSearch.clearQuery(0, "inventory")
M.syncPanel(0, "inventory", "", "")
equal(inv.text, "", "panel clear synchronizes empty native field")
equal(inv.category, "", "panel clear synchronizes empty category")
equal(active["0:inventory"], nil, "panel clear does not recreate enhanced state")

inv.mode, inv.text, inv.category = "category", "Medical", "preserve"
oldCalls = inv.calls
equal(M.syncPanel(0, "inventory", "@Brita", "Weapon"), false, "category-only field excluded from sync")
equal(inv.text, "Medical", "category-only primary field retained")
equal(inv.category, "preserve", "category-only secondary field retained")
equal(inv.calls, oldCalls, "category-only sync does not refilter native view")

inv.mode, inv.text, inv.category = "both", "old text", "Weapon"
SuQingSearch.setQuery(0, "@Brita axe", "inventory", "Weapon", "panel")
settings.integrate = false
equal(M.syncPanel(0, "inventory", "new text", "Food"), false, "disabled integration does not synchronize panel")
equal(inv.text, "old text", "disabled integration preserves native field")
inv:clearSearch()
equal(active["0:inventory"].source, "panel", "disabled clear leaves standalone panel query")
settings.integrate = true

SuQingSearch.setQuery(0, "@Brita axe", "inventory", "Weapon", "panel")
M.syncPanel(0, "inventory", "@Brita axe", "Weapon")
settings.integrate = false
M.refreshOptions()
equal(active["0:inventory"].source, "panel", "disabling integration detaches panel without clearing it")
oldNotifications = #notifications
inv.searchField:setText("hammer")
equal(active["0:inventory"].source, "panel", "disabled native edit leaves standalone panel query")
equal(#notifications, oldNotifications, "disabled integration does not update panel text")
settings.integrate = true

inv.suppressSearchUpdate = true
local originalSetText = inv.searchField.setText
inv.searchField.setText = function() error("textbox failure") end
ok = pcall(M.syncPanel, 0, "inventory", "axe", "Weapon")
equal(ok, false, "textbox synchronization errors surface")
equal(inv.suppressSearchUpdate, true, "textbox error restores prior suppress flag")
inv.searchField.setText = originalSetText
inv.suppressSearchUpdate = nil

M.onContainerRefresh({}, "begin")
equal(dirty, 0, "intermediate refresh not scanned")
M.onContainerRefresh({}, "end")
M.onContainerUpdate({})
equal(dirty, 2, "completed refresh and content update mark dirty")

for _, value in ipairs({ "@Brita", "&Base.Axe", "-broken", "axe saw", '"red pen"', "axe|saw", "axe |", "axe\\|saw", "axe\\ saw", "hammer", "  hammer  ", "mod-item", "foo@bar", "foo&bar", "\\@literal", "NRB", "M110Rifle" }) do
    equal(M.isSearchQuery(value), true, "shared query routing " .. value)
end
for _, value in ipairs({ "", " ", "\t\r\n" }) do
    equal(M.isSearchQuery(value), false, "empty query routing " .. value)
end
equal(M.isSearchQuery(nil), false, "nil query routing")
inv.mode, inv.category = "both", "Food"
inv.searchField:setText("NRB")
equal(active["0:inventory"].text, "NRB", "single uppercase initials reach shared matcher unchanged")
equal(active["0:inventory"].category, "Food", "single pinyin query keeps category")
equal(inv.native[1], "", "single pinyin query bypasses native name matcher")
equal(inv.native[2], "Food", "single pinyin query preserves native category matcher")
inv.searchField:setText("M110Rifle")
equal(active["0:inventory"].text, "M110Rifle", "compact English query reaches shared matcher")
inv.searchField:setText(" \t ")
equal(active["0:inventory"], nil, "whitespace clears field-owned shared query")

settings.searchHandling = "special"
inv.mode, inv.category, inv.text = "both", "Food", "hammer"
M.refreshOptions()
equal(active["0:inventory"], nil, "special-only policy clears ordinary enhanced query")
equal(inv.native[1], "hammer", "ordinary search retains exact native text and highlighter")
equal(inv.native[2], "Food", "ordinary native search retains category")
inv.searchField:setText("@Brita hammer")
equal(active["0:inventory"].text, "@Brita hammer", "special query uses enhancement in special-only policy")
equal(inv.native[1], "", "special syntax does not enter native literal matching")
inv.searchField:setText("hammer")
equal(active["0:inventory"], nil, "removing special syntax clears stale enhanced results")
equal(inv.native[1], "hammer", "removing special syntax restores native highlight route")
for _, value in ipairs({"@", "&", "-", '"unfinished', "hammer |", "hammer saw", "hammer\\ saw"}) do
    inv.searchField:setText(value)
    equal(active["0:inventory"].text, value, "special and incomplete syntax remains enhanced: " .. value)
end
for _, value in ipairs({"hammer", "  hammer  ", "foo@bar", "mod-item", "NRB", "M110Rifle"}) do
    equal(M.isSearchQuery(value), false, "plain query native policy: " .. value)
end
SuQingSearch.setQuery(0, "hammer", "inventory", "Food", "panel")
M.syncPanel(0, "inventory", "hammer", "Food")
M.refreshOptions()
equal(active["0:inventory"].source, "panel", "explicit enhancement panel retains ownership in special-only mode")
equal(inv.native[1], "", "explicit enhancement panel bypasses native literal matcher")
inv.searchField:setText("hammer")
equal(active["0:inventory"], nil, "ordinary field edit clears synchronized panel query in native policy")
settings.searchHandling = "all"
M.refreshOptions()
equal(active["0:inventory"].text, "hammer", "all policy immediately resumes ordinary enhanced query")
equal(inv.native[1], "", "all policy resumes enhanced highlighter route")

-- PZ's usual class.__index = class inheritance, including the PZO table
-- implementation, must not acquire a persistent per-instance method override.
H.__index = H
local direct = setmetatable({ text = "@Brita", control = {}, playerNum = 0,
    inventoryWindow = { player = 0, onCharacter = true, inventoryPane = {} } }, H)
direct:onSearchTextChange()
equal(ownSlot(direct, "getSearchTexts"), nil, "PZ-style class inheritance retains no getter override")
direct.fail = true
equal(pcall(H.onSearchTextChange, direct), false, "PZ-style inherited callback errors surface")
equal(ownSlot(direct, "getSearchTexts"), nil, "PZ-style inheritance restores exact slot on error")
H.__index = nil

local previous = H.onSearchTextChange
dofile("mods/SuQingSearchEnhancement/42/media/lua/client/SuQingSearch/Integration.lua")
equal(H.onSearchTextChange, previous, "module reload does not stack wrappers")
equal(#Events.OnGameStart.callbacks, 1, "module reload does not stack events")
return "SQSEARCH_INTEGRATION assertions=" .. tostring(count) .. " failures=0"
