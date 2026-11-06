-- Adapt CleanUI's existing search fields without replacing its controls or row data.
-- Installation is deferred until the first tick after OnGameStart so the legacy
-- pinyin/selection compatibility layers have installed their runtime wrappers.
if isServer and isServer() then return end

SuQingSearch = SuQingSearch or {}
local SQ = SuQingSearch
SQ.Integration = SQ.Integration or {}
local M = SQ.Integration
if M.loaded then return end
M.loaded = true

local handlers = setmetatable({}, { __mode = "k" })
local installedClasses = setmetatable({}, { __mode = "k" })
local boundFields = setmetatable({}, { __mode = "k" })
local nativeChanges = setmetatable({}, { __mode = "k" })
local syncedPanels = setmetatable({}, { __mode = "k" })
local SOURCE = "cleanui"
local replayingOptions = false

local function options()
    return SQ.getOptions and SQ.getOptions() or { integrate = true, clickPopup = false }
end

-- The sandbox policy only controls existing search fields. The dedicated
-- enhancement panel remains an explicit request to use the shared matcher.
function M.isSearchQuery(value)
    if SQ.shouldHandleQuery then return SQ.shouldHandleQuery(value) end
    return tostring(value or ""):find("%S") ~= nil
end

local function contextFor(handler)
    local window = handler.getWindow and handler:getWindow()
        or handler.inventoryWindow or handler.lootWindow
    if not window then return nil end
    local player = handler.playerNum or window.player or 0
    local scope = (window.onCharacter == true or handler.inventoryWindow ~= nil)
        and "inventory" or "nearby"
    return player, scope, window
end

local function clearOwnedQuery(handler, allSources)
    local player, scope = contextFor(handler)
    if player ~= nil and SQ.clearQuery then
        if allSources then SQ.clearQuery(player, scope)
        else SQ.clearQuery(player, scope, SOURCE) end
    end
end

local function notifyPanel(handler, text, category)
    if replayingOptions or options().integrate == false or not SQ.panelQueryChanged then return end
    local player, scope = contextFor(handler)
    if player ~= nil then SQ.panelQueryChanged(player, scope, text or "", category or "") end
end

local function bindField(handler, field)
    if not field or boundFields[field] then return end
    boundFields[field] = true
    local original = field.onMouseDown
    field.onMouseDown = function(self, x, y)
        local result
        if original then result = original(self, x, y) end
        local settings = options()
        if settings.integrate ~= false and settings.clickPopup == true and SQ.open then
            local player, scope = contextFor(handler)
            if player ~= nil then
                local text, category
                if handler.getSearchTexts then text, category = handler:getSearchTexts() end
                SQ.open(player, scope, text or "", category or "")
            end
        end
        return result
    end
end

function M.attach(handler, originalChange)
    if not handler then return end
    handlers[handler] = true
    if originalChange then nativeChanges[handler] = originalChange end
    -- The primary field has normal text-editing/focus behavior; the optional
    -- popup does not consume its left-click or change the category field.
    bindField(handler, handler.searchField)
end

local function ownSlot(object, name)
    -- PZO's table implementation can expose inherited entries through rawget.
    -- Iteration still distinguishes a real instance override from its class.
    for key, value in pairs(object) do
        if key == name then return value end
    end
end

local function withCategoryOnly(handler, original, category, ...)
    -- Shadow this instance only, preserving both inherited methods and unusual
    -- instance overrides. Always restore the exact previous slot on an error.
    local previous = ownSlot(handler, "getSearchTexts")
    handler.getSearchTexts = function() return "", category end
    local ok, result = pcall(original, handler, ...)
    handler.getSearchTexts = previous
    if not ok then error(result, 0) end
    return result
end

local function attachExisting(class, originalChange)
    if not getSpecificPlayer then return end
    for player = 0, 3 do
        if getSpecificPlayer(player) then
            local inventory = getPlayerInventory and getPlayerInventory(player)
            local loot = getPlayerLoot and getPlayerLoot(player)
            for _, window in pairs({ inventory = inventory, loot = loot }) do
                local controls = window.controlsUI
                if controls and controls.handlers then M.attach(controls.handlers[class], originalChange) end
            end
        end
    end
end

