-- Load after the native ModOptions implementation, Core.lua and Settings.lua.
-- No save or game is initialized; SandboxVars is a deterministic Lua table.
local SQ = assert(SuQingSearch)
local cases, assertions = 0, 0
local function equal(actual, expected, message)
    assertions = assertions + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local originalSandboxVars = SandboxVars
local unicodeName = "\231\137\155\232\130\137\233\165\188" -- UTF-8 牛肉饼, matching Java UI input.

for _, variables in ipairs({ false, {}, { SuQingSearchEnhancement = {} },
    { SuQingSearchEnhancement = { SearchHandling = 1 } },
    { SuQingSearchEnhancement = { SearchHandling = 0 } },
    { SuQingSearchEnhancement = { SearchHandling = 3 } },
    { SuQingSearchEnhancement = { SearchHandling = "invalid" } } }) do
    cases = cases + 1
    SandboxVars = variables
    equal(SQ.getSearchHandlingMode(), "all", "missing or unsupported values retain default")
    equal(SQ.getOptions().searchHandling, "all", "mode included in settings snapshot")
    equal(SQ.shouldHandleQuery("nails"), true, "default owns literal query")
    equal(SQ.shouldHandleQuery("@MFS"), true, "default owns special query")
    equal(SQ.shouldHandleQuery(nil), false, "default ignores nil input")
    equal(SQ.shouldHandleQuery(""), false, "default ignores empty input")
    equal(SQ.shouldHandleQuery(" \t\r\n"), false, "default ignores whitespace input")
end
SandboxVars = nil
cases = cases + 1
equal(SQ.getSearchHandlingMode(), "all", "existing world without namespace uses default")

for _, value in ipairs({ 2, "2" }) do
    SandboxVars = { SuQingSearchEnhancement = { SearchHandling = value } }
    cases = cases + 1
    equal(SQ.getSearchHandlingMode(), "special", "sandbox special-only value")
    equal(SQ.getOptions().searchHandling, "special", "special mode settings snapshot")
    for _, query in ipairs({ "", "nails", unicodeName, " NRB ", "M-16", "A@B", "A&B" }) do
        equal(SQ.shouldHandleQuery(query), false, "ordinary input remains native: " .. query)
    end
    for _, query in ipairs({ "@MFS", "&Base.Nails", "-box", "nails | box", "nails box", '"Nails Box"', "@", '"unfinished' }) do
        equal(SQ.shouldHandleQuery(query), true, "special input uses enhancement: " .. query)
    end
end

-- Sandbox reads are live; no stale setting snapshot keeps ownership after a
-- runtime sandbox edit. The caller still owns the integration tick-box gate.
cases = cases + 1
SandboxVars.SuQingSearchEnhancement.SearchHandling = 1
equal(SQ.shouldHandleQuery("nails"), true, "live mode change back to all")
SandboxVars.SuQingSearchEnhancement.SearchHandling = 2
equal(SQ.shouldHandleQuery("nails"), false, "live mode change to special only")
equal(SQ.shouldHandleQuery("nails box"), true, "AND remains special after mode change")
SandboxVars = originalSandboxVars
return "SQSEARCH_SETTINGS cases=" .. tostring(cases) .. " assertions=" .. tostring(assertions) .. " failures=0"
