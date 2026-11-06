-- Final presentation ordering only. Item groups, transfer payloads and the
-- user's native sort remain intact; matches are a stable partition over them.
SuQingSearch = SuQingSearch or {}
local SQ = SuQingSearch
local M = {}
SQ.Ordering = M
local panes = setmetatable({}, { __mode = "k" })

local function ownSlot(object, name)
    -- PZO's optimized self-indexing class tables can resolve inherited methods
    -- even through rawget. Iteration distinguishes the actual instance slot.
    for key, value in pairs(object) do if key == name then return value end end
    return nil
end

local function empty(values)
    for _ in pairs(values) do return false end
    return true
end

local function identity(value)
    if value == nil then return nil end
    if instanceof and instanceof(value, "InventoryItem") then return value, false end
    if type(value) == "table" and value.type ~= "separator" and value.items
        and value.name ~= nil then return value.name, true end
    return nil
end

local function snapshot(pane, selected)
    local saved = { inventory = pane.inventory, items = {}, groups = {}, raw = {},
        first = pane.firstSelect, joyIndex = pane.joyselection }
    for key, value in pairs(selected) do
        saved.raw[key] = value
        local id, group = identity(value)
        if id ~= nil then
            if group then saved.groups[id] = true else saved.items[id] = true end
        end
    end
    local anchor = pane.items and pane.items[pane.firstSelect]
    saved.anchor, saved.anchorGroup = identity(anchor)
    if type(pane.joyselection) == "number" and pane.items then
        saved.joyAnchor, saved.joyGroup = identity(pane.items[pane.joyselection + 1])
    end
    return saved
end

local function selectedValue(saved, value)
    local id, group = identity(value)
    if id ~= nil and ((group and saved.groups[id]) or (not group and saved.items[id])) then
        return value
    end
    return nil
end

local function restore(pane, selected, saved, actualRows)
    table.wipe(selected)
    if not actualRows then
        for key, value in pairs(saved.raw) do selected[key] = value end
        pane.firstSelect = saved.first
        pane.joyselection = saved.joyIndex
        return
    end
    for key, value in pairs(saved.raw) do
        if type(key) ~= "number" then selected[key] = value end
    end
    pane.firstSelect = nil
    if saved.joyAnchor ~= nil then pane.joyselection = -1 end
    for row, value in ipairs(pane.items or {}) do
        if selectedValue(saved, value) then selected[row] = value end
        local id, group = identity(value)
        if saved.anchor ~= nil and id == saved.anchor and group == saved.anchorGroup then
            pane.firstSelect = row
        end
        if saved.joyAnchor ~= nil and id == saved.joyAnchor and group == saved.joyGroup then
            pane.joyselection = row - 1
        end
    end
end

local function interacting(pane)
    -- CleanUI retains dragStarted after releasing the item and only clears it
    -- on the next item click. Current drag state, not that historical flag,
    -- controls deferral so searching immediately after a transfer can sort.
    if pane.dragging ~= nil or pane.draggingMarquis then return true end
    if ISMouseDrag and ISMouseDrag.dragging ~= nil then return true end
    if isMouseButtonDown then
        for button = 0, 2 do if isMouseButtonDown(button) then return true end end
    end
    return false
end

local function dirty(pane)
    return pane.inventory and pane.inventory.isDrawDirty and pane.inventory:isDrawDirty() == true
end

local function finalise(pane)
    if type(pane.searchContainer) == "function" then
        pane:searchContainer(pane.searchText, pane.searchCategoryText, pane.searchMode)
    elseif type(pane.refreshContainer) == "function" then
        pane:refreshContainer()
    end
end

local function reviewedCleanUI()
    if not getModInfoByID then return false end
    local info = getModInfoByID("CleanUI") or getModInfoByID("\\CleanUI")
    return info and info.getModVersion and tostring(info:getModVersion()) == "2.10.4"
end

