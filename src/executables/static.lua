-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

local path = require("pl.path")
local directory = require("pl.dir")
local file = require("pl.file")
local tablex = require("pl.tablex")
local utilities = require("utilities")

---@param opt Combustion.BuildOptions
return function (opt)
    if not opt.c_compiler then error("No C compiler specified") end

    opt.cflags = opt.cflags or { utilities.is_gcc_like(opt.c_compiler) and "-Os" or "/O2" }

    ---@type { [string] : integer }
    local running_compiles = {}
    ---@param options { contents: string, cflags: string[]?, defines: { [string] : string }?, to: string, is_file: boolean }
    local function compile(options)
        local defines_str = ""
        for k, v in pairs(options.defines or {}) do
            v = v:gsub('"', '\\"')
            defines_str = defines_str.."-D"..k.."=\""..v.."\" "

            options.cflags[#options.cflags+1] = defines_str
        end

        --disable warnings
        options.cflags[#options.cflags+1] = utilities.is_gcc_like(opt.c_compiler) and "-w" or "/w"

        local cflags = table.concat(options.cflags or {}, " ")


        local cmd = string.format("%s %s -x c -c -o %s -", opt.c_compiler, cflags, options.to)
        if options.is_file then
            cmd = string.format("%s %s -c -o %s %s", opt.c_compiler, cflags, options.to, options.contents)
        end

        -- if posix, then fork off in order to compile
        -- if jit and jit.os ~= "Windows" then
        --     local ffi = require("ffi")
        --     ffi.cdef [[
        --         int fork(void);
        --         int execlp(const char *file, const char *arg, ...);
        --         int getpid(void);
        --     ]]

        --     local pid = ffi.C.fork()
        --     if pid == 0 then
        --         --child
        --         print("("..ffi.C.getpid()..") Compiling to "..options.to.."...")
        --         ffi.C.execlp("/bin/sh", "/bin/sh", "-c", cmd)
        --         os.exit(1)
        --     else
        --         running_compiles[options.to] = pid
        --     end

        --     return true
        -- end

        print("$ "..cmd)
        local proc = io.popen(cmd, "w")
        if not proc then return false, "Could not open pipe to "..cmd end
        if not options.is_file then
            proc:write(options.contents)
        end

        local ok, err = proc:close()
        if not ok then return false, err end

        return true
    end

    ---@param options { input: string[], flags: string[]?, to: string }
    ---@return boolean ok, string? err
    local function link(options)
        local cmd = string.format("%s %s -o %s %s", opt.linker, table.concat(options.flags or {}, " "), options.to, table.concat(options.input, " "))
        print("$ "..cmd)
        local proc = io.popen(cmd, "w")
        if not proc then return false, "Could not open pipe to "..cmd end

        local ok, err = proc:close()
        if not ok then return false, err end

        return true
    end

    local bin = path.join(opt.bin_dir, opt.name)
    local obj_dir = path.join(opt.build_dir, "obj")
    path.rmdir(obj_dir)
    file.delete(bin)
    assert(directory.makepath(obj_dir))

    --first, copy compat53 to the obj dir, needed for compiling modules
    local compat53 = require("executables.loaders.static.compat-53-c")
    assert(file.write(path.join(obj_dir, "compat-5.3.h"), compat53.header))
    assert(file.write(path.join(obj_dir, "compat-5.3.c"), compat53.source))

    local template = require("executables.loaders.static.module-template")
    local template_path = path.join(obj_dir, "module-template.c")
    assert(file.write(template_path, template))


    opt.cflags[#opt.cflags+1] = "-I"..obj_dir
    opt.cflags[#opt.cflags+1] = "-I"..opt.lua_incdir
    -- opt.cflags[#opt.cflags+1] = "-g"
    -- opt.cflags[#opt.cflags+1] = "-Og"

    ---@type string?
    local entry_symbol = nil

    require("jit.p").start("fa", "performance.log")
    ---{ [name with all the '.'s] : path }
    ---@type { [string] : { hexname: string, luac_object: string, module_object: string, module_symbol: string } }
    local modules = {}
    --compile all the modules, use the `executables.loaders.static.module-template` with different defines
    for _, module in ipairs(opt.luac_objects) do
        local cflags = tablex.copy(opt.cflags)
        local mangled_name = ("lua_%s"):format(utilities.hex_encode(module))
        local sym, symsize = utilities.bin2c(mangled_name.."_luac", file.read(module))
        local luac_objc = path.join(obj_dir, mangled_name..".luac.o")

        if module:find(opt.lua_source_dir, 1, true) == 1 then
            module = module:sub(#opt.lua_source_dir + 1)
            --remove leading slash if it exists
            if module:sub(1, 1) == "/" or module:sub(1, 1) == "\\" then module = module:sub(2) end
            if module == opt.entry then
                print("Found entry point: "..module)
                entry_symbol = mangled_name
            end
        end

        --first, compile the module into an object
        assert(compile {
            contents = sym,
            cflags = cflags,
            to = luac_objc,
            is_file = false
        })

        --the path as if it would be `require`d lua, for example `my/module.lua` would be `my.module`, and `my/module/init.lua` would also be `my.module`
        --the common base path for all files is `opt.lua_source_dir`
        local modulepath do
            local src_dir = opt.lua_source_dir
            if src_dir:sub(-1) ~= "/" then
                src_dir = src_dir .. "/"
            end

            -- Remove the lua_source_dir prefix if it exists
            if module:find(opt.lua_source_dir, 1, true) == 1 then
                module = module:sub(#opt.lua_source_dir + 1)
            end

            modulepath = module:gsub("/", "."):gsub("\\", ".")

            modulepath = modulepath:gsub("%.lua$", "")
            modulepath = modulepath:gsub("%.init$", "")

            if modulepath:sub(1, 1) == "." then modulepath = modulepath:sub(2) end
        end

        local mod_obj = path.join(obj_dir, mangled_name..".o")
        assert(compile {
            contents = template_path,
            cflags = cflags,
            to = mod_obj,
            is_file = true,

            defines = {
                ["COMBUSTION_MODULE_SYMBOL"] = mangled_name,
                ["COMBUSTION_MODULE_NAME"] = modulepath,
                ["COMBUSTION_MODULE_BYTECODE_SYMBOL"] = mangled_name.."_luac",
                ["COMBUSTION_MODULE_BYTECODE_SIZE"] = tostring(symsize)
            }
        })

        modules[modulepath] = {
            hexname = mangled_name,
            luac_object = luac_objc,
            module_object = mod_obj,
            module_symbol = mangled_name
        }
    end
    require("jit.p").stop()

    if not entry_symbol then error("Could not find entry point "..opt.entry) end

    --Compile the entry point
    --write it to a file in the obj dir, we want it to be a file so that `__FILE__` and `__LINE__` work
    local entry_source_path = path.join(obj_dir, "combustion-entry.c")
    assert(file.write(entry_source_path, require("executables.loaders.static.loader")))

    --first, we need to make the module list, in the format of `{ "name", module_symbol }, { "name2", module_symbol2 }, ...`

    local module_list = ""
    for pathname, module in pairs(modules) do
        module_list = module_list..string.format('{ "%s", MODULE(%s) }, ', pathname, module.hexname)
    end

    local module_definition_template = "extern DECLARE_MODULE(%s);"
    local module_definitions = ""
    for _, module in pairs(modules) do
        module_definitions = module_definitions..string.format(module_definition_template, module.hexname).." "
    end

    local entry_path = path.join(obj_dir, "combustion-entry.o")
    print("Compiling with entry "..opt.entry.." into "..entry_path..", entry symbol: "..entry_symbol)
    local cflags = tablex.copy(opt.cflags)
    cflags[#cflags+1] = "-I"..obj_dir
    compile {
        contents = entry_source_path,
        cflags = cflags,
        to = entry_path,
        is_file = true,

        defines = {
            ["COMBUSTION_ENTRY"] = entry_symbol,
            ["COMBUSTION_MODULE_LIST"] = module_list,
            ["COMBUSTION_MODULE_DEFINITIONS"] = module_definitions
        }
    }

    local objects = {}
    for _, module in pairs(modules) do
        objects[#objects+1] = module.luac_object
        objects[#objects+1] = module.module_object
    end

    --link with lua or luajit depending on the luac version
    local ldflags = { "-L"..opt.lua_libdir, (opt.lua.version == "JIT" and "-lluajit" or "-llua") }
    for _, lib in ipairs(opt.link or {}) do
        ldflags[#ldflags+1] = "-l"..lib
    end

    -- if jit and jit.os ~= "Windows" then
    --     local ffi = require("ffi")
    --     ffi.cdef [[
    --         int waitpid(int pid, int *status, int options);
    --         int kill(int pid, int sig);
    --     ]]

    --     for module, pid in pairs(running_compiles) do
    --         print("Waiting for "..module.." to compile ("..pid..")...")
    --         local status = ffi.new("int[1]")
    --         ffi.C.waitpid(pid, status, 0)

    --         if status[0] ~= 0 then
    --             error("Child compiler process "..pid.." exited with status "..status[0])
    --         end

    --         --after we are done, kill the child process
    --         local SIGKILL = 9
    --         ffi.C.kill(pid, SIGKILL)
    --     end
    -- end

    print("Linking...")
    assert(link {
        input = { entry_path, unpack(objects) },
        to = bin,
        flags = ldflags
    })

    --copy shared objects
end
