-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

local export = {}

---@alias Platform "Windows"|"Linux"|"OSX"|string

---@alias LuaVersion "5.1"|"5.2"|"5.3"|"5.4"|"JIT"|string

---@class Lua
---@field version LuaVersion
---@field interpreter string
---@field compiler string

local stringx = require("pl.stringx")
local path = require("pl.path")
string.buffer = require("string.buffer")

---@type LuaFileSystem
local lfs = require("lfs")

---@type { [string] : FunctionArgument }
export.programs = setmetatable({}, {
    __index = function(_, prog)
        local exec = prog
        local function arg(x)
            if x == nil then
                local proc, err = io.popen(exec, "r")
                if not proc then return nil, err end
                local contents = proc:read("*a")
                proc:close()
                contents = stringx.strip(contents)
                return contents
            else
                exec = exec.." "..tostring(x)
                return arg
            end
        end

        return arg
    end
})

---@type Platform
export.platform = "Other"
do
    if jit then
        export.platform = require("ffi").os
    else
        if package.config:sub(1, 1) == '\\' then
            export.platform = "Windows"
        else
            --uname time
            local uname, err = export.programs["uname"]()
            if not uname then
                export.platform = "Other"
                warning("Could not determine platform: "..err)
            else
                if uname == "Linux" then
                    export.platform = "Linux"
                elseif uname == "Darwin" then
                    export.platform = "OSX"
                else
                    export.platform = uname
                end
            end
        end
    end
end

---@param name string
---@return string? executable, string? err
function export.find_executable(name)
    local path = os.getenv("PATH")
    if not path then return nil, "Could not find PATH environment variable" end
    if export.platform == "Windows" then
        local paths = stringx.split(path, ";")
        for _, path in ipairs(paths) do
            local file = path.."\\"..name..".exe"
            if lfs.attributes(file, "mode") == "file" then return file
            else return nil, "Could not find executable "..name end
        end
    else
        --Use "which"
        local res, err = export.programs["which"](name)()
        if res then return res
        else return nil, err end
    end
end

---@alias FunctionArgument (fun(str: string): FunctionArgument) | fun(): string?, string?

---@return Lua? info, string? err
function export.find_lua()
    ---@type Lua
    ---@diagnostic disable-next-line: missing-fields
    local luainfo = {}

    for _, name in ipairs { "", "5.1", "5.2", "5.3", "5.4", "jit" } do
        local lua, err = export.find_executable("lua"..name)
        if lua then
            luainfo.interpreter = lua
            if name == "" then
                local ver_str, err = export.programs[luainfo.interpreter] "-v"()
                if not ver_str then return nil, err end

                local ver = ver_str:match("Lua (%d+%.%d+)")
                if ver and ver == "5.1" or ver == "5.2" or ver == "5.3" or ver == "5.4" then
                    luainfo.version = ver
                else
                    luainfo.version = ver_str
                end
            else
                luainfo.version = name --[[@as LuaVersion]]
            end
            break
        end
    end

    if not luainfo.interpreter then return nil, "Could not find Lua interpreter" end

    luainfo.interpreter = export.find_executable(luainfo.interpreter) --[[@as string]]

    if luainfo.version == "JIT" then
        luainfo.compiler = luainfo.interpreter
    else
        local luac, err = export.find_executable("luac"..luainfo.version)
        if not luac then return nil, err end
        luainfo.compiler = luac
    end

    return luainfo, nil
end


---@param lua string
---@return LuaVersion? version, string? err
function export.verify_lua(lua)
    local verstr, err = export.programs[lua] "-v"()
    if not verstr then return nil, err end

    local version = verstr:match("Lua (%d+%.%d+)")
    if not version then
        version = verstr:match("LuaJIT (%d+%.%d+)")
        if not version then version = verstr
        else version = "JIT" end
    end

    return version, nil
end

---@param dir string
---@param filetype string
---@return string[]? files, string? err
function export.find(dir, filetype)
    local files = {}
    for dirent in lfs.dir(dir) do
        if dirent == "." or dirent == ".." then goto next end
        local relpath = path.join(dir, dirent)

        if path.isfile(relpath) and path.extension(relpath) == filetype then
            table.insert(files, relpath)
        elseif path.isdir(relpath) then
            local subfiles, err = export.find(relpath, filetype)
            if not subfiles then return nil, err end
            for _, file in ipairs(subfiles) do
                table.insert(files, file)
            end
        end

        ::next::
    end

    return files, nil
end


---@param cc string
---@return boolean
function export.is_gcc_like(cc)
    return not not export.programs[cc] "--version"()
end

---@param symname string
---@param data string
---@param size number?
---@return string, number size
function export.bin2c(symname, data, size)
    size = size or #data
    local buf = string.buffer.new((size * 8) + string.len("#include <stddef.h>\n\nconst unsigned char "..symname.."[] = {\n};\nconst size_t "..symname.."_size = "..size..";\n"))

    buf:putf("#include <stddef.h>\n\nconst unsigned char %s[] = {\n", symname)
    for i = 1, #data do
        buf:putf("%d,", data:byte(i))
        if i % 16 == 0 then buf:putf("\n") end
    end
    buf:putf("\n};\nconst size_t %s_size = %d;\n", symname, size)

    return buf:tostring(), size
end

---Bin2C that works on non-luajit, so no `string.buffer`
---@param symname string
---@param data string
---@param size number?
---@return string
function export.bin2c_portable(symname, data, size)
    size = size or #data
    local buf = {}

    table.insert(buf, "#include <stddef.h>\n\nconst unsigned char "..symname.."[] = {\n")
    for i = 1, #data do
        table.insert(buf, data:byte(i)..",")
        if i % 16 == 0 then table.insert(buf, "\n") end
    end
    table.insert(buf, "\n};\nconst size_t "..symname.."_size = "..size..";\n")

    return table.concat(buf)
end

---@brief hash string
---@param str string
---@return number
function export.hash_portable(str)
    -- see: https://stackoverflow.com/a/7666577
    local hash = 5381
    for i = 1, #str do
        hash = (bit.lshift(hash, 5) + hash) + string.byte(string.sub(str, i, i))
    end
    return hash
end

---@brief hash string
---@param str string
---@return number
function export.hash(str)
    local ffi = require("ffi")
    -- see: https://stackoverflow.com/a/7666577
    local hash = ffi.new("uint32_t", 5381)
    for i = 1, #str do
---@diagnostic disable-next-line: param-type-mismatch
        hash = (bit.lshift(hash, 5) + hash) + string.byte(string.sub(str, i, i))
    end
    return assert(tonumber(hash))
end

---@brief unhash number
---@param hash number
---@return string
function export.unhash_portable(hash)
    local str = ""
    while hash > 0 do
        str = str..string.char(hash % 256)
        hash = math.floor(hash / 256)
    end
    return str
end

---Turns a string into a series of hex bytes, i,e "Hello" -> "48656c6c6f" as a string
---@param string string
---@return string
function export.hex_encode(string)
    local hex = ""
    for i = 1, #string do
        hex = hex..string.format("%02X", string:byte(i))
    end
    return hex
end

return export
