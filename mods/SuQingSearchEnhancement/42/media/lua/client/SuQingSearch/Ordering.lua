-- Final presentation ordering only. Item groups, transfer payloads and the
-- user's native sort remain intact; matches are a stable partition over them.
SuQingSearch = SuQingSearch or {}
local SQ = SuQingSearch
local M = {}
SQ.Ordering = M
local panes = setmetatable({}, { __mode = "k" })

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
    if pane.dragging ~= nil or pane.dragStarted or pane.draggingMarquis then return true end
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

local function reviewedSelectionBridge(pane)
    local bridge = SuQingUIInteractionFixes and SuQingUIInteractionFixes.proximitySelection
    return bridge and bridge.version == "1.0.1" and bridge.installed == true and bridge.enabled == true
        and not pane.doController and pane.inventory and pane.inventory.getType
        and pane.inventory:getType() == "proxInv"
end

local function partition(pane, state)
    local list = pane.itemslist
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
    if active and record and not record.invalid and record.active
        and record.revision == state.revision and record.inventory == pane.inventory
        and record.list == pane.itemslist and record.generation == pane.refreshContainerCount
        and record.sort == pane.itemSortFunc and not dirty(pane) then
        return original(pane, doDragged, ...)
    end

    record = record or {}
    panes[pane] = record
    local newQuery = active and (not record.active or record.query ~= (state.query or "")
        or record.category ~= (state.category or ""))
    record.invalid = true
    local saved = snapshot(pane, selected)
    local useBridge = reviewedSelectionBridge(pane)
    record.busy = true
    local ok, reason = pcall(finalise, pane)
    if not ok then
        record.busy = false
        if pane.inventory == saved.inventory and pane.selected == selected then restore(pane, selected, saved, false) end
        error(reason, 0)
    end
    if pane.inventory ~= saved.inventory then
        panes[pane] = nil
        return original(pane, doDragged, ...)
    end

    local changed = false
    if active then
        ok, changed = pcall(partition, pane, state)
        if not ok then
            record.busy = false
            if pane.selected == selected then restore(pane, selected, saved, false) end
            error(changed, 0)
        end
    end
    local list, generation, sort = pane.itemslist, pane.refreshContainerCount, pane.itemSortFunc
    -- If drawing fails after the list changed, a later clear must still restore
    -- native order rather than treating this pane as never having been sorted.
    if active and changed then record.ordered = true end
    if newQuery and pane.setYScroll then pane:setYScroll(0) end

    local shadow
    if not useBridge and pane.selected == selected then
        table.wipe(selected)
        shadow = {
            __index = function(_, row) return selectedValue(saved, pane.items and pane.items[row]) end,
            __newindex = function(t, key, value)
                if type(key) ~= "number" then rawset(t, key, value) end
            end,
        }
        setmetatable(selected, shadow)
    end
    local a, b, c, d
    ok, a, b, c, d = pcall(original, pane, doDragged, ...)
    if shadow and getmetatable(selected) == shadow then setmetatable(selected, nil) end
    record.busy = false
    if not useBridge and pane.inventory == saved.inventory and pane.selected == selected then
        restore(pane, selected, saved, ok)
    end
    if not ok then error(a, 0) end

    record.active, record.ordered, record.invalid = active, active and changed, false
    record.revision = state and state.revision
    record.query, record.category = state and state.query or "", state and state.category or ""
    record.inventory, record.list, record.generation, record.sort = pane.inventory, list, generation, sort
    return a, b, c, d
end

return M
