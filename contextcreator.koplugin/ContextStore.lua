--[[
per book persistence, one json file per book under a "contextcreator" folder

built with the reader ui so it can read the current books title/authors/id, and owns reading
and writing the v2 document (handing shape/migration off to ContextSchema). the rest of the
plugin only ever talks to load()/save(), it never touches the filesystem directly
]]

local DataStorage = require("datastorage")
local rapidjson = require("rapidjson")
local util = require("util")
local logger = require("logger")
local ContextText = require("ContextText")
local ContextSchema = require("ContextSchema")

local ContextStore = {}
ContextStore.__index = ContextStore

function ContextStore:new(ui)
    return setmetatable({ ui = ui }, ContextStore)
end

function ContextStore:getStoreDir()
    --start from KOReaders home folder, fall back to the data dir if none is set
    local home = G_reader_settings:readSetting("home_dir") or DataStorage:getDataDir()
    --go one directory out of the home folder, then keep our files in a "contextcreator" folder there
    local parent = util.splitFilePathName((home:gsub("/+$", "")))
    local dir = parent:gsub("/+$", "") .. "/contextcreator"
    util.makePath(dir)
    return dir
end

function ContextStore:getBookFile()
    return (self.ui.document and self.ui.document.file) or "unknown"
end

function ContextStore:getBookTitle()
    local props = self.ui.doc_props or {}
    local title = props.display_title or props.title
    if not title or title == "" then
        local _path, name = util.splitFilePathName(self:getBookFile())
        title = name
    end
    return title or "Untitled"
end

function ContextStore:getBookFilePath()
    return self:getStoreDir() .. "/" .. ContextText.sanitizeFilename(self:getBookTitle()) .. ".json"
end

--the stable per book id used for sync, koreaders partial md5 of the file (same hash kosync uses,
--robust against title/filename changes). may be nil for some formats, we still work without it
function ContextStore:getBookId()
    local ds = self.ui.doc_settings
    return ds and ds:readSetting("partial_md5_checksum") or nil
end

function ContextStore:getBookAuthors()
    local props = self.ui.doc_props or {}
    return props.authors or props.author or props.Author or ""
end

--load the v2 document for the current book, migrating an old v1 file in place (in memory) on the way.
--always returns a well-shaped doc, even when the file is missing or unreadable.
function ContextStore:load()
    local path = self:getBookFilePath()
    local doc
    local f = io.open(path, "r")
    if not f then
        doc = ContextSchema.newDoc()
    else
        local content = f:read("*a")
        f:close()
        local data = nil
        if content and content ~= "" then
            local ok, decoded = pcall(rapidjson.decode, content)
            if ok and type(decoded) == "table" then
                data = decoded
            else
                logger.warn("ContextCreator: could not parse", path)
            end
        end
        if data == nil then
            doc = ContextSchema.newDoc()
        elseif data.schema == nil then
            doc = ContextSchema.migrateV1toV2(data) --old flat file
        else
            doc = data
        end
    end

    ContextSchema.normalize(doc)

    --keep the book metadata fresh (cheap, and the id/title can only become known after open)
    doc.book.id = doc.book.id or self:getBookId()
    doc.book.title = self:getBookTitle()
    doc.book.authors = self:getBookAuthors()
    return doc
end

--write the v2 document for the current book. file-level updated is bumped so a future sync can
--cheaply tell something changed. an entirely empty doc (no nodes/relationships/tombstones) is removed
function ContextStore:save(doc)
    local path = self:getBookFilePath()
    if ContextSchema.isEmpty(doc) then
        os.remove(path)
        return
    end
    doc.updated = ContextSchema.now()
    local ok, encoded = pcall(rapidjson.encode, doc, { pretty = true, sort_keys = true })
    if not ok then
        logger.err("ContextCreator: failed to encode doc:", encoded)
        return
    end
    local fw = io.open(path, "w")
    if not fw then
        logger.err("ContextCreator: could not write", path)
        return
    end
    fw:write(encoded)
    fw:close()
end

return ContextStore
