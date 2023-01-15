---@param prog string
---@param ... string
---@return fun(): string
local function execute(prog, ...)
    local args = {...}
    local proc = assert(io.popen(prog.." "..table.concat(args, ' '), "r"))

    return coroutine.wrap(function ()
        local out = ""
        for line in proc:lines() do
            out = out..line.."\n"
            coroutine.yield(line)
        end

        return out, proc:close()
    end)
end

local lua_basedir, ok = execute("pkg-config", "lua5.4", "--libs-only-L")():match("%-L(.*)"):gsub("/lib$", "/")
if not ok then
    error("Could not find Lua 5.4")
end

local cc do
    cc = os.getenv("CC")
    if not cc then
        cc = execute("which", "cc")()
        if cc == "" then
            cc = execute("which", "gcc")()
            if cc == "" then
                cc = execute("which", "clang")()
                if cc == "" then
                    error("No C compiler found")
                end
            end
        end
        cc = cc:gsub("\n", "")
    end
end

local os = execute("uname")():gsub("\n", "")

-- return {
--     entry = "main.lua",
--     path = {
--         "lua_modules/share/lua/5.4/",
--         "src/"
--     },
--     cpath = {
--         "lua_modules/lib/lua/5.4/",
--     },

--     lua = {
--         version     = "5.4",
--         interpreter = lua_basedir.."/bin/lua5.4",
--         compiler    = "luac5.4 -s -o $(output) $(input)",

--         --If OS is linux, use .so, otherwise use .dylib
--         runtime     = lua_basedir..(os == "Darwin" and "/lib/liblua5.4.dylib" or "/lib/liblua5.4.so"),
--     },

--     c_compiler = cc,

--     output_format = "self-extract"
-- }

return {
    entry = "main.lua",
    path = {
        "lua_modules/share/lua/5.1/",
        "src/"
    },
    cpath = {
        "lua_modules/lib/lua/5.1/",
    },

    lua = {
        version     = "JIT",
        interpreter = lua_basedir.."/bin/luajit-2.1.0-beta3",
        compiler    = lua_basedir.."/bin/luajit-2.1.0-beta3 -b -s -t raw $(input) $(output)",

        --If OS is linux, use .so, otherwise use .dylib
        runtime     = lua_basedir..(os == "Darwin" and "/lib/libluajit.dylib" or "/lib/libluajit.so"),
    },

    c_compiler = cc,

    output_format = "self-extract"
}
