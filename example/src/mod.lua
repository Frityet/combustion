---@type LuaFileSystem
local lfs = require("lfs")
local path = require("pl.path")

local export = {}

---@alias Module { name: string, path: string }

---@param dir string
---@param ext string
---@param list Module[]
---@param base string?
function export.recursive_add_files(dir, ext, list, base)
    for file in lfs.dir(dir) do
        if file == "." or file == ".." then goto next end
        local abs_path = path.abspath(path.join(dir, file))
        if path.isfile(abs_path) and path.extension(abs_path) == ext then
            table.insert(list, { name = path.join(base or "", file), path = abs_path })
        elseif path.isdir(abs_path) then
            export.recursive_add_files(path.join(dir, file), ext, list, path.join(base or "", file))
        end

        ::next::
    end
end

return export
