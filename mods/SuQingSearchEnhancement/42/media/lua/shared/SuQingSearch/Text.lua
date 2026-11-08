-- Text matching only. Optional romanization is supplied by the active provider;
-- this module does not contain or redistribute a third-party pinyin dictionary.
SuQingSearch = SuQingSearch or {}
local Text = {}
SuQingSearch.Text = Text

local converter, converterRevision = nil, 0
local cache, cacheOrder, cacheHead, cacheSize, cacheWeight = {}, {}, 1, 0, 0
local warned = false
local separator = string.char(31)
local CACHE_ENTRY_LIMIT = 4096
local CACHE_WEIGHT_LIMIT = 4 * 1024 * 1024
local SCAN_ENTRY_LIMIT = 4096
local SCAN_WEIGHT_LIMIT = 512 * 1024

local function lowerASCII(character)
    return string.char(string.byte(character) + 32)
end

local function fold(value)
    value = tostring(value or "")
    if not value:find("[A-Z]") then return value end
    return (value:gsub("[A-Z]", lowerASCII))
end

local function removeLiteral(value, needle)
    local boundary = value:find(needle, 1, true)
    if not boundary then return value end
    local parts, position = {}, 1
    while boundary do
        parts[#parts + 1] = value:sub(position, boundary - 1)
        position = boundary + #needle
        boundary = value:find(needle, position, true)
    end
    parts[#parts + 1] = value:sub(position)
    return table.concat(parts)
end

local function compact(value)
    -- Keep dots, slashes and other punctuation meaningful. The Unicode strings
    -- below are the nonbreaking/ideographic spaces and typographic apostrophe.
    -- PZ's lexer reads numeric escapes as UTF-8 bytes before constructing strings.
    -- These spellings preserve the exact characters in both PZ and Lua 5.1.
    value = removeLiteral(value, "\194\160")
    value = removeLiteral(value, "\227\128\128")
    value = removeLiteral(value, "\226\128\153")
    local pattern = "[%s%-%_']"
    if not value:find(pattern) then return value end
    return (value:gsub(pattern, ""))
end

local function contains(text, query)
    return text:find(query, 1, true) ~= nil
end

function Text.setConverter(value)
    assert(value == nil or type(value) == "function", "pinyin converter must be a function or nil")
    converter = value
    converterRevision = converterRevision + 1
    cache, cacheOrder, cacheHead, cacheSize, cacheWeight = {}, {}, 1, 0, 0
    warned = false
end

local function reserveCandidates(budget, text, weight)
    if weight > CACHE_WEIGHT_LIMIT then return false end
    if not budget or budget.seen[text] then return true end
    -- A scan larger than the cache must not continually evict its own early
    -- names. They can remain warm while the tail continues to match normally.
    if budget.entries == 0 or weight > budget.weight then return false end
    budget.seen[text] = true
    budget.entries = budget.entries - 1
    budget.weight = budget.weight - weight
    return true
end

local function storeCandidates(text, values, weight)
    while cacheSize == CACHE_ENTRY_LIMIT or cacheWeight + weight > CACHE_WEIGHT_LIMIT do
        local oldest = cacheOrder[cacheHead]
        cacheWeight = cacheWeight - cache[oldest].weight
        cache[oldest] = nil
        cacheOrder[cacheHead] = nil
        cacheHead = cacheHead % CACHE_ENTRY_LIMIT + 1
        cacheSize = cacheSize - 1
    end
    cacheOrder[(cacheHead + cacheSize - 1) % CACHE_ENTRY_LIMIT + 1] = text
    values.weight = weight
    cache[text] = values
    cacheSize = cacheSize + 1
    cacheWeight = cacheWeight + weight
end

local function candidates(text, budget)
    local cached = cache[text]
    if cached then
        reserveCandidates(budget, text, cached.weight)
        return cached
    end
    -- Include string content and an allowance for Lua entries. Oversized
    -- results still match in full, but are not stored in the shared cache.
    local values, weight = {}, 64 + 2 * #text
    local ok, result = pcall(converter, text, separator)
    if ok and type(result) == "string" then
        local position = 1
        while position <= #result do
            local boundary = result:find(separator, position, true)
            local value = result:sub(position, boundary and boundary - 1 or #result)
            if value ~= "" then
                value = fold(value)
                values[#values + 1] = value
                weight = weight + 24 + 2 * #value
            end
            if not boundary then break end
            position = boundary + 1
        end
    elseif not warned then
        warned = true
        if type(print) == "function" then
            print("[SuQingSearch] Optional pinyin conversion failed; literal text matching remains available.")
        end
    end
    -- Cache failed conversions too so a broken provider is not called per item.
    if reserveCandidates(budget, text, weight) then storeCandidates(text, values, weight) end
    return values
end

local function matchesPrepared(text, query, compactQuery, usePinyin, budget)
    if query == "" then return true end
    local value = fold(text)
    if contains(value, query) or (compactQuery ~= "" and contains(compact(value), compactQuery)) then
        return true
    end
    if usePinyin ~= true or type(converter) ~= "function" or compactQuery == "" then return false end
    for _, candidate in ipairs(candidates(value, budget)) do
        if contains(candidate, query) or contains(compact(candidate), compactQuery) then
            return true
        end
    end
    return false
end

function Text.matches(text, term, usePinyin)
    local query = fold(term)
    return matchesPrepared(text, query, compact(query), usePinyin)
end

-- A single scan owns its prepared terms and text results. Identical display
-- names, types and category labels can share matches without retaining items.
function Text.newMatcher(usePinyin)
    local terms, count, weight, revision = {}, 0, 0, converterRevision
    local budget = { seen = {}, entries = CACHE_ENTRY_LIMIT, weight = CACHE_WEIGHT_LIMIT }
    local function reserve(entryWeight)
        if count == SCAN_ENTRY_LIMIT or weight + entryWeight > SCAN_WEIGHT_LIMIT then return false end
        count, weight = count + 1, weight + entryWeight
        return true
    end
    return function(text, term)
        if revision ~= converterRevision then
            terms, count, weight, revision = {}, 0, 0, converterRevision
            budget = { seen = {}, entries = CACHE_ENTRY_LIMIT, weight = CACHE_WEIGHT_LIMIT }
        end
        text, term = tostring(text or ""), tostring(term or "")
        local entry = terms[term]
        if not entry then
            local query = fold(term)
            local compactQuery = compact(query)
            if not reserve(96 + 2 * (#term + #query + #compactQuery)) then
                return matchesPrepared(text, query, compactQuery, usePinyin, budget)
            end
            entry = { query = query, compactQuery = compactQuery, results = {} }
            terms[term] = entry
        end
        local matched = entry.results[text]
        if matched ~= nil then return matched end
        matched = matchesPrepared(text, entry.query, entry.compactQuery, usePinyin, budget)
        if reserve(32 + 2 * #text) then entry.results[text] = matched end
        return matched
    end
end

return Text
