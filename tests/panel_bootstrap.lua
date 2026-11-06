-- Load after runtime_bootstrap.lua. Pure UI model; no Java UI or world is created.
local M = SQSearchMock
M.screenWidth, M.screenHeight, M.fontHeight = 1280, 720, 16
M.externalTextEntry, M.focused = false, nil
M.contextCalls, M.uiPanels = {}, {}
Keyboard = { KEY_F8 = 66, KEY_ESCAPE = 1, KEY_RETURN = 28, KEY_A = 30 }
function getCore()
    return {
        getScreenWidth = function() return M.screenWidth end,
        getScreenHeight = function() return M.screenHeight end,
        isDoingTextEntry = function() return M.externalTextEntry or M.focused ~= nil end,
    }
end
function getTextManager()
    return {
        getFontHeight = function() return M.fontHeight end,
        MeasureStringX = function(self, font, text) return #text * 6 end,
    }
end
local oldGetText = getText
function getText(key, arg)
    if arg then return key .. ":" .. tostring(arg) end
    return oldGetText(key)
end

local UI = {}
UI.__index = UI
function UI:derive(name)
    local class = { Type = name }
    class.__index = class
    setmetatable(class, { __index = self })
    return class
end
function UI:new(x, y, width, height)
    local object = { x = x or 0, y = y or 0, width = width or 100, height = height or 20,
        children = {}, visible = true, wantKeyEvents = false, borderColor = { a = 1 }, calls = {} }
    setmetatable(object, self)
    return object
end
function UI:initialise() self.initialised = true end
function UI:createChildren() end
function UI:instantiate()
    if self.javaObject then return end
    self.javaObject = {}
    self:createChildren()
end
function UI:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
    child:instantiate()
end
function UI:addToUIManager()
    self:instantiate()
    M.uiPanels[#M.uiPanels + 1] = self
end
function UI:setVisible(visible) self.visible = visible end
function UI:isReallyVisible() return self.visible end
function UI:setWantKeyEvents(want) self.wantKeyEvents = want end
function UI:setWidth(width) self.width = width end
function UI:setHeight(height) self.height = height end
function UI:setX(x) self.x = x end
function UI:setY(y) self.y = y end
function UI:getWidth() return self.width end
function UI:getHeight() return self.height end
function UI:bringToTop() self.topCalls = (self.topCalls or 0) + 1 end
function UI:drawText(text, ...) self.calls[#self.calls + 1] = { text = text, args = { ... } } end
function UI:render() self.renderCalls = (self.renderCalls or 0) + 1 end

ISCollapsableWindow = UI:derive("ISCollapsableWindow")
function ISCollapsableWindow:titleBarHeight() return 20 end
function ISCollapsableWindow:close() self:setVisible(false) end
ISButton = UI:derive("ISButton")
function ISButton:new(x, y, width, height, title, target, callback)
    local object = UI.new(self, x, y, width, height)
    object.title, object.target, object.callback = title, target, callback
    return object
end
function ISButton:click() if self.callback then self.callback(self.target, self) end end
ISTextEntryBox = UI:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, width, height)
    local object = UI.new(self, x, y, width, height)
    object.text = text
    return object
end
function ISTextEntryBox:setFont(font) self.font = font end
function ISTextEntryBox:setPlaceholderText(text) self.placeholder = text end
function ISTextEntryBox:getInternalText() return self.text end
function ISTextEntryBox:setText(text)
    self.text = text or ""
    -- Deliberately deliver a change signal so suppression/re-entry logic is exercised.
    if self.onTextChange then self:onTextChange() end
end
function ISTextEntryBox:focus()
    M.focused = self
    self.focusCalls = (self.focusCalls or 0) + 1
end
function ISTextEntryBox:unfocus() if M.focused == self then M.focused = nil end end
function ISTextEntryBox:isFocused() return M.focused == self end
ISRichTextPanel = UI:derive("ISRichTextPanel")
function ISRichTextPanel:setText(text) self.text = text end
function ISRichTextPanel:paginate() self.height = 96; self.paginateCalls = (self.paginateCalls or 0) + 1 end

function M.context()
    local context = { options = {} }
    function context:addOption(label, target, callback)
        local option = { label = label, target = target, callback = callback }
        function option:activate() return self.callback(self.target) end
        self.options[#self.options + 1] = option
        return option
    end
    return context
end
function M.releaseKey(panel, key)
    if panel:isReallyVisible() and panel.wantKeyEvents and panel.onKeyRelease then panel:onKeyRelease(key) end
end
local oldRequire = require
function require(name)
    if name == "PZAPI/ModOptions" then return assert(PZAPI and PZAPI.ModOptions, "load native ModOptions.lua before Settings") end
    if name == "SuQingSearch/Runtime" then return SuQingSearch end
    if name == "ISUI/ISCollapsableWindow" then return ISCollapsableWindow end
    if name == "ISUI/ISTextEntryBox" then return ISTextEntryBox end
    if name == "ISUI/ISButton" then return ISButton end
    if name == "ISUI/ISRichTextPanel" then return ISRichTextPanel end
    return oldRequire(name)
end
