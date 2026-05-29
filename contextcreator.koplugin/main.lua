local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local rapidjson = require("rapidjson")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ContextCreator = WidgetContainer:extend{
    name = "contextcreator",
    -- only active when a document is open; remove this to also load in the file browser
    is_doc_only = true,
}

--normalize a word so that variations of it map to the same context
--lowercases, strips surrounding punctuation, and removes the possessive "'s"
local function normalizeWord(word)
    if not word then return "" end
    word = word:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    word = word:lower()
    word = word:gsub("^[%p]+", ""):gsub("[%p]+$", "")    --trim leading/trailing punctuation
    word = word:gsub("['\u{2019}]s$", "")                --possessive, straight or curly apostrophe
    return word
end

--make sure that strings are safe to use as a file name
local function sanitizeFilename(name)
    name = (name or ""):gsub("[/\\:%*%?\"<>|%c]", "_")
    name = name:gsub("^%.+", ""):gsub("%s+$", "")
    if name == "" then name = "Untitled" end
    return name
end

---split a multi line editor blob into a list of dot points (one per line).
local function linesToPoints(text)
    local points = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            table.insert(points, line)
        end
    end
    return points
end

function ContextCreator:init()
    self.ui.menu:registerToMainMenu(self)

    --add a button to the long press/highlight popup
    if self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("13_contextcreator", function(this)
            return {
                text = _("Add to context"),
                callback = function()
                    local word = this.selected_text and this.selected_text.text
                    this:onClose()
                    if word and word ~= "" then
                        self:showEntryEditor(word)
                    end
                end,
            }
        end)
    end
end


--storage, chose to have a json file per book

function ContextCreator:getStoreDir()
    --start from KOReader's home folder, fall back to the data dir if none is set
    local home = G_reader_settings:readSetting("home_dir") or DataStorage:getDataDir()
    --go one directory out of the home folder, then keep our files in a "contextcreator" folder there
    local parent = util.splitFilePathName((home:gsub("/+$", "")))
    local dir = parent:gsub("/+$", "") .. "/contextcreator"
    util.makePath(dir)
    return dir
end

function ContextCreator:getBookTitle()
    local props = self.ui.doc_props or {}
    local title = props.display_title or props.title
    if not title or title == "" then
        local _path, name = util.splitFilePathName(self:getBookFile())
        title = name
    end
    return title or "Untitled"
end

function ContextCreator:getBookFile()
    return (self.ui.document and self.ui.document.file) or "unknown"
end

function ContextCreator:getBookFilePath()
    return self:getStoreDir() .. "/" .. sanitizeFilename(self:getBookTitle()) .. ".json"
end

--load the {context title -> {points}} table for the current book
function ContextCreator:loadContexts()
    local f = io.open(self:getBookFilePath(), "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return {} end
    local ok, data = pcall(rapidjson.decode, content)
    if ok and type(data) == "table" then return data end
    logger.warn("ContextCreator: could not parse", self:getBookFilePath())
    return {}
end

function ContextCreator:saveContexts(contexts)
    local path = self:getBookFilePath()
    if next(contexts) == nil then
        os.remove(path)
        return
    end
    local ok, encoded = pcall(rapidjson.encode, contexts, { pretty = true, sort_keys = true })
    if not ok then
        logger.err("ContextCreator: failed to encode contexts:", encoded)
        return
    end
    local f = io.open(path, "w")
    if not f then
        logger.err("ContextCreator: could not write", path)
        return
    end
    f:write(encoded)
    f:close()
end

--find an existing context whose title matches the word
function ContextCreator:findContextKey(contexts, word)
    if contexts[word] then return word end
    local norm = normalizeWord(word)
    for title in pairs(contexts) do
        if normalizeWord(title) == norm then return title end
    end
    return nil
end


--editing

function ContextCreator:showEntryEditor(word)
    if normalizeWord(word) == "" then return end

    local contexts = self:loadContexts()
    local key = self:findContextKey(contexts, word) or word
    local points = contexts[key] or {}

    local dialog
    dialog = InputDialog:new{
        title = T(_("Context: %1"), key),
        input = table.concat(points, "\n"),
        input_hint = _("One dot point per line..."),
        description = _("Each line becomes a separate dot point."),
        allow_newline = true,
        text_height = Screen:scaleBySize(180),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local new_points = linesToPoints(dialog:getInputText())
                    if #new_points == 0 then
                        contexts[key] = nil -- emptied -> delete this context
                    else
                        contexts[key] = new_points
                    end
                    self:saveContexts(contexts)
                    UIManager:close(dialog)
                    logger.dbg("ContextCreator: saved", key, "with", #new_points, "points")
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end


--viewing contexts for a book

function ContextCreator:showAllContexts()
    local contexts = self:loadContexts()
    local items = {}
    for title, points in pairs(contexts) do
        table.insert(items, {
            text = T("%1  (%2)", title, #points),
            _title = title,
        })
    end

    if #items == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No context entries for this book yet.\n\nLong-press a word while reading and tap \"Add to context\" to start."),
        })
        return
    end

    table.sort(items, function(a, b) return a._title:lower() < b._title:lower() end)

    local menu
    menu = Menu:new{
        title = T(_("Contexts: %1"), self:getBookTitle()),
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            UIManager:close(menu)
            self:showEntryEditor(item._title)
        end,
        close_callback = function()
            UIManager:close(menu)
        end,
    }
    UIManager:show(menu)
end

--reader menu entry

function ContextCreator:addToMainMenu(menu_items)
    menu_items.contextcreator = {
        text = _("Context Creator"),
        sorting_hint = "tools",
        callback = function() self:showAllContexts() end,
    }
end

return ContextCreator
