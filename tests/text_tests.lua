-- Load generated upstream dictionary fixture, text_bootstrap, Text and the
-- actual installed pinyin.lua before this test, in a standalone Lua environment.
local T = assert(SuQingSearch and SuQingSearch.Text, "load SuQingSearch/Text first")
local provider = assert(type(pinyin) == "function" and pinyin, "load actual upstream pinyin.lua")
local cases, assertions = 0, 0
local function equal(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local calls = 0
local function actualConverter(text, delimiter)
    calls = calls + 1
    equal(delimiter, string.char(31), "provider receives unambiguous variant separator")
    return provider(text, delimiter)
end
local function test(text, query, expected, label, enabled)
    cases = cases + 1
    equal(T.matches(text, query, enabled ~= false), expected, label)
end

T.setConverter(actualConverter)
test("M110 Rifle", "m110", true, "English literal ASCII case fold")
test("M110 rifle", "RIFLE", true, "English uppercase query")
test("MixedCASE", "xEdCa", true, "case-insensitive partial substring")
equal(calls, 0, "literal hits do not call optional provider")
test("M110_Rifle", "m110rifle", true, "underscore compact literal")
test("M110-Rifle", "M110_RIFLE", true, "hyphen and underscore separators equivalent")
test("M110  Rifle", "m110rifle", true, "multiple spaces compact literal")
test("M110\tRifle", "M110 rifle", true, "whitespace compact literal")
test("M110\227\128\128Rifle", "m110rifle", true, "ideographic space compact literal")
test("M110\194\160Rifle", "m110rifle", true, "nonbreaking space compact literal")
test("Xi'an", "XIAN", true, "ASCII pinyin apostrophe compact literal")
test("Xi\226\128\153an", "xian", true, "typographic pinyin apostrophe compact literal")
test("Base.M110", "basem110", false, "dot remains meaningful", false)
test("A/B", "ab", false, "slash remains meaningful", false)
test("A:B", "ab", false, "colon remains meaningful", false)
test("A+B", "ab", false, "plus remains meaningful", false)
test("ordinary text", "-_' ", false, "separator-only query does not broaden to all text")
test("A-B", "-", true, "literal separator still matches when actually present")
test(nil, "x", false, "nil text safe")
test("", "", true, "empty query follows substring contract")

test("\231\137\155\232\130\137\233\165\188", "NIUROUBING", true, "real provider full pinyin case fold")
test("\231\137\155\232\130\137\233\165\188", "NRB", true, "real provider initials case fold")
test("\231\137\155\232\130\137\233\165\188", "ROUB", true, "partial full-pinyin substring")
test("\231\137\155\232\130\137\233\165\188", "RB", true, "partial initials substring")
test("\231\137\155\232\130\137\233\165\188", "niu rou-bing", true, "query syllable separators compacted")
test("\231\137\155\232\130\137\233\165\188", "n_r_b", true, "query initial separators compacted")
test("\231\137\155\232\130\137\233\165\188", "\231\137\155\232\130\137", true, "native Chinese literal unchanged")
test("\231\137\155\232\130\137\233\164\133", "niuroubing", true, "traditional target full pinyin")
test("\231\137\155\232\130\137\233\164\133", "NRB", true, "traditional target initials")
test("\232\152\135\230\184\133", "SUQING", true, "traditional source-name text conversion")
test("\232\152\135\230\184\133", "SQ", true, "traditional source-name initials")
test("\233\147\157\230\163\146", "LVBANG", true, "upstream uses ASCII v for umlaut")
test("\233\139\129\230\163\146", "lb", true, "traditional umlaut initials")
test("\230\144\156\231\180\162\229\162\158\229\188\186", "SOUSUOZENGQIANG", true, "real provider polyphonic full variant")
test("\230\144\156\231\180\162\229\162\158\229\188\186", "SOUSUOZENGJIANG", true, "alternate polyphonic full variant retained")
test("\230\144\156\231\180\162\229\162\158\229\188\186", "SSZQ", true, "polyphonic initials variant")
test("\230\144\156\231\180\162\229\162\158\229\188\186", "SSZJ", true, "alternate polyphonic initials variant")
test("M110\230\173\165\230\158\170", "m110BQ", true, "mixed Latin and Chinese initials")
test("M110 \230\173\165\230\167\141", "M110BQ", true, "mixed target whitespace compacted")
test("M110_\230\173\165\230\158\170", "m110buqiang", true, "mixed target underscore compacted")
test("M110-\230\173\165\230\167\141", "M110 BQ", true, "mixed target hyphen and query whitespace")
test("\231\137\155\232\130\137\233\165\188", "NRB", false, "pinyin disable retains literal path only", false)
test("\231\137\155\232\130\137\233\165\188", "\231\137\155\232\130\137", true, "pinyin disable still permits Chinese literal", false)
test("M110_Rifle", "M110RIFLE", true, "pinyin disable still permits compact ASCII", false)

cases = cases + 1
local before = calls
T.matches("\231\137\155\232\130\137\233\165\188", "does-not-match", true)
T.matches("\231\137\155\232\130\137\233\165\188", "also-no-match", true)
equal(calls, before, "repeated name conversions reused across different query terms")
T.setConverter(actualConverter)
T.matches("\231\137\155\232\130\137\233\165\188", "NRB", true)
equal(calls, before + 1, "setConverter invalidates old name cache even with same function")

cases = cases + 1
local boundaryCalls = 0
T.setConverter(function(text, delimiter)
    boundaryCalls = boundaryCalls + 1
    equal(delimiter, string.char(31), "custom provider exact delimiter")
    return "foo" .. delimiter .. "bar" .. delimiter .. "F-B" .. delimiter .. ""
end)
equal(T.matches("unrelated target", "foo", true), true, "first variant matched")
equal(T.matches("unrelated target", "BAR", true), true, "second variant matched")
equal(T.matches("unrelated target", "fb", true), true, "separators compact within one variant")
equal(T.matches("unrelated target", "oob", true), false, "no substring across adjacent variants")
equal(T.matches("unrelated target", "foobar", true), false, "variants never concatenated for compact match")
equal(T.matches("unrelated target", "foo-bar", true), false, "query separators cannot join independent variants")
equal(boundaryCalls, 1, "one cached conversion for all variant queries")

cases = cases + 1
T.setConverter(nil)
test("\231\137\155\232\130\137\233\165\188", "NRB", false, "missing optional provider is a pinyin miss")
test("M110_Rifle", "m110rifle", true, "missing provider preserves compact literal")
equal(T.matches("\231\137\155\232\130\137\233\165\188", "\231\137\155\232\130\137", true), true, "missing provider preserves Chinese literal")

cases = cases + 1
TextMock.logs = {}
local failedCalls = 0
T.setConverter(function()
    failedCalls = failedCalls + 1
    error("provider test failure")
end)
equal(T.matches("\231\137\155\232\130\137\233\165\188", "NRB", true), false, "provider failure safely falls back")
equal(T.matches("\231\137\155\232\130\137\233\165\188", "niuroubing", true), false, "negative conversion result cached")
equal(failedCalls, 1, "same failing name does not hammer provider")
equal(T.matches("\232\152\135\230\184\133", "SQ", true), false, "another provider failure remains a miss")
equal(#TextMock.logs, 1, "provider failure logged at most once per provider install")
equal(T.matches("\231\137\155\232\130\137\233\165\188", "\231\137\155\232\130\137", true), true, "provider failure does not block literal hit")
T.setConverter(function() return {} end)
equal(T.matches("\231\137\155\232\130\137\233\165\188", "NRB", true), false, "unexpected provider result type is a safe miss")

cases = cases + 1
local boundedCalls = 0
T.setConverter(function(text, delimiter) boundedCalls = boundedCalls + 1; return "converted" end)
local accidentalHits = 0
for index = 1, 512 do if T.matches("target-" .. tostring(index), "absent", true) then accidentalHits = accidentalHits + 1 end end
equal(accidentalHits, 0, "cache population does not broaden nonmatching queries")
equal(boundedCalls, 512, "512 unique names converted once")
T.matches("target-1", "absent", true)
equal(boundedCalls, 512, "earliest name retained through cache capacity")
T.matches("target-513", "absent", true)
equal(boundedCalls, 513, "next unique name converted at capacity boundary")
for index = 1, 512 do T.matches("target-" .. tostring(index), "absent", true) end
equal(boundedCalls > 513, true, "bounded eviction allows some older names to be recomputed")

cases = cases + 1
T.setConverter(actualConverter)
local displayedName = "\231\137\155\232\130\137\233\165\188"
equal(T.matches(displayedName, "NRB", true), true, "current instance name romanized")
displayedName = "\232\152\135\230\184\133"
equal(T.matches(displayedName, "NRB", true), false, "rename never reuses different name's romanization")
equal(T.matches(displayedName, "SQ", true), true, "renamed instance uses new pinyin")
T.setConverter(nil)
return "SQSEARCH_TEXT cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0 language=" .. TextMock.language
