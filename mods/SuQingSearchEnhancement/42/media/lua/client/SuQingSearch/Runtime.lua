require "SuQingSearch/Core"
require "SuQingSearch/Text"
require "SuQingSearch/Settings"
require "SuQingSearch/Ordering"
require "ISUI/ISInventoryPane"

local SQ = SuQingSearch
local Core = SQ.Core
SQ.states = SQ.states or {}
SQ.pages = SQ.pages or setmetatable({}, {__mode = "k"})
local modNames = {}
local pinyinEnabled = false
local dueAt = 0
local lastRefresh = 0
local searchHandling

local function now()
    return getTimestampMs()
end

function SQ.getState(playerNum, scope)
    SQ.states[playerNum] = SQ.states[playerNum] or {}
    local states = SQ.states[playerNum]
    if not states[scope] then
        states[scope] = {query = "", compiled = Core.compile(""), matches = {}, counts = {}, total = 0,
            revision = 0, ready = false}
    end
    return states[scope]
end

function SQ.markDirty()
    -- Coalesce game/UI events without postponing a pending refresh indefinitely.
    if dueAt == 0 then dueAt = now() + 120 end
end

function SQ.setQuery(playerNum, text, scope, category, source)
    local state = SQ.getState(playerNum, scope)
    text = text or ""
    category = category or ""
    if state.query == text and state.category == category and state.source == source then return end
    state.query = text
    state.category = category
    state.source = source or "panel"
    state.compiled = Core.compile(text)
    state.revision = state.revision + 1
    state.ready = false
    -- Never retain previous hits while the user is entering a different expression.
    state.matches, state.counts, state.total = {}, {}, 0
    SQ.markDirty()
end

function SQ.clearQuery(playerNum, scope, source)
    local state = SQ.getState(playerNum, scope)
    if source and state.source ~= source then return end
    state.query, state.category, state.source = "", "", nil
    state.compiled = Core.compile("")
    state.revision = state.revision + 1
    state.ready = false
    state.matches, state.counts, state.total = {}, {}, 0
end

local function textMatches(text, term)
    return SQ.Text.matches(text, term, pinyinEnabled)
end

local function categoryMatches(item, query)
    if not query or query == "" then return true end
    for _, category in ipairs({item:getDisplayCategory() or "", item:getCategory() or ""}) do
        if textMatches(category, query) or textMatches(getText("IGUI_ItemCat_" .. category), query) then
            return true
        end
    end
    return false
end

local function readable(container, page)
    if not container then return false end
    local kind = container:getType()
    if kind == "proxInv" or kind == "local" then return false end
    local player = getSpecificPlayer(page.player)
    if not player or container:isLockedToCharacter(player) then return false end
    local parent = container:getParent()
    if parent and instanceof(parent, "IsoThumpable") and parent:isLockedToCharacter(player) then return false end
    return page.onCharacter or kind == "floor" or container:isExplored()
end
SQ.isReadableContainer = readable

function SQ.refreshPage(page)
    if not page.inventoryPane then return end
    local scope = page.onCharacter and "inventory" or "nearby"
    local state = SQ.getState(page.player, scope)
    local previousMatches, previousTotal, previousReady = state.matches, state.total, state.ready
    state.matches, state.counts, state.total = {}, {}, 0
    if not state.compiled.active or state.compiled.errorKey then
        state.ready = false
        return
    end
    pinyinEnabled = SQ.getOptions().pinyin == true
    local options = {
        modNames = modNames,
        vanillaNames = {"vanilla", "\229\142\159\231\137\136", getText("UI_SQSearch_Vanilla")},
        unknownNames = {"unknown", "\230\156\170\231\159\165", getText("UI_SQSearch_Unknown")},
        textMatcher = textMatches,
    }
    local seenContainers, seenItems = {}, {}
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        if not seenContainers[container] and readable(container, page) then
            seenContainers[container] = true
            local items = container:getItems()
            local count = 0
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if not seenItems[item] then
                    seenItems[item] = true
                    if not item:isHidden() and Core.matches(item, state.compiled, options)
                        and categoryMatches(item, state.category) then
                        state.matches[item] = true
                        state.total = state.total + 1
                        count = count + 1
                    end
                end
            end
            state.counts[container] = count
        end
    end
    -- Virtual aggregation tabs project already-counted instances, including only
    -- items present in a readable physical source. They add nothing to the total.
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        if container and (container:getType() == "proxInv" or container:getType() == "local") then
            local items, unique, count = container:getItems(), {}, 0
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if state.matches[item] and not unique[item] then
                    unique[item], count = true, count + 1
                end
            end
            state.counts[container] = count
        end
    end
    local changed = previousTotal ~= state.total
    if not changed then
        for item in pairs(state.matches) do
            if not previousMatches[item] then changed = true; break end
        end
    end
    state.ready = true
    if changed or not previousReady then state.revision = state.revision + 1 end
