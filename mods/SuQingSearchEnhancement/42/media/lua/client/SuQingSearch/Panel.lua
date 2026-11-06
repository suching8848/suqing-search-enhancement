require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISRichTextPanel"
require "SuQingSearch/Runtime"

local SQ = SuQingSearch
local Panel = ISCollapsableWindow:derive("SuQingSearchPanel")
SQ.Panel = Panel
SQ.panels = {}

local function button(panel, x, y, width, text, callback)
    local control = ISButton:new(x, y, width, panel.lineHeight, getText(text), panel, callback)
    control:initialise()
    panel:addChild(control)
    return control
end

function Panel:submit()
    if self.suppressChange then return end
    SQ.setQuery(self.playerNum, self.entry:getInternalText(), self.scope, self.category, "panel")
    if SQ.Integration then
        SQ.Integration.syncPanel(self.playerNum, self.scope, self.entry:getInternalText(), self.category)
    end
end

function Panel:chooseScope(scope)
    if self.scope ~= scope then
        SQ.clearQuery(self.playerNum, self.scope)
        if SQ.Integration then SQ.Integration.syncPanel(self.playerNum, self.scope, "", self.category) end
        self.scope, self.category = scope, ""
    end
    self:submit()
    self.entry:focus()
end

function Panel:insertToken(token)
    local text = self.entry:getInternalText()
    if text ~= "" and text:sub(-1) ~= " " then text = text .. " " end
    self.entry:setText(text .. token)
    self:submit()
    self.entry:focus()
end

function Panel:clear()
    self.suppressChange = true
    self.entry:setText("")
    self.suppressChange = false
    SQ.clearQuery(self.playerNum, self.scope)
    if SQ.Integration then SQ.Integration.syncPanel(self.playerNum, self.scope, "", self.category) end
    self.entry:focus()
end

function Panel:toggleHelp()
    self.showHelp = not self.showHelp
    self:layoutHelp()
end

function Panel:layoutHelp()
    self.help:setVisible(self.showHelp)
    self.help:setWidth(self.width - 20)
    self.help:paginate()
    self:setHeight(self.baseHeight + (self.showHelp and self.help.height + 12 or 0))
    self:setY(math.max(0, math.min(self.y, getCore():getScreenHeight() - self.height)))
end

function Panel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y, gap = self:titleBarHeight() + 10, 8
    self.entry = ISTextEntryBox:new("", 10, y, self.width - 115, self.lineHeight)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry:setFont(UIFont.Small)
    self.entry:setPlaceholderText(getText("UI_SQSearch_Placeholder"))
    self.entry.onTextChange = function() self:submit() end
    self.entry.onCommandEntered = function() self.entry:unfocus() end
    self:addChild(self.entry)
    self.clearButton = button(self, self.width - 95, y, 85, "UI_SQSearch_Clear", Panel.clear)
    y = y + self.lineHeight + gap
    self.inventoryButton = button(self, 10, y, 105, "UI_SQSearch_Inventory", function(panel) panel:chooseScope("inventory") end)
    self.nearbyButton = button(self, 123, y, 105, "UI_SQSearch_Nearby", function(panel) panel:chooseScope("nearby") end)
    self.helpButton = button(self, self.width - 120, y, 110, "UI_SQSearch_Usage", Panel.toggleHelp)
    y = y + self.lineHeight + gap
    local tokens = {{"UI_SQSearch_Mod", "@"}, {"UI_SQSearch_ID", "&"}, {"UI_SQSearch_Exclude", "-"}, {"UI_SQSearch_Or", "| "}}
    local tokenWidth = math.floor((self.width - 44) / 4)
    for index, token in ipairs(tokens) do
        local value = token[2]
        button(self, 10 + (index - 1) * (tokenWidth + 8), y, tokenWidth, token[1], function(panel) panel:insertToken(value) end)
    end
    y = y + self.lineHeight + gap
    self.statusY = y
    self.baseHeight = y + self.lineHeight + 12
    self.help = ISRichTextPanel:new(10, self.baseHeight, self.width - 20, 10)
    self.help:initialise()
    self.help.background = false
    self.help.defaultFont = UIFont.Small
    self.help.autosetheight = true
    self.help.marginLeft, self.help.marginRight = 0, 0
    self.help:setText(getText("UI_SQSearch_Help"))
    self:addChild(self.help)
    self:layoutHelp()
end

function Panel:render()
    ISCollapsableWindow.render(self)
    local state = SQ.getState(self.playerNum, self.scope)
    local message
    if state.compiled.errorKey then
        message = getText(state.compiled.errorKey)
    elseif not state.compiled.active then
        message = getText((self.entry:getInternalText() ~= "" or self.category ~= "")
            and "UI_SQSearch_Native" or "UI_SQSearch_Empty")
    else
        message = getText("UI_SQSearch_Count", tostring(state.total))
    end
    self:drawText(message, 10, self.statusY, 0.9, 0.78, 1, 1, UIFont.Small)
    self.inventoryButton.borderColor.a = self.scope == "inventory" and 1 or 0.3
    self.nearbyButton.borderColor.a = self.scope == "nearby" and 1 or 0.3
end

function Panel:close()
    self.entry:unfocus()
    ISCollapsableWindow.close(self)
end

function Panel:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function Panel:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end

function Panel:new(playerNum)
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local width = math.min(math.max(580, fontHeight * 34), getCore():getScreenWidth() - 20)
    local o = ISCollapsableWindow.new(self, (getCore():getScreenWidth() - width) / 2, 100, width, 210)
    o.playerNum = playerNum
    o.scope = "inventory"
    o.category = ""
    o.lineHeight = math.max(25, fontHeight + 8)
    o.title = getText("UI_SQSearch_Title")
    o.resizable = false
    o:setWantKeyEvents(true)
    o.showHelp = SQ.getOptions().showHelp
    o.backgroundColor = {r = 0.07, g = 0.05, b = 0.1, a = 0.96}
    o.borderColor = {r = 0.7, g = 0.55, b = 0.85, a = 0.9}
    return o
end

-- Existing-field edits update a visible panel without re-entering either matcher.
function SQ.panelQueryChanged(playerNum, scope, text, category)
    local panel = SQ.panels[playerNum]
    if not panel or panel.scope ~= scope then return end
    panel.suppressChange = true
    panel.entry:setText(text or "")
    panel.suppressChange = false
    panel.category = category or ""
end

function SQ.open(playerNum, scope, text, category)
    if not getSpecificPlayer(playerNum) then return end
    local panel = SQ.panels[playerNum]
    if not panel then
        panel = Panel:new(playerNum)
        panel:initialise()
        panel:addToUIManager()
        SQ.panels[playerNum] = panel
    end
    panel.scope = scope or panel.scope
    local state = SQ.getState(playerNum, panel.scope)
    panel.category = category == nil and (state.category or "") or category
    panel.suppressChange = true
    panel.entry:setText(text == nil and state.query or text)
    panel.suppressChange = false
    panel:setVisible(true)
    panel:bringToTop()
    panel.entry:focus()
    panel:submit()
    SQ.markDirty()
end

Events.OnKeyPressed.Add(function(key)
    if key == SQ.getOptions().openKey and key ~= 0 and getSpecificPlayer(0) then
        -- Core's native text-entry state also covers chat and IME composition.
        if getCore():isDoingTextEntry() then return end
        SQ.open(0)
    end
end)

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context)
    if SQ.getOptions().showContextMenu ~= true then return end
    context:addOption(getText("UI_SQSearch_Open"), playerNum, function(player) SQ.open(player) end)
end)
