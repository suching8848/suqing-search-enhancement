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

local function captureAnchors(pane, saved)
    local rows = pane.items
    saved.anchor, saved.anchorGroup = identity(rows and rows[pane.firstSelect])
    if rows and type(pane.joyselection) == "number" then
        saved.joyAnchor, saved.joyGroup = identity(rows[pane.joyselection + 1])
    end
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
    captureAnchors(pane, saved)
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

local function interacting(pane, stackToggle)
    -- CleanUI retains dragStarted after releasing the item and only clears it
    -- on the next item click. Current drag state, not that historical flag,
    -- controls deferral so searching immediately after a transfer can sort.
    if pane.dragging ~= nil or pane.draggingMarquis then return true end
    if ISMouseDrag and ISMouseDrag.dragging ~= nil then return true end
    if isMouseButtonDown then
        for button = stackToggle and 1 or 0, 2 do if isMouseButtonDown(button) then return true end end
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

local function rememberNative(pane, record, rebuilt, refresh)
    record.native = nil
    local integration = SQ.Integration
    if not rebuilt or not integration or not integration.reviewedNativeSearch or not reviewedCleanUI()
        or not integration.reviewedNativeSearch(pane, refresh) then return end
    local rows = {}
    for _, list in ipairs(presentationViews(pane)) do
        local copy = {}
        for index, row in ipairs(list) do copy[index] = row end
        rows[list] = copy
    end
    record.native = {
        rows = rows, search = pane.searchContainer, refresh = refresh,
        text = pane.searchText, category = pane.searchCategoryText, mode = pane.searchMode,
    }
end

local function reuseNative(pane, record)
    local native = record.native
    return native and native.search == pane.searchContainer and native.refresh == pane.refreshContainer
        and native.text == pane.searchText and native.category == pane.searchCategoryText
        and native.mode == pane.searchMode
end

local stackInputSources = {
    { "CleanUI", "2.10.4", "isui/isinventorypane.lua" },
    { "SuQingUIInteractionFixes", "1.0.1", "suqing_proximityselectionfix.lua" },
    { "Codex_InventoryTransferPerformance_4221", "1.2.2", "codex_inventorytransferperformance.lua" },
}
local observedInputs = {}

local function normalizedPath(path)
    if type(path) == "string" then return path:gsub("\\", "/"):gsub("^@", ""):lower() end
end

local function reviewedStackInput(fn)
    if type(fn) ~= "function" or not getFilenameOfClosure or not getModInfoByID then return false end
    local ok, reviewed = pcall(function()
        local source = normalizedPath(getFilenameOfClosure(fn))
        if not source then return false end
        for _, entry in ipairs(stackInputSources) do
            local id, version, file = entry[1], entry[2], entry[3]
            local info = getModInfoByID(id) or getModInfoByID("\\" .. id)
            if info and tostring(info:getModVersion()) == version then
                local directory = normalizedPath(info:getVersionDir())
                if directory and source == directory .. "/media/lua/client/" .. file then return true end
            end
        end
        return false
    end)
    return ok and reviewed
end

local function observeStackInput(name)
    local class = ISInventoryPane
    local original = class and class[name]
    if original == observedInputs[name] then return end
    observedInputs[name] = original
    if not reviewedStackInput(original) then return end
    local wrapper
    wrapper = function(pane, x, ...)
        local record = panes[pane]
        if not record then return original(pane, x, ...) end
        local previous = record.stackToggle
        record.stackToggle = nil
        local inventory, list, generation = pane.inventory, pane.itemslist, pane.refreshContainerCount
        local group = pane.items and pane.items[pane.mouseOverOption]
        local sameView = (record.list == list and record.generation == generation)
            or (previous and previous.list == list and previous.generation == generation)
        if class[name] ~= wrapper or pane[name] ~= wrapper or not record.active or not record.ordered
            or record.invalid or record.busy or record.inventory ~= inventory or record.sort ~= pane.itemSortFunc or not sameView
            or not reuseNative(pane, record) or dirty(pane) or interacting(pane, true)
            or type(generation) ~= "number" or type(x) ~= "number" or type(pane.column2) ~= "number"
            or x >= pane.column2 or type(group) ~= "table" or group.type == "separator"
            or not group.items or not group.name or not pane.collapsed then
            return original(pane, x, ...)
        end
        local collapsed = pane.collapsed[group.name]
        local toggle = previous or {}
        -- Refresh can rewrite the anchor index for native order before the
        -- renderer rebuilds its displayed row map.
        if not previous then captureAnchors(pane, toggle) end
        local a, b, c, d = original(pane, x, ...)
        local nextGeneration = generation == 10000 and 0 or generation + 1
        if pane.inventory == inventory and pane.itemslist ~= list and pane.refreshContainerCount == nextGeneration
            and pane.collapsed[group.name] == not collapsed and not dirty(pane) and not interacting(pane, true) then
            -- The input handled a stack header and already rebuilt the view.
            -- The next normal draw can finish ordering without another rebuild.
            toggle.list, toggle.generation = pane.itemslist, nextGeneration
            record.stackToggle = toggle
        end
        return a, b, c, d
    end
    observedInputs[name] = wrapper
    class[name] = wrapper
end

