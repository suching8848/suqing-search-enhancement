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
local REFRESH_DELAY_MS = 120
local AUDIT_INTERVAL_MS = 1000
local SLICE_BUDGET_MS = 2
local SLICE_MAX_STEPS = 96
local nextPage = 1
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

local function active(state)
    return state.compiled.active and not state.compiled.errorKey
end

local function markStateDirty(state, dueAt)
    -- A running scan can finish. A burst of events requests just one follow-up.
    if active(state) and not state.dueAt then state.dueAt = dueAt end
end

function SQ.markDirty()
    local dueAt = now() + REFRESH_DELAY_MS
    for _, states in pairs(SQ.states) do
        for _, state in pairs(states) do
            if state.scan and not state.ready then state.scan.checkContents = true end
            markStateDirty(state, dueAt)
        end
    end
end

local function clearResults(state)
    state.ready, state.sources = false, nil
    state.preview = nil
    state.matches, state.counts, state.total = {}, {}, 0
end

local function invalidateResults(state)
    if state.ready or state.preview then
        clearResults(state)
        state.revision = state.revision + 1
    end
end

function SQ.setQuery(playerNum, text, scope, category, source)
    local state = SQ.getState(playerNum, scope)
    text, category, source = text or "", category or "", source or "panel"
    if state.query == text and state.category == category and state.source == source then return end
    state.query, state.category, state.source = text, category, source
    state.compiled = Core.compile(text)
    state.revision = state.revision + 1
    state.scan, state.dueAt, state.auditAt = nil, nil, nil
    state.matchText = nil
    clearResults(state)
    markStateDirty(state, now() + REFRESH_DELAY_MS)
end

function SQ.clearQuery(playerNum, scope, source)
    local state = SQ.getState(playerNum, scope)
    if source and state.source ~= source then return end
    state.query, state.category, state.source = "", "", nil
    state.compiled = Core.compile("")
    state.revision = state.revision + 1
    state.scan, state.dueAt, state.auditAt = nil, nil, nil
    state.matchText = nil
    clearResults(state)
end

local function categoryMatches(item, query, matchText)
    if not query or query == "" then return true end
    for _, category in ipairs({item:getDisplayCategory() or "", item:getCategory() or ""}) do
        if matchText(category, query) or matchText(getText("IGUI_ItemCat_" .. category), query) then
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