function M.install()
    local class = ISInventoryCommonHandler_InventorySearch
    if not class or type(class.onSearchTextChange) ~= "function"
        or type(class.getControl) ~= "function" then return false end
    if installedClasses[class] then return true end
    installedClasses[class] = true

    local originalChange = class.onSearchTextChange
    local originalControl = class.getControl
    local originalClear = class.clearSearch
    class.getControl = function(self, ...)
        local result = originalControl(self, ...)
        M.attach(self, originalChange)
        return result
    end
    class.onSearchTextChange = function(self, ...)
        M.attach(self, originalChange)
        local enabled = options().integrate ~= false
        local player, scope, window = contextFor(self)
        local mode = self.getSearchMode and self:getSearchMode() or self.searchMode or "name"
        local name, category
        if self.getSearchTexts then name, category = self:getSearchTexts() end
        if enabled and player ~= nil and window.inventoryPane and mode ~= "category"
            and M.isSearchQuery(name) and type(SQ.setQuery) == "function" then
            syncedPanels[self] = nil
            SQ.setQuery(player, name or "", scope, category or "", SOURCE)
            -- Native category mode, refresh, selection preservation and the old
            -- pinyin wrapper remain in the chain. Our shared name query
            -- is withheld from CleanUI's literal matcher.
            local result = withCategoryOnly(self, originalChange, category or "", ...)
            notifyPanel(self, name, category)
            return result
        end
        -- A player editing a panel-synchronized field makes this field the new
        -- authority. Disabling integration only detaches the two interfaces.
        clearOwnedQuery(self, enabled and syncedPanels[self] == true)
        syncedPanels[self] = nil
        local result = originalChange(self, ...)
        notifyPanel(self, name, category)
        return result
    end
    if type(originalClear) == "function" then
        class.clearSearch = function(self, ...)
            -- CleanUI's clear button suppresses text callbacks, then invokes
            -- pane:searchContainer directly. It still needs to clear our owner.
            clearOwnedQuery(self, options().integrate ~= false)
            syncedPanels[self] = nil
            local result = originalClear(self, ...)
            notifyPanel(self, "", "")
            return result
        end
    end

    attachExisting(class, originalChange)
    return true
end

-- The standalone panel already owns SQ's query state when calling this method.
-- Reflect it into an existing CleanUI field without promoting it to "cleanui"
-- ownership or running the native literal-name highlighter alongside it.
function M.syncPanel(playerNum, scope, text, category)
    if options().integrate == false then return false end
    local updated = false
    for handler in pairs(handlers) do
        local player, handlerScope = contextFor(handler)
        local mode = handler.getSearchMode and handler:getSearchMode() or handler.searchMode or "name"
        local original = nativeChanges[handler]
        if player == playerNum and handlerScope == scope and mode ~= "category"
            and original and handler.searchField and handler.searchField.setText then
            local effectiveCategory = category
            if effectiveCategory == nil and handler.getSearchTexts then
                local _name
                _name, effectiveCategory = handler:getSearchTexts()
            end
            effectiveCategory = effectiveCategory or ""
            local previousSuppress = handler.suppressSearchUpdate
            handler.suppressSearchUpdate = true
            local ok, result = pcall(function()
                handler.searchField:setText(text or "")
                if handler.categorySearchField and handler.categorySearchField.setText then
                    handler.categorySearchField:setText(effectiveCategory)
                end
            end)
            handler.suppressSearchUpdate = previousSuppress
            if not ok then error(result, 0) end
            syncedPanels[handler] = true
            withCategoryOnly(handler, original, effectiveCategory)
            updated = true
        end
    end
    return updated
end

-- Settings changes replay current field text through the newly selected route.
-- clearQuery's source argument protects queries owned by the standalone panel.
function M.refreshOptions()
    local previousReplay = replayingOptions
    replayingOptions = true
    local ok, result = pcall(function()
        for handler in pairs(handlers) do
            if options().integrate ~= false and syncedPanels[handler] and nativeChanges[handler] then
                -- Applying an unrelated option is not a user edit of this field.
                local _name, category = handler:getSearchTexts()
                withCategoryOnly(handler, nativeChanges[handler], category or "")
            elseif handler.onSearchTextChange then
                handler:onSearchTextChange()
            end
        end
    end)
    replayingOptions = previousReplay
    if not ok then error(result, 0) end
end

local function markDirty()
    if SQ.markDirty then SQ.markDirty() end
end
M.onContainerUpdate = markDirty
function M.onContainerRefresh(_page, stage)
    if stage == "end" then markDirty() end
end

local installPending = false
local function installOnTick()
    if Events and Events.OnTick then Events.OnTick.Remove(installOnTick) end
    installPending = false
    M.install()
end
function M.scheduleInstall()
    if installPending then return end
    if Events and Events.OnTick then
        installPending = true
        Events.OnTick.Add(installOnTick)
    else
        M.install()
    end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(M.scheduleInstall) end
    if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(M.onContainerUpdate) end
    if Events.OnRefreshInventoryWindowContainers then
        Events.OnRefreshInventoryWindowContainers.Add(M.onContainerRefresh)
    end
end
