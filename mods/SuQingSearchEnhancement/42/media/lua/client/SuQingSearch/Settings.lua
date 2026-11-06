require "PZAPI/ModOptions"

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

function SQ.getOptions()
    local result = {}
    for _, key in ipairs({"integrate", "clickPopup", "openKey", "showCounts", "showHelp", "pinyin", "sortMatches", "showContextMenu"}) do
        result[key] = options:getOption(key):getValue()
    end
    return result
end

options.apply = function()
    if SQ.Integration then SQ.Integration.refreshOptions() end
    if SQ.markDirty then SQ.markDirty() end
end