local function reviewedSelectionBridge(pane)
    local bridge = SuQingUIInteractionFixes and SuQingUIInteractionFixes.proximitySelection
    return bridge and bridge.version == "1.0.1" and bridge.installed == true and bridge.enabled == true
        and not pane.doController and pane.inventory and pane.inventory.getType
        and pane.inventory:getType() == "proxInv"
end

local function partition(list, state, nativeRows)
    if type(list) ~= "table" then return false end
    local ordered, hits, misses = {}, {}, {}
    local removeKnownSeparator = reviewedCleanUI()
    local function appendSegment()
        for _, row in ipairs(hits) do ordered[#ordered + 1] = row end
        for _, row in ipairs(misses) do ordered[#ordered + 1] = row end
        hits, misses = {}, {}
    end
    for _, row in ipairs(nativeRows or list) do
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

local function partitionViews(pane, state, native)
    local changed = false
    for _, list in ipairs(presentationViews(pane)) do
        if partition(list, state, native and native.rows[list]) then changed = true end
    end
    return changed
end

local function restoreNativeViews(native)
    for list, rows in pairs(native.rows) do
        for index = 1, math.max(#list, #rows) do list[index] = rows[index] end
    end
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
    if record and record.busy then return original(pane, doDragged, ...) end
    local pending = record and record.stackToggle
    if pending then
        record.stackToggle = nil
    elseif interacting(pane) then
        return original(pane, doDragged, ...)
    end
    local selected = pane.selected or {}
    if getmetatable(selected) ~= nil then return original(pane, doDragged, ...) end

    local compiled = state and state.compiled
    local enabled = not SQ.getOptions or SQ.getOptions().sortMatches ~= false
    local active = enabled and state and state.ready == true and compiled
        and compiled.active == true and not compiled.errorKey
    local stackToggle = active and pending and record.active and not record.invalid
        and record.revision == state.revision and record.inventory == pane.inventory
        and record.sort == pane.itemSortFunc
        and record.query == (state.query or "") and record.category == (state.category or "")
        and pending.list == pane.itemslist and pending.generation == pane.refreshContainerCount
        and reuseNative(pane, record) and not dirty(pane)
    if pending and interacting(pane, stackToggle) then return original(pane, doDragged, ...) end
    local restoreNative = record and record.ordered and not active
    if not active and not restoreNative then
        if record then record.active = false end
        return original(pane, doDragged, ...)
    end
    local sameView = record and not record.invalid and record.inventory == pane.inventory
        and record.list == pane.itemslist and record.generation == pane.refreshContainerCount
        and record.sort == pane.itemSortFunc and not dirty(pane) and samePresentation(pane, record)
    local cached = active and sameView and record.active and record.revision == state.revision
    local reuse = not cached and sameView and reuseNative(pane, record)

    record = record or {}
    panes[pane] = record
    local newQuery = active and (not record.active or record.query ~= (state.query or "")
        or record.category ~= (state.category or ""))
    record.invalid = true
    local inventory = pane.inventory
    local saved = not cached and snapshot(pane, selected) or nil
    if stackToggle then
        saved.anchor, saved.anchorGroup = pending.anchor, pending.anchorGroup
        saved.joyAnchor, saved.joyGroup = pending.joyAnchor, pending.joyGroup
    end
    -- The Proximity bridge remaps after a native refresh generation changes.
    -- Reused rows and stack clicks need our own semantic anchor for the draw.
    local useBridge = not reuse and not stackToggle and reviewedSelectionBridge(pane)
    record.busy = true
    local ok, reason = true, nil
    if not cached and not reuse then
        local generation = pane.refreshContainerCount
        ok, reason = pcall(stackToggle and settleRefreshedViews or finalise, pane)
        if not ok then
            record.busy = false
            if pane.inventory == inventory and pane.selected == selected then restore(pane, selected, saved, false) end
            error(reason, 0)
        end
        rememberNative(pane, record, stackToggle or pane.refreshContainerCount ~= generation, pane.refreshContainer)
    end
    if pane.inventory ~= inventory then
        panes[pane] = nil
        return original(pane, doDragged, ...)
    end

    local changed = false
    if active and not cached then
        ok, changed = pcall(partitionViews, pane, state, reuse and record.native)
        if not ok then
            record.busy = false
            if pane.selected == selected then restore(pane, selected, saved, false) end
            error(changed, 0)
        end
    elseif restoreNative and reuse then
        restoreNativeViews(record.native)
    end
    if not cached and record.native then rememberPresentation(pane, record) end
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
            local generation = pane.refreshContainerCount
            local r1, r2, r3, r4 = nativeRefresh(self, ...)
            if self == pane and pane.inventory == inventory then
                refreshed = true
                settleRefreshedViews(pane)
                -- Capture only the last completed native rebuild, before
                -- enhanced rows change their order again.
                rememberNative(pane, record, pane.refreshContainerCount ~= generation, nativeRefresh)
                if partitionViews(pane, state) then
                    changed, record.ordered = true, true
                end
                if record.native then rememberPresentation(pane, record) end
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
    if not cached or refreshed then
        -- A renderer may replace or reorder a view after we sorted it.
        -- In that case the captured native order must not be reused.
        if record.native and not samePresentation(pane, record) then record.native = nil end
        if not record.native then rememberPresentation(pane, record) end
    end
    if active and not cached and record.native then
        observeStackInput("onMouseDown")
        observeStackInput("onMouseDoubleClick")
    end
    return a, b, c, d
end

return M