end

function SQ.rowCount(row, state)
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

function SQ.drawMatches(pane, doDragged)
    if doDragged or not pane.parent or not pane.items then return end
    local page = pane.parent
    local state = SQ.getState(pane.player, page.onCharacter and "inventory" or "nearby")
    if not state.compiled.active or not state.ready then return end
    local header, rowHeight = pane.headerHgt, pane.itemHgt
    local scrollWidth = 0
    if pane.vscroll and pane.isVScrollBarVisible and pane:isVScrollBarVisible() then
        scrollWidth = pane.vscroll:getWidth()
    end
    local width, height = math.max(0, pane:getWidth() - 2 - scrollWidth), pane:getHeight()
    local showCounts = SQ.getOptions().showCounts
    local nativeHighlight = false
    for index, row in ipairs(pane.items) do
        -- CleanUI applies the group's native search flag to every expanded
        -- child. Its row map holds the actual child item, not that flag.
        if type(row) == "table" then
            if row.type == "separator" then nativeHighlight = false
            elseif row.items then nativeHighlight = row.matchesSearch == true end
        end
        local y = (index - 1) * rowHeight + header + pane:getYScroll()
        if y + rowHeight > header and y < height then
            local count, total = SQ.rowCount(row, state)
            local dragged = pane.dragging ~= nil and pane.dragStarted and pane.selected and pane.selected[index]
            if count > 0 and not dragged then
                local top, bottom = math.max(header, y), math.min(height, y + rowHeight)
                -- Same RGBA as CleanUI's native yellow search background.
                -- Preserve selection/hover colors and never stack two yellow
                -- fills when a native category search already painted the row.
                if not nativeHighlight and not (pane.selected and pane.selected[index])
                    and pane.mouseOverOption ~= index then
                    pane:drawRectStatic(1, top, width, bottom - top, 0.3, 0.5, 0.3, 0.1)
                end
                pane:drawRectStatic(1, top, 3, bottom - top, 0.9, 0.82, 0.65, 1)
                pane:drawRectBorderStatic(1, top, width, bottom - top, 0.65, 0.82, 0.65, 1)
                if showCounts and total > 1 and top == y and bottom == y + rowHeight then
                    local label = tostring(count) .. "/" .. tostring(total)
                    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, label) + 6
                    pane:drawRectStatic(width - labelWidth, y + 1, labelWidth, rowHeight - 2, 0.9, 0.12, 0.08, 0.18)
                    pane:drawTextRight(label, width - 3, y + 1 - pane:getYScroll(), 0.92, 0.8, 1, 1, UIFont.Small)
                end
            end
        end
    end
end

