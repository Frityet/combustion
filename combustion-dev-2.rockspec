---@diagnostic disable: lowercase-global
package = "combustion"
version = "dev-2"
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
    "argparse",
    "lua ~> 5.1",
}
build = {
    type = "builtin",

    install = {
        bin = {
            ["combust"] = "src/main.lua"
        }
    },

    modules = {
        ["combustion.utilities"] = "src/utilities.lua",
        ["combustion.compile"] = "src/compile.lua",

        ["combustion.executables"] = "src/executables/init.lua",

        ["combustion.executables.self-extract"] = "src/executables/self-extract.lua",
        ["combustion.executables.loaders.self-extract.loader"] = "src/executables/loaders/self-extract/loader.lua",
        ["combustion.executables.loaders.self-extract.miniz"] = "src/executables/loaders/self-extract/miniz.lua",

        ["combustion.executables.static"] = "src/executables/static.lua",
        ["combustion.executables.loaders.static.loader"] = "src/executables/loaders/static/loader.lua",
        ["combustion.executables.loaders.static.module-template"] = "src/executables/loaders/static/module-template.lua",
        ["combustion.executables.loaders.static.compat-53-c"] = "src/executables/loaders/static/compat-53-c.lua",
        ["combustion.zip"] = {
            sources = { "src/miniz.c", "src/zip.c" },
            incdirs = { "src/" }
        }
    }
}