local function getSources(page)
    local physical, virtual, seen = {}, {}, {}
    for _, button in ipairs(page.backpacks or {}) do
        local container = button.inventory
        if container and not seen[container] then
            seen[container] = true
            local kind = container:getType()
            if kind == "proxInv" or kind == "local" then
                virtual[#virtual + 1] = container
            elseif readable(container, page) then
                physical[#physical + 1] = container
            end
        end
    end
    physical.physicalCount = #physical
    for _, container in ipairs(virtual) do physical[#physical + 1] = container end
    return physical
end

local function sameSources(a, b)
    if not a or #a ~= #b or a.physicalCount ~= b.physicalCount then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function newScan(page, sources, state)
    local pinyin = SQ.getOptions().pinyin == true
    if not state.matchText or state.matcherPinyin ~= pinyin then
        state.matchText, state.matcherPinyin = SQ.Text.newMatcher(pinyin), pinyin
    end
    local options = {
        modNames = modNames,
        vanillaNames = {"vanilla", "\229\142\159\231\137\136", getText("UI_SQSearch_Vanilla")},
        unknownNames = {"unknown", "\230\156\170\231\159\165", getText("UI_SQSearch_Unknown")},
        scanTextMatcher = state.matchText,
    }
    local virtualSources = {}
    for index = sources.physicalCount + 1, #sources do virtualSources[sources[index]] = true end
    return {
        page = page, sources = sources, pinyin = pinyin, options = options,
        snapshots = {}, sourceIndex = 1, matches = {}, counts = {}, seenItems = {}, total = 0,
        virtualSources = virtualSources,
    }
end

local function advanceScan(scan, state, work)
    while scan.sourceIndex <= #scan.sources and work.steps > 0 and now() < work.deadline do
        work.steps = work.steps - 1
        local container = scan.sources[scan.sourceIndex]
        if not scan.items then
            -- Copy references in Java. The live list can change while the scan yields.
            local snapshot = ArrayList.new()
            snapshot:addAll(container:getItems())
            scan.items, scan.itemIndex, scan.itemCount = snapshot, 0, snapshot:size()
            scan.snapshots[scan.sourceIndex] = snapshot
            scan.counts[container] = 0
            scan.virtualSeen = scan.sourceIndex > scan.sources.physicalCount and {} or nil
        elseif scan.itemIndex >= scan.itemCount then
            scan.sourceIndex = scan.sourceIndex + 1
            scan.items = nil
        else
            local item = scan.items:get(scan.itemIndex)
            scan.itemIndex = scan.itemIndex + 1
            if scan.virtualSeen then
                -- Virtual tabs only project already-counted physical instances.
                if scan.matches[item] and not scan.virtualSeen[item] then
                    scan.virtualSeen[item] = true
                    scan.counts[container] = scan.counts[container] + 1
                end
            elseif not scan.seenItems[item] then
                scan.seenItems[item] = true
                if not item:isHidden() and Core.matches(item, state.compiled, scan.options)
                    and categoryMatches(item, state.category, scan.options.scanTextMatcher) then
                    scan.matches[item] = true
                    scan.total = scan.total + 1
                    scan.counts[container] = scan.counts[container] + 1
                    if not state.matches[item] then scan.changed = true end
                end
            end
        end
    end
    return scan.sourceIndex > #scan.sources
end

local function sameContents(scan)
    for index, snapshot in ipairs(scan.snapshots) do
        -- Native comparison also catches same-size replacement and reorder.
        if not snapshot:equals(scan.sources[index]:getItems()) then return false end
    end
    return true
end

local function retryScan(state)
    if state.preview then invalidateResults(state) end
    state.scan, state.dueAt = nil, now()
end

function SQ.refreshPage(page, work)
    if not page.inventoryPane then return end
    local state = SQ.getState(page.player, page.onCharacter and "inventory" or "nearby")
    if not active(state) then return end
    work = work or {steps = SLICE_MAX_STEPS, deadline = now() + SLICE_BUDGET_MS}
    if not state.scan or state.scan.page ~= page then
        local sources = getSources(page)
        if state.page ~= page or not sameSources(state.sources, sources) then
            invalidateResults(state)
        end
        state.page, state.dueAt = page, nil
        state.scan = newScan(page, sources, state)
    end
    local scan = state.scan
    if scan.checkContents then
        scan.checkContents = nil
        if scan.pinyin ~= (SQ.getOptions().pinyin == true) or not sameContents(scan) then
            retryScan(state)
            return
        end
    end
    if not advanceScan(scan, state, work) then
        -- Keep the provisional matches separate from the last complete result.
        -- A periodic refresh can continue to display that complete result.
        if not state.ready and scan.total > 0 then state.preview = scan end
        return
    end
    state.scan = nil
    if not sameSources(scan.sources, getSources(page))
        or scan.pinyin ~= (SQ.getOptions().pinyin == true) then
        invalidateResults(state)
        state.dueAt = now()
        return
    end
    if not sameContents(scan) then
        retryScan(state)
        return
    end
    -- Finishing a preview keeps the same ordering session, including a stack
    -- toggle in flight. Ordering flushes the final batch when preview ends.
    if not state.preview and (scan.changed or state.total ~= scan.total or not state.ready) then
        state.revision = state.revision + 1
    end
    state.matches, state.counts, state.total = scan.matches, scan.counts, scan.total
    state.sources = scan.sources
    state.preview = nil
    state.ready = true
    state.auditAt = now() + AUDIT_INTERVAL_MS
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
    local results = state.preview or state
    if (not state.ready and not state.preview) or results.total == 0 then return end
    local header, rowHeight = pane.headerHgt, pane.itemHgt
    if rowHeight <= 0 then return end
    local scrollWidth = 0
    if pane.vscroll and pane.isVScrollBarVisible and pane:isVScrollBarVisible() then
        scrollWidth = pane.vscroll:getWidth()
    end
    local width, height = math.max(0, pane:getWidth() - 2 - scrollWidth), pane:getHeight()
    local scroll = pane:getYScroll()
    local first = math.max(1, math.floor(-scroll / rowHeight) + 1)
    local last = math.min(#pane.items, math.ceil((height - header - scroll) / rowHeight))
    if first > last then return end
    local showCounts = SQ.getOptions().showCounts
    local nativeHighlight = false
    -- The viewport may start on a child of a header just above it.
    local firstRow = pane.items[first]
    if type(firstRow) ~= "table" or (not firstRow.items and firstRow.type ~= "separator") then
        for index = first - 1, 1, -1 do
            local row = pane.items[index]
            if type(row) == "table" and (row.items or row.type == "separator") then
                nativeHighlight = row.type ~= "separator" and row.matchesSearch == true
                break
            end
        end
    end
    for index = first, last do
        local row = pane.items[index]
        -- CleanUI applies the group's native search flag to every expanded
        -- child. Its row map holds the actual child item, not that flag.
        if type(row) == "table" then
            if row.type == "separator" then nativeHighlight = false
            elseif row.items then nativeHighlight = row.matchesSearch == true end
        end
        local y = (index - 1) * rowHeight + header + scroll
        if y + rowHeight > header and y < height then
            local count, total = SQ.rowCount(row, results)
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
                if showCounts and count < total and top == y and bottom == y + rowHeight then
                    local label = tostring(count) .. "/" .. tostring(total)
                    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, label) + 6
                    pane:drawRectStatic(width - labelWidth, y + 1, labelWidth, rowHeight - 2, 0.9, 0.12, 0.08, 0.18)
                    pane:drawTextRight(label, width - 3, y + 1 - scroll, 0.92, 0.8, 1, 1, UIFont.Small)
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
        local count = (state.preview or state).counts[self.inventory] or 0
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
    local state = SQ.getState(page.player, page.onCharacter and "inventory" or "nearby")
    if state.page == page and (state.scan or state.ready) then
        local sources = getSources(page)
        if state.scan and not sameSources(state.scan.sources, sources) then
            state.scan = nil
            if state.preview then invalidateResults(state) end
        end
        if state.ready and not sameSources(state.sources, sources) then invalidateResults(state) end
    end
    markStateDirty(state, now() + REFRESH_DELAY_MS)
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
    local ready
    for page in pairs(SQ.pages) do
        local current = page.onCharacter and getPlayerInventory(page.player) or getPlayerLoot(page.player)
        local state = SQ.getState(page.player, page.onCharacter and "inventory" or "nearby")
        if current ~= page then SQ.pages[page] = nil end
        if current ~= page or not page:isReallyVisible() then
            if state.page == page then
                invalidateResults(state)
                state.scan, state.auditAt, state.page, state.matchText = nil, nil, nil, nil
            end
        elseif active(state) and (state.scan or timestamp >= (state.dueAt or state.auditAt or 0)) then
            ready = ready or {}
            ready[#ready + 1] = page
        end
    end
    if not ready then return end

    local work = {steps = SLICE_MAX_STEPS, deadline = timestamp + SLICE_BUDGET_MS}
    local first = (nextPage - 1) % #ready + 1
    for offset = 0, #ready - 1 do
        if work.steps == 0 or now() >= work.deadline then break end
        local index = (first + offset - 1) % #ready + 1
        SQ.refreshPage(ready[index], work)
        nextPage = index + 1
    end
end

local function start()
    SQ.states = {}
    SQ.pages = setmetatable({}, {__mode = "k"})
    nextPage = 1
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
