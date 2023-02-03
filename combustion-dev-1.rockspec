package = "combustion"
version = "dev-1"
source = {
    url = "git://github.com/Frityet/combustion"
}
description = {
    summary = "Tool to pack any lua project (including dependencies) into a single executable",
    detailed = [[
        Combustion is a tool to pack any lua project (including dependencies) into a single executable.
        It can be used to create a single executable for your lua project, or to create a self-extracting archive.

        Just define a `combust-config.lua` in the root of your project (example in repo) and run the combust executable!
    ]],
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
--        ["executables.package"] = "src/executables/package/init.lua",
--        ["executables.package.osx"] = "src/executables/package/osx.lua",
--        ["executables.package.linux"] = "src/executables/package/linux.lua",
--        ["executables.package.windows"] = "src/executables/package/windows.lua",



        ["utilities"] = "src/utilities.lua"
    }
}
