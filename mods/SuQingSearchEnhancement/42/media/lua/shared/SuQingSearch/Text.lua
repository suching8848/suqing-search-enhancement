-- Text matching only. Optional romanization is supplied by the active provider;
-- this module does not contain or redistribute a third-party pinyin dictionary.
SuQingSearch = SuQingSearch or {}
local Text = {}
SuQingSearch.Text = Text

local converter
local cache, cacheSize = {}, 0
local warned = false
local separator = string.char(31)
local CACHE_LIMIT = 512

local function fold(value)
    return tostring(value or ""):gsub("[A-Z]", function(character)
        return string.char(string.byte(character) + 32)
    end)
end

local function removeLiteral(value, needle)
    local parts, position = {}, 1
    while true do
        local boundary = value:find(needle, position, true)
        if not boundary then
            parts[#parts + 1] = value:sub(position)
            return table.concat(parts)
        end
        parts[#parts + 1] = value:sub(position, boundary - 1)
        position = boundary + #needle
    end
end

local function compact(value)
    -- Keep dots, slashes and other punctuation meaningful. The Unicode strings
    -- below are the nonbreaking/ideographic spaces and typographic apostrophe.
    -- PZ's lexer reads numeric escapes as UTF-8 bytes before constructing strings.
    -- These spellings preserve the exact characters in both PZ and Lua 5.1.
    value = removeLiteral(value, "\194\160")
    value = removeLiteral(value, "\227\128\128")
    value = removeLiteral(value, "\226\128\153")
    return value:gsub("[%s%-%_']", "")
end

local function contains(text, query)
    return text:find(query, 1, true) ~= nil
end

local function variantMatches(value, query, compactQuery)
    if contains(value, query) then return true end
    return compactQuery ~= "" and contains(compact(value), compactQuery)
end

function Text.setConverter(value)
    assert(value == nil or type(value) == "function", "pinyin converter must be a function or nil")
    converter = value
    cache, cacheSize, warned = {}, 0, false
end

local function candidates(text)
    local cached = cache[text]
    if cached ~= nil then return cached end
    local values = {}
    local ok, result = pcall(converter, text, separator)
    if ok and type(result) == "string" then
        local position = 1
        while position <= #result do
            local boundary = result:find(separator, position, true)
            local value = result:sub(position, boundary and boundary - 1 or #result)
            if value ~= "" then values[#values + 1] = fold(value) end
            if not boundary then break end
            position = boundary + 1
        end
    elseif not warned then
        warned = true
        if type(print) == "function" then
            print("[SuQingSearch] Optional pinyin conversion failed; literal text matching remains available.")
        end
    end
    -- Negative conversion results are cached too, avoiding repeated provider
    -- errors. Eviction keeps memory bounded without holding any item instance.
    if cacheSize >= CACHE_LIMIT then cache, cacheSize = {}, 0 end
    cache[text], cacheSize = values, cacheSize + 1
    return values
end

function Text.matches(text, term, usePinyin)
    local value, query = fold(text), fold(term)
    if query == "" then return true end
    local compactQuery = compact(query)
    if variantMatches(value, query, compactQuery) then return true end
    if usePinyin ~= true or type(converter) ~= "function" or compactQuery == "" then return false end
    for _, candidate in ipairs(candidates(value)) do
        if variantMatches(candidate, query, compactQuery) then return true end
    end
    return false
end

return Text
