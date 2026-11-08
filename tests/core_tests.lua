-- Execute after shared/SuQingSearch/Core.lua in Lua 5.1 or the game's standalone Kahlua.
-- Uses deterministic mock items only; never loads a save or starts Project Zomboid.
local Core = assert(SuQingSearch and SuQingSearch.Core, "load SuQingSearch/Core first")
local cases, assertions = 0, 0
local function equal(actual, expected, message)
    assertions = assertions + 1
    assert(actual == expected, (message or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function item(name, fullType, modID, vanilla)
    local result = { name = name, fullType = fullType, modID = modID, vanilla = vanilla }
    function result:getName() return self.name end
    function result:getFullType() return self.fullType end
    function result:getModID() return self.modID end
    function result:isVanilla() return self.vanilla end
    return result
end
local gun = item("M110 Rifle", "Base.M110", "ModernFirearmsSystem", false)
local nails = item("Nails", "Base.Nails", "pz-vanilla", true)
local nailsBox = item("Nails Box", "Base.NailsBox", "pz-vanilla", true)
local options = {
    modNames = { ModernFirearmsSystem = "Escape from Kentucky - Modern Firearms System" },
    aliases = { ModernFirearmsSystem = { "MFS", "现代枪械", "枪械系统" } },
    vanillaNames = { "vanilla", "原版" },
    unknownNames = { "unknown", "未知来源" },
}
local function test(query, object, expected, message, custom)
    cases = cases + 1
    equal(Core.matches(object, Core.compile(query), custom or options), expected, message or query)
end

test("", gun, true, "empty query")
test(" \t\r\n", gun, true, "whitespace query")
test(nil, gun, true, "nil query")
test("m110", gun, true, "ASCII insensitive name")
test("M110 rifle", gun, true, "AND whitespace")
test("m110 nails", gun, false, "AND not OR")
test("m110 | nails", gun, true, "first OR group")
test("m110 | nails", nails, true, "second OR group")
test("m110 -rifle | nails -box", gun, false, "AND binds above OR")
test("m110 -rifle | nails -box", nails, true, "separate OR branch")
test("m110 -rifle | nails -box", nailsBox, false, "NOT in second branch")
test("-box", nails, true, "negative-only query")
test("-box", nailsBox, false, "negative-only rejection")
test('"M110 Rifle"', gun, true, "quoted name")
test('"M110  Rifle"', gun, false, "quoted spaces preserved")
test('"@MFS"', item("@MFS", "Base.Test", "pz-vanilla", true), true, "quoted prefix is literal")
test('"A | B"', item("A | B", "Base.Test", "pz-vanilla", true), true, "quoted OR is literal")
test('"A \\"B\\""', item('A "B"', "Base.Test", "pz-vanilla", true), true, "escaped quote")
test('"A\\\\B"', item("A\\B", "Base.Test", "pz-vanilla", true), true, "escaped backslash")
test("@mfs", gun, true, "registered acronym alias")
test("@现代枪械", gun, true, "Chinese alias")
test("@ModernFirearmsSystem", gun, true, "real Mod ID")
test('@"Escape from Kentucky" m110', gun, true, "quoted mod display name")
test("@原版", nails, true, "localized vanilla alias")
test("@原版", gun, false, "Base namespace does not imply vanilla")
test("@base", gun, false, "namespace is not Mod ID")
test("-@MFS", gun, false, "negated source")
test("@MFS &base.m110", gun, true, "source AND exact ID")
test("&Base.Nails", nails, true, "full ID exact equality")
test("&Base.Nails", nailsBox, false, "full ID rejects common prefix")
test("&nails", nails, false, "partial ID is not full ID")
test("-&Base.Nails", nailsBox, true, "negated exact ID")

local unknown = item("Unknown item", "Custom.Test", nil, false)
test("@未知来源", unknown, true, "localized unknown source")
test("@原版", unknown, false, "unknown source is not vanilla")
test("&Custom.Test", unknown, true, "unknown source still has exact ID")
unknown.modID = "ModernFirearmsSystem"
test("@MFS", unknown, true, "unresolved sources not permanently cached")

local renamed = item("Original bag", "Base.Bag", "pz-vanilla", true)
test("original", renamed, true, "initial instance name")
renamed.name = "Renamed food bag"
test("original", renamed, false, "old instance name not cached")
test('"food bag"', renamed, true, "new instance name used immediately")

local scriptOnly = {
    getName = function() return "Modded tool" end,
    getScriptItem = function()
        return {
            getFullName = function() return "Base.Tool" end,
            getModID = function() return "ModernFirearmsSystem" end,
        }
    end,
}
test("@MFS &Base.Tool", scriptOnly, true, "script metadata fallback")
local displaySource = item("A tool", "Custom.Tool", "CustomMod", false)
function displaySource:getModName() return "A custom toolkit" end
test('@"custom toolkit"', displaySource, true, "optional real mod display name")

for _, query in ipairs({ "|", "|nails", "nails|", "nails||box", "nails | | box", "@", "&", "-", "-@", "-&", '"unfinished', '@"unfinished', '""', '@""', '"   "' }) do
    cases = cases + 1
    local parsed = Core.compile(query)
    equal(parsed.active, true, "invalid query remains active: " .. query)
    equal(type(parsed.errorKey), "string", "invalid query reports translation key: " .. query)
    equal(Core.matches(gun, parsed, options), false, "invalid query never broadens gun result: " .. query)
    equal(Core.matches(nails, parsed, options), false, "invalid query never broadens other result: " .. query)
end

local cnItem = item("牛肉饼", "Base.BeefPatty", "pz-vanilla", true)
test("nrb", cnItem, false, "no mandatory pinyin dependency")
test("nrb", cnItem, true, "optional pinyin callback", {
    pinyinMatcher = function(name, query) return name == "牛肉饼" and query == "nrb" end,
})
test("niuroubing", cnItem, true, "optional full pinyin callback", {
    pinyinMatcher = function(name, query) return name == "牛肉饼" and query == "niuroubing" end,
})
test("nrb", cnItem, false, "pinyin callback failure is a miss", {
    pinyinMatcher = function() error("test provider unavailable") end,
})
test("牛肉", cnItem, true, "native Chinese substring")

-- Dispatch human-readable fields through the shared matcher. Identifier syntax
-- deliberately stays outside this callback so loose text can never broaden &.
local humanAliases = {
    ["牛肉饼"] = { nrb = true, niuroubing = true },
    ["现代枪械"] = { xdqx = true, xiandaiqiangxie = true },
    ["原版"] = { yb = true, yuanban = true },
    ["未知来源"] = { wzly = true },
    ["中文工具包"] = { zwgjb = true },
    ["Beef_Patty"] = { ["beef patty"] = true },
    ["Modern Firearms"] = { modernfirearms = true },
    ["Guns and Ammo"] = { gunsandammo = true },
}
local function sharedMatcher(text, query)
    return humanAliases[text] and humanAliases[text][query] == true or false
end
local sharedOptions = {
    textMatcher = sharedMatcher,
    modNames = { ModernFirearmsSystem = "现代枪械" },
    aliases = { ModernFirearmsSystem = { "Modern Firearms", "现代枪械", "Guns and Ammo" } },
    vanillaNames = { "原版" },
    unknownNames = { "未知来源" },
}
test("NRB", cnItem, true, "uppercase initials share human matcher", sharedOptions)
test("NIUROUBING", cnItem, true, "uppercase full pinyin share human matcher", sharedOptions)
test("RiF", gun, true, "mixed case partial literal still matches")
test("RIF", gun, true, "uppercase partial literal still matches")
test("@XDQX", gun, true, "mod human display name uses shared initials matcher", sharedOptions)
test("@XIAnDAIQIANGXIE", gun, true, "mod human display name uses full pinyin matcher", sharedOptions)
test("@GunsAndAmmo", gun, true, "human alias supports compact matching", sharedOptions)
test("@YB", nails, true, "localized vanilla alias uses shared matcher", sharedOptions)
local unknownSource = item("Tool", "Custom.Unknown", nil, false)
test("@WZLY", unknownSource, true, "localized unknown alias uses shared matcher", sharedOptions)
local namedSource = item("Tool", "Custom.Named", "OtherSourceID", false)
function namedSource:getModName() return "中文工具包" end
test("@ZWGJB", namedSource, true, "optional mod display name uses shared matcher", sharedOptions)

local renamedPatty = item("My lunch", "Base.BeefPatty", "pz-vanilla", true)
function renamedPatty:getDisplayName() return "牛肉饼" end
function renamedPatty:getType() return "Beef_Patty" end
test("lunch", renamedPatty, true, "current instance name remains searchable", sharedOptions)
test("NRB", renamedPatty, true, "display name remains searchable after rename", sharedOptions)
test("PATTY", renamedPatty, true, "plain item type fallback retains prior inventory capability", sharedOptions)
test('"Beef Patty"', renamedPatty, true, "item type fallback uses shared loose matcher", sharedOptions)
local legacySource = {
    aliases = { ModernFirearmsSystem = { "现代枪械" } },
    pinyinMatcher = sharedMatcher,
}
test("@XDQX", gun, true, "legacy pinyin callback also works for source human aliases", legacySource)
test("NRB", cnItem, false, "new shared matcher takes priority over legacy callback", {
    textMatcher = function() return false end,
    pinyinMatcher = function() return true end,
})
test("NRB", cnItem, false, "shared matcher error remains a miss", {
    textMatcher = function() error("unavailable text provider") end,
})
test("牛肉", cnItem, true, "literal fallback survives failed shared matcher", {
    textMatcher = function() error("unavailable text provider") end,
})
local providerCalls = 0
local permissive = { textMatcher = function() providerCalls = providerCalls + 1; return true end }
test("&BASE.NAILS", nails, true, "full ID remains case insensitive exact equality", permissive)
test("&Base.Nail", nails, false, "full ID rejects partial even with permissive text provider", permissive)
test("&Base.Nails", nailsBox, false, "full ID rejects prefix sibling with text provider", permissive)
test("&BaseNails", nails, false, "full ID never removes separators", permissive)
test("-&Base.Nails", nailsBox, true, "negated ID remains strict with text provider", permissive)
cases = cases + 1
equal(providerCalls, 0, "exact identifiers never call a human text provider")
test("@MODERNFIREARMS", gun, true, "Mod ID keeps case-insensitive literal substring", permissive)
test("@Modern-Firearms-System", gun, false, "Mod ID alone never uses human separator tolerance", permissive)
cases = cases + 1
equal(providerCalls, 0, "literal Mod ID path does not invoke human text provider without human names")

local scanOptions = {
    scanTextMatcher = function(text, query)
        providerCalls = providerCalls + 1
        return sharedMatcher(text, query)
    end,
    modNames = sharedOptions.modNames,
}
test("@XDQX &Base.M110", gun, true, "scan matcher participates in source and exact ID query", scanOptions)
test("NRB -@XDQX", cnItem, true, "scan matcher participates in name and source exclusion", scanOptions)
test("&Base.Nails", nails, true, "standalone ID still bypasses the scan matcher", scanOptions)
equal(providerCalls, 4, "only name, source display name and vanilla aliases use scan matcher")
test("牛肉", cnItem, true, "literal fallback survives failed scan matcher", {
    scanTextMatcher = function() error("test scan failure") end,
})

-- Evaluate mixed displayed stacks per instance, never infer all rows from a head item.
local mixedStack = { nails, nailsBox, item("Nails", "ThirdParty.Nails", "ModernFirearmsSystem", false) }
local parsed = Core.compile("@MFS nails")
local count = 0
for _, object in ipairs(mixedStack) do
    if Core.matches(object, parsed, options) then count = count + 1 end
end
cases = cases + 1
equal(count, 1, "same display-name stack retains only correct source instance")
local exactCount = 0
for _, object in ipairs(mixedStack) do
    if Core.matches(object, Core.compile("&Base.Nails"), options) then exactCount = exactCount + 1 end
end
cases = cases + 1
equal(exactCount, 1, "mixed stack exact fullType")

cases = cases + 1
equal(Core.matches(nil, Core.compile(""), options), false, "nil item rejected")
equal(Core.matches({}, Core.compile("nails"), options), false, "missing methods safe")
equal(Core.matches({}, Core.compile("@未知来源"), options), true, "missing methods unknown source")
equal(Core.matches(gun, { active = true, groups = { {} } }, options), false, "empty compiled clause never matches")
equal(Core.matches(gun, { active = true, groups = {} }, options), false, "empty active query never matches")
Core.clearMetadataCache()
test("@MFS &Base.M110", gun, true, "cache reset preserves meaning")

-- Special-only integration follows the same grammar as enhanced compilation,
-- including AND whitespace and malformed syntax that needs an enhanced error.
local unicodeName = "\231\137\155\232\130\137\233\165\188" -- UTF-8 牛肉饼, matching Java UI input.
for _, query in ipairs({ "", " \t\r\n", "nails", unicodeName, " NRB ", "M-16", "A@B", "A&B", "C:\\Tools" }) do
    cases = cases + 1
    equal(Core.hasSpecialSyntax(query), false, "literal query remains native: " .. query)
    equal(Core.compile(query).special, false, "literal parse flag: " .. query)
end
for _, query in ipairs({ "@MFS", "&Base.Nails", "-box", "-@MFS", "-&Base.Nails", "nails | box", "nails box", "nails\tbox", '"nails box"', '"A \\"B\\""', "@", "&", "-", "|", "nails|", '"unfinished', '""' }) do
    cases = cases + 1
    equal(Core.hasSpecialSyntax(query), true, "special query activates enhancement: " .. query)
    equal(Core.compile(query).special, true, "special parse flag: " .. query)
end
cases = cases + 1
equal(Core.hasSpecialSyntax(nil), false, "nil query remains native")
return "SQSEARCH_CORE cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
