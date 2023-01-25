package = "combustion"
version = "dev-1"
source = {
    url = "git://https://github.com/Frityet/combustion"
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
        ["executables.package"] = "src/executables/package/init.lua",
        ["executables.package.osx"] = "src/executables/package/osx.lua",
        ["executables.package.linux"] = "src/executables/package/linux.lua",
        ["executables.package.windows"] = "src/executables/package/windows.lua",



        ["utilities"] = "src/utilities.lua"
    }
}
