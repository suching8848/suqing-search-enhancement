-- Real installed provider + generated CN dictionary + deterministic containers.
local M, SQ = SQSearchMock, SuQingSearch
local assertions, cases = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case() cases = cases + 1 end
local actualProvider = assert(pinyin)
M.pinyinProvider = actualProvider
M.options.pinyin = true
M.mods = M.list({"\\yxjs_PinYinSearch", "\\Cuisine", "\\Weapons", "\\Tools"})
function getModInfoByID(id)
    local names = {Cuisine = "\231\137\155\232\130\137\229\183\165\229\157\138", Weapons = "\231\142\176\228\187\163\230\158\170\230\162\176", Tools = "\232\152\135\230\184\133"}
    local name = names[id]
    if name then return {getName = function() return name end} end
end
SQTextTranslations.IGUI_ItemCat_Food = "\233\163\159\231\137\169"
SQTextTranslations.IGUI_ItemCat_Weapon = "\230\173\166\229\153\168"
local pancake = M.item("\231\137\155\232\130\137\233\165\188", "Cuisine.Pancake", "Cuisine", false, "Food")
local rifle = M.item("M110 \230\173\165\230\158\170", "Base.M110", "Weapons", false, "Weapon")
local tool = M.item("\232\152\135\230\184\133\229\183\165\229\133\183", "Base.SuQingTool", "Tools")
local usb = M.item("USB Cable", "Base.USBCable", "Tools")
local container = M.container("crate", {pancake, rifle, tool, usb}, true)
local page = M.page(false, {container})
M.loot[0] = page
M.emit("OnGameStart")
M.advance(121)

local function search(query, category)
    SQ.setQuery(0, query, "nearby", category or "", "cleanui")
    SQ.refreshPage(page)
    return SQ.getState(0, "nearby")
end
local function expect(query, item, category)
    local result = search(query, category)
    equal(result.matches[item], true, "runtime hit: " .. query)
    equal(result.ready, true, "runtime ordering snapshot ready: " .. query)
    return result
end

case()
equal(M.pinyinRequires, 1, "prefixed activated Mod ID loads optional provider")
expect("NIUROUBING", pancake)
expect("NRB", pancake)
expect("Niu-Rou_Bing", pancake)
expect("roub", pancake)

case()
expect("m110bq", rifle)
expect("M110BuQiang", rifle)
expect("M110-bq", rifle)
expect("uSbCa", usb)

case()
local results = expect("@SQ", tool)
equal(results.matches[usb], true, "source initials apply to every item from that source")
equal(results.matches[pancake], nil, "source pinyin does not mix unrelated mods")
expect("@SuQiNg", tool)
expect("@NRGF NRB", pancake)
expect("@WEAP M110BQ", rifle, "WQ")

case()
expect("&BASE.M110", rifle)
equal(search("&Base.M11").total, 0, "partial full ID remains exact despite fuzzy names")
equal(search("&Base.M-110").total, 0, "ID separators are never compacted")
equal(search("&NRB").total, 0, "exact ID never uses pinyin")
equal(search("@NRGF -NRB").total, 0, "pinyin exclusion uses the same item expression")

case()
M.options.pinyin = false
equal(search("NRB").total, 0, "pinyin can be disabled without resetting original settings")
expect("\231\137\155\232\130\137\233\165\188", pancake)
expect("USBCa", usb)
equal(search("@SQ").total, 0, "source pinyin obeys the same option")

case()
M.options.pinyin = true
local result = expect("NRB", pancake)
local beforeRevision = result.revision
pancake.name = "\232\152\135\230\184\133"
SQ.refreshPage(page)
equal(result.total, 0, "renamed instance drops the old pinyin hit")
equal(result.revision, beforeRevision + 1, "changed pinyin hit invalidates top-order cache")
expect("SQ", pancake)

case()
M.mods = M.list({"Cuisine", "Weapons", "Tools"})
M.emit("OnGameStart")
M.advance(121)
equal(M.pinyinRequires, 1, "disabled upstream mod is not implicitly loaded")
equal(search("@SQ").total, 0, "no provider falls back to literal sources")
expect("@Tools USB", usb)
M.mods = M.list({"yxjs_PinYinSearch", "Tools"})
M.emit("OnGameStart")
M.advance(121)
equal(M.pinyinRequires, 2, "plain activated Mod ID also loads provider")
expect("@SQ", tool)

return "SQSEARCH_PINYIN_RUNTIME cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
