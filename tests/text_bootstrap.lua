-- SQTextTranslations is supplied only by a generated validation fixture read from
-- the locally installed upstream CN/CH UI.json. No dictionary is stored here.
assert(type(SQTextTranslations) == "table", "load generated validation dictionary fixture first")
function getText(key) return SQTextTranslations[key] or key end
TextMock = { language = SQTextTestLanguage or "unknown" }
TextMock.originalPrint = print
TextMock.logs = {}
function print(message) TextMock.logs[#TextMock.logs + 1] = tostring(message) end