local function presentationViews(pane)
    local views, seen = {}, {}
    local function add(list)
        if type(list) == "table" and not seen[list] then
            seen[list] = true
            views[#views + 1] = list
        end
    end
    add(pane.itemslist)
    -- NeatUI Equipment 1.0.2 temporarily draws a separate filtered array, then
    -- puts the full array back. Ordering only itemslist therefore misses the
    -- rows the player actually sees while its hide-equipped eye is enabled.
    local info = getModInfoByID and (getModInfoByID("NeatUI_Equipment") or getModInfoByID("\\NeatUI_Equipment"))
    if info and info.getModVersion and tostring(info:getModVersion()) == "1.0.2"
        and pane.neqFilteredFor == pane.inventory then
        add(pane.neqFullItemList)
        add(pane.neqFilteredItemList)
    end
    return views
end

local function samePresentation(pane, record)
    local views = presentationViews(pane)
    if not record.views or #views ~= #record.views then return false end
    for index, list in ipairs(views) do
        local saved = record.views[index]
        if saved.list ~= list or #saved.rows ~= #list then return false end
        -- A wrapper can sort the existing table without changing its identity,
        -- refresh count or comparator. Detect that before taking the fast path.
        for row, value in ipairs(list) do
            if saved.rows[row] ~= value then return false end
        end
    end
    return true
end

local function rememberPresentation(pane, record)
    record.views = {}
    for index, list in ipairs(presentationViews(pane)) do
        local rows = {}
        for row, value in ipairs(list) do rows[row] = value end
        record.views[index] = { list = list, rows = rows }
    end
end

local function reviewedSelectionBridge(pane)
    local bridge = SuQingUIInteractionFixes and SuQingUIInteractionFixes.proximitySelection
    return bridge and bridge.version == "1.0.1" and bridge.installed == true and bridge.enabled == true
        and not pane.doController and pane.inventory and pane.inventory.getType
        and pane.inventory:getType() == "proxInv"
end

local function partition(list, state)
    if type(list) ~= "table" then return false end
    local ordered, hits, misses = {}, {}, {}
    local removeKnownSeparator = reviewedCleanUI()
    local function appendSegment()
        for _, row in ipairs(hits) do ordered[#ordered + 1] = row end
        for _, row in ipairs(misses) do ordered[#ordered + 1] = row end
        hits, misses = {}, {}
    end
    for _, row in ipairs(list) do
        if row.type == "separator" then
            local known = removeKnownSeparator and row.name == "."
                and type(row.items) == "table" and empty(row.items)
            if not known then
                appendSegment()
                ordered[#ordered + 1] = row
            end
        else
            local count = SQ.rowCount(row, state)
            local target = count > 0 and hits or misses
            target[#target + 1] = row
        end
    end
    appendSegment()
    local changed = #ordered ~= #list
    if not changed then
        for index, row in ipairs(ordered) do
            if list[index] ~= row then changed = true; break end
        end
    end
    if changed then
        for index = 1, math.max(#list, #ordered) do list[index] = ordered[index] end
    end
    return changed
end

local function partitionViews(pane, state)
    local changed = false
    for _, list in ipairs(presentationViews(pane)) do
        if partition(list, state) then changed = true end
    end
    return changed
end

local function settleRefreshedViews(pane)
    if not reviewedCleanUI() or type(pane.searchContainer) ~= "function" then return end
    -- CleanUI reconciles pinned/category priorities after refreshContainer has
    -- returned, including a refresh initiated from inside renderdetails. Reach
    -- that native finalizer with the completed refresh reused once per view,
    -- then our partition remains the last presentation change before drawing.
    local originalList = pane.itemslist
    local originalRefresh = ownSlot(pane, "refreshContainer")
    local query, category, mode = pane.searchText, pane.searchCategoryText, pane.searchMode
    local generation = pane.refreshContainerCount
    local ok, reason = pcall(function()
        for _, list in ipairs(presentationViews(pane)) do
            pane.itemslist = list
            pane._cleanUIRowPriorityRefreshCount = nil
            pane._cleanUICategoryPresentationRefreshCount = nil
            local reused = 0
            rawset(pane, "refreshContainer", function(self)
                if self ~= pane then error("unexpected search ordering refresh receiver") end
                reused = reused + 1
            end)
            finalise(pane)
            if reused ~= 1 or pane.refreshContainerCount ~= generation then
                error("unsupported CleanUI search ordering refresh contract")
            end
        end
    end)
    rawset(pane, "refreshContainer", originalRefresh)
    pane.itemslist = originalList
    pane.searchText, pane.searchCategoryText, pane.searchMode = query, category, mode
    if not ok then error(reason, 0) end
end

function M.render(pane, state, doDragged, original, ...)
    if doDragged ~= false then return original(pane, doDragged, ...) end
    local record = panes[pane]
    if (record and record.busy) or interacting(pane) then return original(pane, doDragged, ...) end
    local selected = pane.selected or {}
    if getmetatable(selected) ~= nil then return original(pane, doDragged, ...) end

    local compiled = state and state.compiled
    local enabled = not SQ.getOptions or SQ.getOptions().sortMatches ~= false
    local active = enabled and state and state.ready == true and compiled
        and compiled.active == true and not compiled.errorKey
    local restoreNative = record and record.ordered and not active
    if not active and not restoreNative then
        if record then record.active = false end
        return original(pane, doDragged, ...)
    end
    local cached = active and record and not record.invalid and record.active
        and record.revision == state.revision and record.inventory == pane.inventory
        and record.list == pane.itemslist and record.generation == pane.refreshContainerCount
        and record.sort == pane.itemSortFunc and not dirty(pane) and samePresentation(pane, record)

    record = record or {}
    panes[pane] = record
    local newQuery = active and (not record.active or record.query ~= (state.query or "")
        or record.category ~= (state.category or ""))
    record.invalid = true
    local inventory = pane.inventory
    local saved = not cached and snapshot(pane, selected) or nil
    local useBridge = reviewedSelectionBridge(pane)
    record.busy = true
    local ok, reason = true, nil
    if not cached then
        ok, reason = pcall(finalise, pane)
        if not ok then
            record.busy = false
            if pane.inventory == inventory and pane.selected == selected then restore(pane, selected, saved, false) end
            error(reason, 0)
        end
    end
    if pane.inventory ~= inventory then
        panes[pane] = nil
        return original(pane, doDragged, ...)
    end

    local changed = false
    if active and not cached then
        ok, changed = pcall(partitionViews, pane, state)
        if not ok then
            record.busy = false
            if pane.selected == selected then restore(pane, selected, saved, false) end
            error(changed, 0)
        end
    end
    -- If drawing fails after the list changed, a later clear must still restore
    -- native order rather than treating this pane as never having been sorted.
    if active and changed then record.ordered = true end
    if newQuery and pane.setYScroll then pane:setYScroll(0) end

    local shadow
    local function prepareSelection()
        if not saved then saved = snapshot(pane, selected) end
        if useBridge or shadow or pane.selected ~= selected then return end
        table.wipe(selected)
        shadow = {
            __index = function(_, row) return selectedValue(saved, pane.items and pane.items[row]) end,
            __newindex = function(t, key, value)
                if type(key) ~= "number" then rawset(t, key, value) end
            end,
        }
        setmetatable(selected, shadow)
    end
    -- An unchanged frame only monitors refreshContainer. Selection snapshots,
    -- table wipes and semantic remapping are needed only if it really rebuilds.
    if not cached then prepareSelection() end
    local a, b, c, d
    local refreshed = false
    local instanceRefresh = ownSlot(pane, "refreshContainer")
    local nativeRefresh = pane.refreshContainer
    if active and type(nativeRefresh) == "function" then
        rawset(pane, "refreshContainer", function(self, ...)
            if self == pane and pane.inventory == inventory then prepareSelection() end
            local r1, r2, r3, r4 = nativeRefresh(self, ...)
            if self == pane and pane.inventory == inventory then
                refreshed = true
                settleRefreshedViews(pane)
                if partitionViews(pane, state) then
                    changed, record.ordered = true, true
                end
            end
            return r1, r2, r3, r4
        end)
    end
    ok, a, b, c, d = pcall(original, pane, doDragged, ...)
    rawset(pane, "refreshContainer", instanceRefresh)
    if shadow and getmetatable(selected) == shadow then setmetatable(selected, nil) end
    record.busy = false
    if saved and not useBridge and pane.inventory == inventory and pane.selected == selected then
        restore(pane, selected, saved, ok)
    end
    if not ok then error(a, 0) end
    if pane.inventory ~= inventory then
        panes[pane] = nil
        return a, b, c, d
    end

    record.active, record.ordered, record.invalid = active, active and (record.ordered or changed), false
    record.revision = state and state.revision
    record.query, record.category = state and state.query or "", state and state.category or ""
    record.inventory, record.list, record.generation, record.sort = pane.inventory,
        pane.itemslist, pane.refreshContainerCount, pane.itemSortFunc
    if not cached or refreshed then rememberPresentation(pane, record) end
    return a, b, c, d
end

return M
