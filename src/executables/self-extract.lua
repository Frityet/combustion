-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

local path = require("pl.path")
local directory = require("pl.dir")
local file = require("pl.file")
local utilities = require("utilities")

---@type fun(directory: string): string?, integer?, string?
local zip = require("zip")

---@param opt Combustion.BuildOptions
return function (opt)
    if not opt.c_compiler then error("No C compiler specified") end

    opt.c_flags = opt.c_flags or { utilities.is_gcc_like(opt.c_compiler) and "-Os" or "/O2" }


    ---@param contents string
    ---@param ... string
    ---@return { to: fun(self, to: string): boolean, string? }
    local function compile(contents, ...)
        local cflags = table.concat({...}, " ")
        return {
            to = function (_, to)
                local cmd = string.format("%s %s -x c -c -o %s -", opt.c_compiler, cflags, to)
                print("$ "..cmd)
                local proc = io.popen(cmd, "w")
                if not proc then return false, "Could not open pipe to "..cmd end
                proc:write(contents)

                local ok, err = proc:close()
                if not ok then return false, err end

                return true
            end
        }
    end

    ---@param files string[]
    ---@return { to: fun(self, to: string): boolean, string? }
    local function link(files)
        return {
            to = function (_, to)
                local result = utilities.programs[opt.linker]
                for _, file in ipairs(files) do
                    result = result(file)
                end

                local out, err = result "-o" (to)()
                print(string.format("$ %s %s -o %s", opt.linker, table.concat(files, " "), to))
                if not out then return false, err end
                return true
            end
        }
    end

    local bin = path.join(opt.bin_dir, opt.name)
    local obj_dir = path.join(opt.build_dir, "obj")
    path.rmdir(obj_dir)
    file.delete(bin)
    local ok, err = file.copy(opt.lua.interpreter, bin)
    if not ok then error(err) end

    --Copy the lua interpreter to the bin directory
    file.copy(opt.lua.interpreter, path.join(opt.bin_dir, "lua"..(utilities.platform == "Windows" and ".exe" or "")))

    local ok, err = directory.makepath(obj_dir)
    if not ok then error(err) end

    ok, err = directory.makepath(opt.bin_dir)
    if not ok then error(err) end

    ---@type string[]
    local objects = {}

    local contents, size, err = zip(opt.build_dir)
    if not contents then error(err) end

    --First, we need to compile miniz by copying the header into the "obj" directory and then compiling the source file
    local miniz = require("executables.loaders.self-extract.miniz")
    local miniz_header_path = path.join(obj_dir, "miniz.h")

    ok  = file.write(miniz_header_path, miniz.header)
    if not ok then error("Could not write miniz header to "..miniz_header_path) end

    table.insert(objects, path.join(obj_dir, "miniz.o"))
    ok, err = compile(miniz.source, "-I"..obj_dir, table.unpack(opt.c_flags))
                :to(objects[1])
    if not ok then error(err) end

    --Now, we need to compile the self-extracting executable "loader"
    local loader_source = require("executables.loaders.self-extract.loader")
    table.insert(objects, path.join(obj_dir, "loader.o"))
    ok, err = compile(loader_source, table.unpack(opt.c_flags),
                      "-I"..obj_dir,
                      "-DCOMBUSTION_ENTRY=\""..opt.entry.."\"",
                      ((opt.graphical and utilities.platform == "Windows") and "-DWIN32_GRAPHICAL" or ""))
              :to(objects[2])
    if not ok then error(err) end

    --Finally, we need to compile the bin2c result of the zip file
    local data = utilities.bin2c("zipfile", contents, size)
    table.insert(objects, path.join(obj_dir, "zipfile.o"))
    ok, err = compile(data, "-I"..obj_dir, table.unpack(opt.c_flags))
              :to(objects[3])
    if not ok then error(err) end

    --Now, we need to link the object files together
    ok, err = link(objects)
              :to(bin)

    path.rmdir(obj_dir)
end
