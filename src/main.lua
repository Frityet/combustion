-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

---@alias DownloadOptions "cache"|"nocache"
---Command line arguments
---@class Combustion.Options
---@field type "self-extract"|"app"|"directory"
---@field output_dir string
---@field sources string[]
---@field library_dir string[]
---@field lua string?
---@field luac string?
---@field entry string
---@field name string
---@field c_compiler string
---@field linker string
---@field download_cc DownloadOptions
---@field download_lua DownloadOptions
---@field verbose boolean


---@type argparse
local argparse = require("argparse")
local pretty = require("pl.pretty")

local utilities = require("utilities")
local compile = require("compile")
local executables = require("executables")

local lprint, lerror = print, error


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

local function warning(msg)
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

parser:argument("type", "The type of project to pack.")
        :args(1)
        :choices {
            "self-extract",
            "app",
            "directory"
        }
        :default "self-extract"

--Options
parser:option("-o --output-dir", "The output directory to write to.")
        :args(1)
        :default "build"

parser:option("-s --sources", "The source directory to pack.")
        :args "+"
        :default "."

parser:option("-L --library-dir", "Location of C libraries")
        :args "+"

parser:option("-r --resources", "Additional resources to pack.")
        :args "+"

parser:option("--lua", "Path to the lua executable")
        :args(1)
        :default(utilities.find_lua().interpreter)

parser:option("--luac", "Path to the lua compiler, must be compatable with the lua executable.")
        :args(1)
        :default(utilities.find_lua().compiler)

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

            return cc
        end)())

parser:option("--linker", "Linker to use.")
        :args(1)
        :default "<C Compiler>"

parser:option("-e --entry", "The entry point of the project.")
        :args(1)
        :default "main.lua"

parser:option("-n --name", "The name of the project.")
        :args(1)
        :default "combust"

parser:option("--download-lua", "Downloads lua based off --lua-version")
        :args(1)
        :choices {
            "no-cache",
            "cache",
        }
        :default "cache"

parser:option("--download-cc", "Downloads tcc for compiling the loader")
        :args(1)
        :choices {
            "no-cache",
            "cache",
        }
        :default "cache"


parser:flag("-v --verbose", "Print verbose output.")
        :default(false)

---@type Combustion.Options
local cli_opts = parser:parse()

local opts, err = compile(cli_opts)
if not opts then error(err) end

if cli_opts.verbose then
    print("Options:")
    print(opts)
end

local success, err = executables[cli_opts.type](opts)
if not success then error(err) end

print("\x1b[32mSuccess!\x1b[0m")