local function decorateButton(button, page)
    if button._sqSearchRender then return end
    button._sqSearchRender = true
    local render = button.render
    button.render = function(self)
        if render then render(self) end
        local state = SQ.getState(page.player, page.onCharacter and "inventory" or "nearby")
        local count = state.counts[self.inventory] or 0
        if count > 0 then
            self:drawRectBorder(0, 0, self.width, self.height, 1, 0.82, 0.65, 1)
            if SQ.getOptions().showCounts then
                local label = count > 99 and "99+" or tostring(count)
                self:drawRect(0, self.height - 15, self.width, 15, 0.85, 0.12, 0.08, 0.18)
                self:drawTextCentre(label, self.width / 2, self.height - 16, 1, 0.85, 1, 1, UIFont.Small)
            end
        end
    end
end

function SQ.registerPage(page)
    SQ.pages[page] = true
    for _, button in ipairs(page.backpacks or {}) do decorateButton(button, page) end
    SQ.markDirty()
end

local function installRenderer()
    if SQ.rendererInstalled then return end
    SQ.rendererInstalled = true
    local original = ISInventoryPane.renderdetails
    ISInventoryPane.renderdetails = function(self, doDragged)
        local page = self.parent
        local state = page and SQ.getState(self.player, page.onCharacter and "inventory" or "nearby")
        local result = SQ.Ordering.render(self, state, doDragged, original)
        SQ.drawMatches(self, doDragged)
        return result
    end
end

function SQ.tick()
    local handling = SQ.getSearchHandlingMode and SQ.getSearchHandlingMode() or "all"
    if handling ~= searchHandling then
        local previous = searchHandling
        searchHandling = handling
        -- An in-game sandbox editor may change the policy without ModOptions'
        -- apply callback. Replay text once so stale enhanced hits disappear.
        if previous ~= nil and SQ.Integration then SQ.Integration.refreshOptions() end
    end
    local timestamp = now()
    if dueAt == 0 and timestamp - lastRefresh < 1000 then return end
    if dueAt > timestamp then return end
    dueAt, lastRefresh = 0, timestamp
    for page in pairs(SQ.pages) do
        local current = page.onCharacter and getPlayerInventory(page.player) or getPlayerLoot(page.player)
        if current ~= page then
            SQ.pages[page] = nil
        elseif page:isReallyVisible() then
            SQ.refreshPage(page)
        else
            -- Hidden pages must not advertise out-of-range results.
            local state = SQ.getState(page.player, page.onCharacter and "inventory" or "nearby")
            if state.ready then state.revision = state.revision + 1 end
            state.ready = false
            state.matches, state.counts, state.total = {}, {}, 0
        end
    end
end

local function start()
    SQ.states = {}
    SQ.pages = setmetatable({}, {__mode = "k"})
    Core.clearMetadataCache()
    modNames = {}
    SQ.Text.setConverter(nil)
    local providerEnabled = false
    local mods = getActivatedMods()
    for i = 0, mods:size() - 1 do
        local id = tostring(mods:get(i))
        local normalizedID = id:sub(1, 1) == "\\" and id:sub(2) or id
        local info = getModInfoByID(id) or getModInfoByID(normalizedID)
        if info then
            modNames[id] = info:getName()
            modNames[normalizedID] = info:getName()
        end
        if normalizedID == "yxjs_PinYinSearch" then providerEnabled = true end
    end
    if providerEnabled then
        local ok, value = pcall(require, "pinyin")
        if ok and type(value) == "function" then SQ.Text.setConverter(value) end
    end
    -- Install after OnGameStart bridges have finished replacing renderdetails.
    local deferred
    deferred = function()
        Events.OnTick.Remove(deferred)
        installRenderer()
        for playerNum = 0, getNumActivePlayers() - 1 do
            local inventory, loot = getPlayerInventory(playerNum), getPlayerLoot(playerNum)
            if inventory then SQ.registerPage(inventory) end
            if loot then SQ.registerPage(loot) end
        end
    end
    Events.OnTick.Add(deferred)
end

Events.OnGameStart.Add(start)
Events.OnTick.Add(SQ.tick)
Events.OnRefreshInventoryWindowContainers.Add(function(page, stage)
    if stage == "end" then SQ.registerPage(page) end
end)
Events.OnContainerUpdate.Add(SQ.markDirty)
