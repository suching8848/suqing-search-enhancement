-- Pure query/matching layer. Does not access containers, reorder rows or write items.
SuQingSearch = SuQingSearch or {}
local Core = {}
SuQingSearch.Core = Core

local metadata = setmetatable({}, { __mode = "k" })

local function lower(value)
    return tostring(value or ""):gsub("[A-Z]", function(character)
        return string.char(string.byte(character) + 32)
    end)
end

local function contains(value, query)
    return string.find(lower(value), query, 1, true) ~= nil
end

local function safeCall(object, method)
    if object == nil then return nil end
    local ok, member = pcall(function() return object[method] end)
    if not ok or type(member) ~= "function" then return nil end
    local success, value = pcall(member, object)
    if success then return value end
    return nil
end

local function isSpace(character)
    return character == " " or character == "\t" or character == "\n" or character == "\r"
end

-- OR has the lowest precedence. An AND clause is one whitespace-separated term.
-- Prefixes must be outside quotation marks: @"Mod Name", -"item name", &Base.Type.
-- Quotes preserve literal spaces/pipes/prefixes, and accept \\" and \\\\ escapes.
function Core.compile(query)
    local result = { groups = {}, active = false, special = false }
    if query == nil then return result end
    query = tostring(query)
    local length, position = #query, 1
    local current = {}
    local function fail(key)
        result.groups = {}
        result.active = true
        result.errorKey = key
        return result
    end
    while position <= length do
        local character = query:sub(position, position)
        if isSpace(character) then
            position = position + 1
        elseif character == "|" then
            result.special = true
            if #current == 0 then return fail("UI_SQSearch_ErrorEmptyOr") end
            result.groups[#result.groups + 1] = current
            current = {}
            result.active = true
            position = position + 1
        else
            result.active = true
            if #current > 0 then result.special = true end
            local term = { field = "name", negated = false }
            if character == "-" then
                result.special = true
                term.negated = true
                position = position + 1
                character = query:sub(position, position)
            end
            if character == "@" or character == "&" then
                result.special = true
                term.field = character == "@" and "mod" or "id"
                position = position + 1
            end
            local text = {}
            local inQuote = false
            while position <= length do
                character = query:sub(position, position)
                if character == '"' then
                    result.special = true
                    inQuote = not inQuote
                    position = position + 1
                elseif inQuote and character == "\\" then
                    local nextCharacter = query:sub(position + 1, position + 1)
                    if nextCharacter == '"' or nextCharacter == "\\" then
                        text[#text + 1] = nextCharacter
                        position = position + 2
                    else
                        text[#text + 1] = character
                        position = position + 1
                    end
                elseif not inQuote and (isSpace(character) or character == "|") then
                    break
                else
                    text[#text + 1] = character
                    position = position + 1
                end
            end
            if inQuote then return fail("UI_SQSearch_ErrorUnclosedQuote") end
            local value = table.concat(text)
            if value == "" or value:match("^%s*$") then
                return fail("UI_SQSearch_ErrorMissingTerm")
            end
            term.value = lower(value)
            current[#current + 1] = term
        end
    end
    if result.active and #current == 0 then return fail("UI_SQSearch_ErrorEmptyOr") end
    if #current > 0 then result.groups[#result.groups + 1] = current end
    return result
end

-- Use the parser's own grammar so source/ID prefixes, exclusions, OR, quoted
-- phrases and whitespace AND all activate special-only integration. A literal
-- hyphen/@/& within a name and surrounding whitespace retain native searching.
-- Invalid special syntax still belongs to the enhanced parser's error display.
function Core.hasSpecialSyntax(query)
    return Core.compile(query).special == true
end

local function getMetadata(item)
    local cached = metadata[item]
    if cached then return cached end
    local fullType = safeCall(item, "getFullType")
    local modID = safeCall(item, "getModID")
    if fullType == nil or fullType == "" then
        local scriptItem = safeCall(item, "getScriptItem")
        fullType = safeCall(scriptItem, "getFullName")
    end
    if modID == nil or modID == "" then
        modID = safeCall(safeCall(item, "getScriptItem"), "getModID")
    end
    local vanilla = safeCall(item, "isVanilla") == true or lower(modID) == "pz-vanilla"
    local result = {
        fullType = fullType and lower(fullType) or "",
        modID = modID and tostring(modID) or "",
        vanilla = vanilla,
    }
    -- Cache immutable identifiers only. Do not pin a temporarily unresolved source.
    if result.fullType ~= "" and (result.modID ~= "" or vanilla) then
        metadata[item] = result
    end
    return result
end

local function humanText(text, value, options)
    text = tostring(text or "")
    if text == "" then return false end
    -- The scan matcher includes the same literal check. Let it reuse the full
    -- result across instances and category labels before doing any text work.
    if type(options.scanTextMatcher) == "function" then
        local ok, answer = pcall(options.scanTextMatcher, text, value)
        if ok then return answer == true end
        return contains(text, value)
    end
    if contains(text, value) then return true end
    -- The new shared matcher owns optional pinyin and separator tolerance.
    -- Retain the old callback contract only when no shared matcher is supplied.
    local matcher = options.textMatcher
    if type(matcher) ~= "function" then matcher = options.pinyinMatcher end
    if type(matcher) ~= "function" then return false end
    local ok, answer = pcall(matcher, text, value)
    return ok and answer == true
end

local function anyNameMatches(names, value, options)
    if type(names) == "string" then return humanText(names, value, options) end
    if type(names) == "table" then
        for _, name in ipairs(names) do
            if type(name) == "string" and humanText(name, value, options) then return true end
        end
    end
    return false
end

local function lookup(names, modID)
    if type(names) ~= "table" then return nil end
    return names[modID] or names[lower(modID)]
end

local function modMatches(item, info, value, options)
    if info.modID ~= "" and contains(info.modID, value) then return true end
    if anyNameMatches(lookup(options.modNames, info.modID), value, options) then return true end
    if anyNameMatches(lookup(options.aliases, info.modID), value, options) then return true end
    if info.vanilla then
        return anyNameMatches(options.vanillaNames or { "vanilla", "pz-vanilla" }, value, options)
    end
    if info.modID == "" then
        return anyNameMatches(options.unknownNames or { "unknown" }, value, options)
    end
    -- Some integrations provide a display-name method. A namespace is never a source.
    local displayName = safeCall(item, "getModName")
    return displayName ~= nil and humanText(displayName, value, options)
end

function Core.matches(item, compiled, options)
    if item == nil or type(compiled) ~= "table" then return false end
    if compiled.errorKey ~= nil then return false end
    if not compiled.active then return true end
    if type(compiled.groups) ~= "table" or #compiled.groups == 0 then return false end
    options = type(options) == "table" and options or {}
    local info, names
    for _, group in ipairs(compiled.groups) do
        local matchesGroup = type(group) == "table" and #group > 0
        if matchesGroup then
            for _, term in ipairs(group) do
                local matched = false
                if term.field == "name" then
                    -- Names may change on rename, fluid changes or item condition changes.
                    if names == nil then
                        names = {
                            safeCall(item, "getName") or "",
                            safeCall(item, "getDisplayName") or "",
                            safeCall(item, "getType") or "",
                        }
                    end
                    matched = anyNameMatches(names, term.value, options)
                elseif term.field == "id" or term.field == "mod" then
                    if info == nil then info = getMetadata(item) end
                    if term.field == "id" then
                        matched = info.fullType ~= "" and info.fullType == term.value
                    else
                        matched = modMatches(item, info, term.value, options)
                    end
                end
                if term.negated then matched = not matched end
                if not matched then
                    matchesGroup = false
                    break
                end
            end
        end
        if matchesGroup then return true end
    end
    return false
end

-- Useful after a script reload; no item or save data is changed.
function Core.clearMetadataCache()
    metadata = setmetatable({}, { __mode = "k" })
end

return Core
