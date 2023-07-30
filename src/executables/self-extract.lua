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


---Used to seperate the loader code and the zip file
local DATA_MAGIC = "!@!_COMBUSTION_MAGIC_!@!"
local DATA_MAGIC_NUMBER = 0xB00B135

---@param opt Combustion.BuildOptions
return function (opt)
    if not opt.c_compiler then error("No C compiler specified") end

    opt.c_flags = opt.c_flags or { utilities.is_gcc_like(opt.c_compiler) and "-Og" or "/O2", "-g" }


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

    ---@class LinkResult
    ---@field private libs string[]?
    ---@field to fun(self, to: string): boolean, string?
    ---@field with fun(self, libs: string[]?): LinkResult

    ---@param files string[]
    ---@return LinkResult
    local function link(files)
        return {
            with = function(self, libs)
                self.libs = libs
                return self
            end,

            to = function (self, to)
                local linkercmd = utilities.programs[assert(opt.linker)]
                for _, file in ipairs(files) do
                    linkercmd = linkercmd(file)
                end

                linkercmd = linkercmd "-o" (to) "-g" "-L" (opt.lib_dir or "./")
                if self.libs ~= nil then
                    linkercmd = linkercmd("-l"..table.concat(self.libs, " -l"))
                end

                local out, err = linkercmd()
                print(string.format("$ %s %s -o %s %s", opt.linker, table.concat(files, " "), to, "-l"..table.concat(self.libs or {}, " -l")))
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
    --[[@cast size integer]]
    --[[@cast contents string]]

    --First, we need to compile miniz by copying the header into the "obj" directory and then compiling the source file
    local miniz = require("executables.loaders.self-extract.miniz")
    local miniz_header_path = path.join(obj_dir, "miniz.h")

    ok = file.write(miniz_header_path, miniz.header)
    if not ok then error("Could not write miniz header to "..miniz_header_path) end

    table.insert(objects, path.join(obj_dir, "miniz.o"))
    ok, err = compile(miniz.source, "-I"..obj_dir, table.unpack(opt.c_flags))
                :to(objects[1])
    if not ok then error(err) end

    --Now, we need to compile the self-extracting executable "loader"
    local loader_source = require("executables.loaders.self-extract.loader")
    table.insert(objects, path.join(obj_dir, "loader.o"))
    ok, err = compile(loader_source, table.unpack(opt.c_flags),
                      "-g",
                      "-I"..obj_dir,
                      "-DCOMBUSTION_ENTRY=\""..opt.entry.."\"",
                      "-DCOMBUSTION_DATA_MAGIC=\""..DATA_MAGIC.."\"",
                      "-DCOMBUSTION_DATA_MAGIC_NUMBER="..DATA_MAGIC_NUMBER,
                      ((opt.graphical and utilities.platform == "Windows") and "-DWIN32_GRAPHICAL" or ""))
              :to(objects[2])
    if not ok then error(err) end


    --Now, we need to link the object files together
    ok, err = link(objects):with(opt.link):to(bin)

    --Now we need to append the zip file to the end of the executable
    local bin_f, err = io.open(bin, "ab")
    if not bin_f then error(err) end

    local dbg_s = DATA_MAGIC
    --First, append the magic numbers
    bin_f:write(DATA_MAGIC)

    --write the magic numbers right after the magic string, this is required becuase the `DATA_MAGIC` might be
    --in the .strings or .rodata section, so if we search the binary we would just the literal in that section
    --instead of the actual magic number
    local n = DATA_MAGIC_NUMBER
    for _ = 1, 4 do
        bin_f:write(string.char(n % 256))
        n = math.floor(n / 256)
    end
    print("Magic number bytes: ")
    for i = 1, #dbg_s do
        io.write(string.format(" %X", dbg_s:sub(i, i):byte()))
    end

    --Now the length of the zip file, intentionally just the numbers not converted to a string into 8 bytes
    --We can't use string.pack because LuaJIT doesn't support it
    print(string.format("\nAdding zip of size %d (hex: %X)", size, size))
    for _ = 1, 8 do
        bin_f:write(string.char(size % 256))
        size = math.floor(size / 256)
    end

    --Finally the zip file

    bin_f:write(contents)

    bin_f:close()

    path.rmdir(obj_dir)
end
