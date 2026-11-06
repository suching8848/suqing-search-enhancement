require "PZAPI/ModOptions"
require "SuQingSearch/Core"

SuQingSearch = SuQingSearch or {}
local SQ = SuQingSearch
local options = PZAPI.ModOptions:getOptions("SuQingSearchEnhancement")
if not options then
    options = PZAPI.ModOptions:create("SuQingSearchEnhancement", "UI_SQSearch_Title")
    options:addTickBox("integrate", "UI_SQSearch_Integrate", true, "UI_SQSearch_IntegrateTip")
    options:addTickBox("clickPopup", "UI_SQSearch_ClickPopup", false, "UI_SQSearch_ClickPopupTip")
    options:addKeyBind("openKey", "UI_SQSearch_OpenKey", Keyboard.KEY_F8, "UI_SQSearch_OpenKeyTip")
    options:addTickBox("showCounts", "UI_SQSearch_ShowCounts", true)
    options:addTickBox("showHelp", "UI_SQSearch_ShowHelp", false)
    options:addTickBox("pinyin", "UI_SQSearch_Pinyin", true, "UI_SQSearch_PinyinTip")
    options:addTickBox("sortMatches", "UI_SQSearch_SortMatches", true, "UI_SQSearch_SortMatchesTip")
    options:addTickBox("showContextMenu", "UI_SQSearch_ContextMenu", false, "UI_SQSearch_ContextMenuTip")
end
SQ.settings = options

-- Missing options in existing worlds use the declared sandbox default. Reading
-- this on demand also picks up a world-setting change without modifying saves.
function SQ.getSearchHandlingMode()
    local variables = type(SandboxVars) == "table" and SandboxVars.SuQingSearchEnhancement or nil
    if type(variables) == "table" and tonumber(variables.SearchHandling) == 2 then
        return "special"
    end
    return "all"
end

-- Only existing search fields use this switch. The dedicated enhanced panel
-- always supports the complete query language regardless of the sandbox mode.
function SQ.shouldHandleQuery(query)
    if not tostring(query or ""):find("%S") then return false end
    return SQ.getSearchHandlingMode() == "all" or SQ.Core.hasSpecialSyntax(query)
end

function SQ.getOptions()
    local result = {}
    for _, key in ipairs({"integrate", "clickPopup", "openKey", "showCounts", "showHelp", "pinyin", "sortMatches", "showContextMenu"}) do
        result[key] = options:getOption(key):getValue()
    end
    result.searchHandling = SQ.getSearchHandlingMode()
    return result
end

options.apply = function()
    if SQ.Integration then SQ.Integration.refreshOptions() end
    if SQ.markDirty then SQ.markDirty() end
end
