return {
    entry = "main.lua",
    path = {
        "lua_modules/share/lua/5.4/",
        "src/"
    },
    cpath = {
        "lua_modules/lib/lua/5.4/",
    },

    lua = {
        version = "5.4",
        interpreter = "/usr/local/bin/lua-5.4",
        compiler = "/usr/local/bin/luac-5.4",
        runtime = "/usr/local/lib/liblua.dylib",
    },

    c_compiler = "clang",

    output_format = "self-extract"
}
