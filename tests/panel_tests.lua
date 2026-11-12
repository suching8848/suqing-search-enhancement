-- Load runtime_bootstrap, panel_bootstrap, native ModOptions, Core, Settings,
-- Runtime and Panel before this file. All UI objects below are deterministic mocks.
local M, SQ = SQSearchMock, SuQingSearch
local cases, assertions = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case() cases = cases + 1 end
local syncCalls, integrationApplies, dirtyCalls = {}, 0, 0
SQ.Integration = {
    syncPanel = function(player, scope, text, category)
        syncCalls[#syncCalls + 1] = { player = player, scope = scope, text = text, category = category }
    end,
    refreshOptions = function() integrationApplies = integrationApplies + 1 end,
}
local oldDirty = SQ.markDirty
SQ.markDirty = function() dirtyCalls = dirtyCalls + 1; oldDirty() end

case()
local settings = assert(PZAPI.ModOptions:getOptions("SuQingSearchEnhancement"))
equal(settings, SQ.settings, "native settings page shared with SQ")
equal(#PZAPI.ModOptions.Data, 1, "one native settings registration")
local expectedDefaults = { integrate = true, clickPopup = false, openKey = Keyboard.KEY_F8, showCounts = true, showHelp = false, pinyin = true, sortMatches = true, showContextMenu = false }
for key, expected in pairs(expectedDefaults) do equal(SQ.getOptions()[key], expected, "native default " .. key) end
settings:getOption("integrate"):setValue(false)
settings:getOption("openKey"):setValue(0)
settings:apply()
equal(SQ.getOptions().integrate, false, "native integrate option updates")
equal(SQ.getOptions().openKey, 0, "native keybind can be disabled")
equal(integrationApplies, 1, "apply refreshes integration")
equal(dirtyCalls, 1, "apply requests result refresh")
settings:getOption("integrate"):setValue(true)
settings:getOption("openKey"):setValue(Keyboard.KEY_F8)

case()
SQ.open(0)
local panel = assert(SQ.panels[0], "first open must create panel")
equal(#M.uiPanels, 1, "first open attaches one panel")
equal(panel.entry ~= nil, true, "addToUIManager instantiates child entry before focus")
equal(panel.visible, true, "first open visible")
equal(panel.wantKeyEvents, true, "panel opts into native Java key-event delivery")
equal(M.focused, panel.entry, "first open focuses entry")
equal(panel.scope, "inventory", "first open inventory scope")
equal(panel.entry:getInternalText(), "", "first open empty query")
equal(panel.entry.placeholder, "UI_SQSearch_Placeholder", "entry uses translated placeholder")
equal(panel.help.visible, false, "default help collapsed")
equal(panel.height, panel.baseHeight, "collapsed panel compact height")
equal(panel.width <= M.screenWidth - 20, true, "window width bounded to screen")
local originalPanel, originalEntry = panel, panel.entry
panel.entry:setText("@ModernFirearmsSystem m110")
equal(SQ.getState(0, "inventory").query, "@ModernFirearmsSystem m110", "text change submits query")
equal(SQ.getState(0, "inventory").source, "panel", "panel owns submitted query")
equal(syncCalls[#syncCalls].text, "@ModernFirearmsSystem m110", "text change synchronizes integrated search")
panel:close()
equal(panel.visible, false, "close hides panel")
equal(M.focused, nil, "close releases text focus")
SQ.open(0)
equal(SQ.panels[0], originalPanel, "reopen reuses panel instance")
equal(panel.entry, originalEntry, "reopen reuses text entry")
equal(#M.uiPanels, 1, "reopen does not add duplicate UI")
equal(panel.entry:getInternalText(), "@ModernFirearmsSystem m110", "reopen restores active query")
equal(M.focused, panel.entry, "reopen restores focus")

case()
local priorSync = #syncCalls
panel.inventoryButton:click()
equal(panel.scope, "inventory", "same scope stays inventory")
equal(SQ.getState(0, "inventory").query, "@ModernFirearmsSystem m110", "same scope preserves input")
panel.nearbyButton:click()
equal(panel.scope, "nearby", "real nearby button selects scope")
equal(SQ.getState(0, "inventory").query, "", "previous panel-owned scope cleared")
equal(SQ.getState(0, "nearby").query, "@ModernFirearmsSystem m110", "new scope receives expression")
equal(M.focused, panel.entry, "scope button returns text focus")
local oldScopeCleared = false
for index = priorSync + 1, #syncCalls do
    local call = syncCalls[index]
    if call.scope == "inventory" and call.text == "" then oldScopeCleared = true end
end
equal(oldScopeCleared, true, "scope transition clears previous integrated search")

case()
panel.category = "Weapon"
panel.entry:setText("m110")
equal(SQ.getState(0, "nearby").category, "Weapon", "submit retains copied category context")
panel.clearButton:click()
equal(panel.entry:getInternalText(), "", "real clear button empties entry")
equal(SQ.getState(0, "nearby").query, "", "clear removes active runtime query")
equal(SQ.getState(0, "nearby").source, nil, "clear removes query owner")
equal(SQ.getState(0, "nearby").total, 0, "clear removes result count")
equal(syncCalls[#syncCalls].text, "", "clear synchronizes empty integrated query")
equal(M.focused, panel.entry, "clear retains focus")
panel.inventoryButton:click()
equal(panel.category, "", "scope change clears copied category filter")

case()
panel.helpButton:click()
equal(panel.showHelp, true, "real help button expands help")
equal(panel.help.visible, true, "help visible")
equal(panel.height > panel.baseHeight, true, "help expands window height")
panel.y = M.screenHeight - 1
panel:layoutHelp()
equal(panel.y + panel.height <= M.screenHeight, true, "help clamps window inside screen")
panel.helpButton:click()
equal(panel.showHelp, false, "second help click collapses")
equal(panel.height, panel.baseHeight, "help collapse restores compact height")

case()
panel.entry:setText("m110")
local tokenLabels = { "UI_SQSearch_Mod", "UI_SQSearch_ID", "UI_SQSearch_Exclude", "UI_SQSearch_Or" }
local tokenValues = { "@", "&", "-", "| " }
for index, label in ipairs(tokenLabels) do
    panel.entry:setText("m110")
    local found
    for _, child in ipairs(panel.children) do if child.title == label then found = child end end
    assert(found, "token button missing: " .. label)
    found:click()
    equal(panel.entry:getInternalText(), "m110 " .. tokenValues[index], "real token button inserts literal operator " .. label)
    equal(M.focused, panel.entry, "token returns focus " .. label)
    equal(type(SQ.getState(0, panel.scope).compiled.errorKey), "string", "half entered operator yields validation state " .. label)
end
panel.entry:setText("m110 ")
panel:insertToken("@")
equal(panel.entry:getInternalText(), "m110 @", "token does not duplicate whitespace")

case()
panel.entry:setText('"unfinished')
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_ErrorUnclosedQuote", "render reports syntax-error translation key")
panel:clear()
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_Empty", "render reports empty state")
local inventoryItems = {}
for index = 1, 120 do
    inventoryItems[index] = index <= 7 and M.item("Rifle", "Base.Rifle") or M.item("Rag", "Base.Rag")
end
local inventoryPage = M.page(true, {M.container("bag", inventoryItems, true)})
M.inventories[0] = inventoryPage
SQ.registerPage(inventoryPage)
panel.entry:setText("rifle")
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_Searching", "render reports searching before the first slice")
M.advance(120)
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_Searching", "render reports searching while scan is incomplete")
M.advance(16)
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_Count:7", "render reports numeric result count")
panel.entry:setText("no-match")
M.advance(120)
M.advance(16)
panel:render()
equal(panel.calls[#panel.calls].text, "UI_SQSearch_Count:0", "render reports zero matches once scan completes")
M.inventories[0] = nil
equal(panel.inventoryButton.borderColor.a, 1, "active scope visual")
equal(panel.nearbyButton.borderColor.a, 0.3, "inactive scope visual")
equal(panel:isKeyConsumed(Keyboard.KEY_ESCAPE), true, "escape consumed by panel")
equal(panel:isKeyConsumed(Keyboard.KEY_A), false, "other keys not consumed globally")
M.releaseKey(panel, Keyboard.KEY_A)
equal(panel.visible, true, "unrelated key release leaves panel open")
M.releaseKey(panel, Keyboard.KEY_ESCAPE)
equal(panel.visible, false, "escape hides panel")
equal(M.focused, nil, "escape releases typing focus")

case()
local beforeTop = panel.topCalls
M.externalTextEntry = true
M.emit("OnKeyPressed", Keyboard.KEY_F8)
equal(panel.topCalls, beforeTop, "F8 ignored while external text entry or IME active")
M.externalTextEntry = false
M.emit("OnKeyPressed", Keyboard.KEY_A)
equal(panel.topCalls, beforeTop, "unbound key ignored")
settings:getOption("openKey"):setValue(0)
M.emit("OnKeyPressed", 0)
M.emit("OnKeyPressed", Keyboard.KEY_F8)
equal(panel.topCalls, beforeTop, "disabled hotkey never opens panel")
settings:getOption("openKey"):setValue(Keyboard.KEY_F8)
M.emit("OnKeyPressed", Keyboard.KEY_F8)
equal(panel.visible, true, "configured F8 opens panel")
equal(panel.topCalls, beforeTop + 1, "hotkey brings existing panel to front once")
M.emit("OnKeyPressed", Keyboard.KEY_F8)
equal(panel.topCalls, beforeTop + 1, "F8 ignored while search entry owns typing focus")
panel.entry:onCommandEntered()
equal(M.focused, nil, "enter releases search typing focus")

case()
panel:close()
local context = M.context()
M.emit("OnFillInventoryObjectContextMenu", 0, context)
equal(#context.options, 0, "inventory context entry hidden by default")
settings:getOption("showContextMenu"):setValue(true)
settings:apply()
M.emit("OnFillInventoryObjectContextMenu", 0, context)
equal(#context.options, 1, "one inventory context entry registered")
equal(context.options[1].label, "UI_SQSearch_Open", "context option translated label")
context.options[1]:activate()
equal(panel.visible, true, "actual context callback opens panel")
equal(M.focused, panel.entry, "context callback focuses entry")
equal(#M.uiPanels, 1, "context callback reuses existing UI")
settings:getOption("showContextMenu"):setValue(false)
settings:apply()
context = M.context()
M.emit("OnFillInventoryObjectContextMenu", 0, context)
equal(#context.options, 0, "inventory context entry can be hidden again without duplicate registration")

case()
panel:close()
SQ.setQuery(0, "nails", "nearby", "Item", "cleanui")
SQ.open(0, "nearby")
equal(panel.scope, "nearby", "explicit open selects requested scope")
equal(panel.entry:getInternalText(), "nails", "explicit scope open loads state query")
equal(panel.category, "Item", "explicit scope open loads category")
SQ.open(0, "nearby", "&Base.Nails")
equal(panel.entry:getInternalText(), "&Base.Nails", "explicit text override populates entry")
equal(SQ.getState(0, "nearby").query, "&Base.Nails", "explicit text override submits runtime expression")
local panelCount = #M.uiPanels
SQ.open(99)
equal(SQ.panels[99], nil, "no-player context cannot construct panel")
equal(#M.uiPanels, panelCount, "invalid player adds no UI")

case()
SQ.setQuery(0, "old query", "nearby", "OldCategory", "cleanui")
SQ.open(0, "nearby", "@ModernFirearmsSystem", "Weapon")
equal(panel.category, "Weapon", "fourth open argument overrides older runtime category")
equal(SQ.getState(0, "nearby").category, "Weapon", "fourth open argument submitted to runtime")
equal(syncCalls[#syncCalls].category, "Weapon", "fourth open argument copied unchanged to integration")
SQ.open(0, "nearby", "nails", "")
equal(panel.category, "", "explicit empty fourth argument clears prior category")
equal(SQ.getState(0, "nearby").category, "", "explicit empty category not replaced with old default")

case()
SQ.setQuery(0, "m110 -hidden", "nearby", "Weapon", "cleanui")
local liveState = SQ.getState(0, "nearby")
local compiledBefore, totalBefore = liveState.compiled, 6
liveState.total = totalBefore
local syncBefore, dirtyBefore, focusBefore, topBefore = #syncCalls, dirtyCalls, panel.entry.focusCalls, panel.topCalls
SQ.panelQueryChanged(0, "nearby", "m110 -hidden", "Weapon")
equal(panel.entry:getInternalText(), "m110 -hidden", "external edit updates visible entry")
equal(panel.category, "Weapon", "external edit updates category")
equal(liveState.source, "cleanui", "external edit notification does not steal query ownership")
equal(liveState.compiled, compiledBefore, "external edit notification does not recompile query")
equal(liveState.total, totalBefore, "external edit notification does not clear valid hits")
equal(#syncCalls, syncBefore, "external edit notification does not resync integration")
equal(dirtyCalls, dirtyBefore, "external edit notification does not schedule another submit")
equal(panel.entry.focusCalls, focusBefore, "external edit notification does not steal focus")
equal(panel.topCalls, topBefore, "external edit notification does not raise panel")
SQ.panelQueryChanged(0, "inventory", "wrong scope", "Food")
equal(panel.entry:getInternalText(), "m110 -hidden", "other-scope notification ignored")
equal(panel.category, "Weapon", "other-scope notification leaves category alone")
SQ.panelQueryChanged(99, "nearby", "wrong player", "Food")
equal(panel.entry:getInternalText(), "m110 -hidden", "missing player panel notification ignored")
SQ.panelQueryChanged(0, "nearby", nil, nil)
equal(panel.entry:getInternalText(), "", "empty notification clears entry")
equal(panel.category, "", "empty notification clears category")
equal(liveState.source, "cleanui", "empty notification does not mutate runtime source")
equal(liveState.query, "m110 -hidden", "notification updates UI only")

case()
-- The original field became authoritative after the panel was opened. Switching
-- scope must clear that former scope too, otherwise stale container badges remain.
SQ.setQuery(0, "@ModernFirearmsSystem m110", "nearby", "Weapon", "cleanui")
SQ.panelQueryChanged(0, "nearby", "@ModernFirearmsSystem m110", "Weapon")
liveState = SQ.getState(0, "nearby")
liveState.total = 3
liveState.matches = { staleInstance = true }
liveState.counts = { staleContainer = 3 }
syncBefore = #syncCalls
panel.inventoryButton:click()
equal(liveState.query, "", "scope switch clears previous cleanui-owned query")
equal(liveState.source, nil, "scope switch removes previous cleanui ownership")
equal(liveState.total, 0, "scope switch removes previous result total")
local staleMatches, staleCounts = false, false
for _ in pairs(liveState.matches) do staleMatches = true end
for _ in pairs(liveState.counts) do staleCounts = true end
equal(staleMatches, false, "scope switch removes previous row highlights")
equal(staleCounts, false, "scope switch removes previous container badges")
equal(panel.scope, "inventory", "scope switch selects requested target")
equal(SQ.getState(0, "inventory").source, "panel", "new scope becomes panel-owned")
equal(SQ.getState(0, "inventory").query, "@ModernFirearmsSystem m110", "new scope keeps latest external expression")
equal(SQ.getState(0, "inventory").category, "", "new scope clears previous category restriction")
local clearedOldIntegration = false
for index = syncBefore + 1, #syncCalls do
    local call = syncCalls[index]
    if call.scope == "nearby" and call.text == "" then clearedOldIntegration = true end
end
equal(clearedOldIntegration, true, "scope switch clears previous original search field too")
return "SQSEARCH_PANEL cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
