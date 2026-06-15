--[[
pure text helpers for matching highlighted words to contexts
no KOReader dependencies, just word normalization, filename sanitizing, trimming, and a
fuzzy similarity score used to suggest merging a new word into an existing context
]]

local ContextText = {}

--how alike two contexts must be (0..1) before we suggest merging instead of creating new
ContextText.SIMILARITY_THRESHOLD = 0.7

--normalize a word so that variations of it map to the same context
--lowercases, strips surrounding punctuation, and removes the possessive "'s"
function ContextText.normalizeWord(word)
    if not word then return "" end
    word = word:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    word = word:lower()
    word = word:gsub("\u{2019}", "'")                    --curly apostrophe -> straight (Lua patterns are byte-based, so a multibyte char can't live in a [class])
    word = word:gsub("^[%p]+", ""):gsub("[%p]+$", "")    --trim leading/trailing punctuation
    word = word:gsub("'s$", "")                          --possessive 's
    if #word > 3 then word = word:gsub("s$", "") end     --plural/trailing s (only on longer words, so "bus" stays "bus")
    return word
end

--make sure that strings are safe to use as a file name
function ContextText.sanitizeFilename(name)
    name = (name or ""):gsub("[/\\:%*%?\"<>|%c]", "_")
    name = name:gsub("^%.+", ""):gsub("%s+$", "")
    if name == "" then name = "Untitled" end
    return name
end

--trim leading/trailing whitespace from a string
function ContextText.trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--Levenshtein edit distance between two strings (byte-wise, fine for our short names)
local function levenshtein(a, b)
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = { [0] = i }
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

--similarity of two already-normalized words, 0 (nothing alike) to 1 (identical)
--containment (e.g. "jon" inside "jon snow") counts as a strong match
function ContextText.similarity(a, b)
    if a == "" or b == "" then return 0 end
    if a == b then return 1 end
    if #a >= 3 and #b >= 3 and (a:find(b, 1, true) or b:find(a, 1, true)) then
        return 0.9
    end
    return 1 - levenshtein(a, b) / math.max(#a, #b)
end

return ContextText
