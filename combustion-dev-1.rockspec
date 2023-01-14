package = "combustion"
version = "dev-1"
source = {
    url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
    homepage = "*** please enter a project homepage ***",
    license = "MIT/X11"
}
dependencies = {
    "luafilesystem",
    "penlight",
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

    }
}
