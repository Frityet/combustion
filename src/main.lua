-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT


---Command line arguments
---@class Combustion.Options
---@field type "self-extract"|"app"|"directory"
---@field output_dir string
---@field source_dirs string[]
---@field library_dirs string[]
---@field link string[]
---@field lua_incdir string?
---@field lua_libdir string?
---@field resources_dirs string[]
---@field lua string?
---@field luac string?
---@field entry string
---@field name string
---@field c_compiler string
---@field cflags string[]?
---@field ldflags string[]?
---@field linker string
---@field verbose boolean
---@field graphical boolean

local argparse = require("argparse")
local pretty = require("pl.pretty")
local path = require("pl.path")
local tablex = require("pl.tablex")

local utilities = require("utilities")
local compile = require("compile")
local executables = require("executables")

local lprint, lerror = print, error
unpack = unpack or table.unpack


---Regular print can't print tables, and pprint has quotations around strings, so this is the best solution
---@param ... any
function print(...)
    local a = {...}
    if #a < 1 then return
    elseif #a == 1 then
        if type(a[1]) ~= "table" then lprint(tostring(a[1])) else print(pretty.write(a[1])) end
    else print(pretty.write(a)) end
end

function error(msg, i)
    if type(msg) == "table" then msg = pretty.write(msg)
    elseif type(msg) ~= "string" then msg = tostring(msg) end
    return lerror("\n\x1b[31m"..msg.."\x1b[0m", i)
end

---@diagnostic disable-next-line: lowercase-global
function warning(msg)
    if type(msg) == "table" then msg = pretty.write(msg)
    elseif type(msg) ~= "string" then msg = tostring(msg) end
    return lprint("\n\x1b[33m"..msg.."\x1b[0m")
end

local parser = argparse() {
    name = "combust",
    description = "Pack your lua project, and all dependencies into a single self contained file.",
    epilog = "https://github.com/Frityet/combustion"
}

parser:add_complete()

local t_choices = tablex.keys(require("executables"))
if t_choices[1] == "source" or t_choices[1] == "header" then error("ERROR ERROR ERROR", t_choices) end

parser:option("-t --type", "The type of project to pack.")
        :args(1)
        :choices(t_choices)
        :default "self-extract"


--Options
parser:option("-o --output-dir", "The output directory to write to.")
        :args(1)
        :default "build"
        :convert(path.abspath)

parser:option("-S --source-dirs", "The source directories to pack.")
        :args "+"
        :default "."
        :convert(function (f)
            if not path.isdir(f) then error("Source directory "..f.." does not exist.") end
            return path.abspath(f)
        end)

parser:option("-L --library-dirs", "Locations of C libraries")
        :args "+"
        :convert(function (f)
            if not path.isdir(f) then error("Library directory "..f.." does not exist.") end
            return path.abspath(f)
        end)

parser:option("-l --link", "Libraries to link with")
        :args "+"
        :default { "c", "m" }

parser:option("--lua-incdir", "Location of lua headers (required for `static` build)")
        :args(1)
        :convert(function (f)
            if not path.isdir(f) then error("Lua include directory "..f.." does not exist.") end
            return path.abspath(f)
        end)

parser:option("--lua-libdir", "Location of liblua (required for `static` build)")
        :args(1)
        :convert(function (f)
            if not path.isdir(f) then error("Lua library directory "..f.." does not exist.") end
            return path.abspath(f)
        end)


parser:option("-R --resource-dirs", "Additional resources to pack.")
        :args "+"
        :convert(function (f)
            if not path.isdir(f) then error("Resource directory "..f.." does not exist.") end
            return path.abspath(f)
        end)

parser:option("--lua", "Path to the lua executable")
        :args(1)
        :default(utilities.find_lua().interpreter)
        :convert(function (f)
            if not path.isfile(f) then error("Lua executable "..f.." does not exist.") end
            local lua, err = utilities.verify_lua(f)
            if not lua then error(err) end

            return path.abspath(f)
        end)

parser:option("--luac", "Path to the lua compiler, must be compatable with the lua executable.")
        :args(1)
        :default("<lua>")
        :convert(function (f)
            if f == "<lua>" then return f end
            if not path.isfile(f) then error("Lua compiler "..f.." does not exist.") end
            local lua, err = utilities.verify_lua(f)
            if not lua then error(err) end

            return path.abspath(f)
        end)

parser:option("--c-compiler", "C compiler to use.")
        :args(1)
        :default((function ()
            local cc = os.getenv("CC")
            if not cc then
                local cc, err = utilities.find_executable("cc")
                if not cc then
                    for _, name in ipairs { "gcc", "clang" } do
                        cc, err = utilities.find_executable(name)
                        if cc then break end
                    end
                end
            end

            if not cc then
                warning("No C compiler found. Some features may not work.")
            else
                cc = utilities.find_executable(cc)
            end

            return cc
        end)())
        :convert(function (f)
            local cc, err = utilities.find_executable(f)
            if not cc then error(err) end
            return cc
        end)

parser:option("--cflags", "Flags to pass to the C compiler.")
        :args "+"

parser:option("--linker", "Linker to use.")
        :args(1)
        :default "<c-compiler>"

parser:option("--ldflags", "Flags to pass to the linker.")
        :args "+"
        :default { "-flto" }


parser:option("-e --entry", "The entry point of the project.")
        :args(1)
        :default "main.lua"


parser:option("-n --name", "The name of the project.")
        :args(1)
        :default "<entry>"

parser:flag("--graphical", "(Windows only) Create a application which does not spawn a console window")
        :default(false)

parser:flag("-v --verbose", "Print verbose output.")
        :default(false)

---@type Combustion.Options
local cli_opts = parser:parse()

if not cli_opts.verbose then
    print = function (...) end
end

local opts = compile(cli_opts)

print("Options:")
print(opts)

executables[cli_opts.type](opts)

print("\x1b[32mSuccess!\x1b[0m")
