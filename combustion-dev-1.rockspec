package = "combustion"
version = "dev-1"
source = {
    url = "https://github.com/Frityet/combustion.git"
}
description = {
    homepage = "https://github.com/Frityet/combustion",
    license = "MIT/X11"
}
dependencies = {
    "luafilesystem",
    "penlight",
    "lua-zip",
    "argparse",
    "lua >= 5.1, < 5.5",
}
build = {
    type = "builtin",

    install = {
        bin = {
            ["combust"] = "src/main.lua"
        }
    },

    modules = {
        ["executables"] = "src/executables/init.lua",
        ["executables.self-extract"] = "src/executables/self-extract.lua",
        ["utilities"] = "src/utilities.lua"
    }
}
