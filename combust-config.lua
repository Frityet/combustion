return {
    entry = "src/main.lua",
    path = {
        "src/",
        "lua_modules/share/lua/5.4/"
    },
    cpath = {
        "lua_modules/lib/lua/5.4/",
    },

    lua = {
        version = "5.4",
        interpreter = "/usr/local/bin/lua-5.4",
        compiler = "/usr/local/bin/luac-5.4",
        runtime = "/usr/local/lib/liblua.a",
    },

    output_format = "binary"
}
