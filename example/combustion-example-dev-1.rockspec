package = "combustion-example"
version = "dev-1"
source = {
   url = "git+https://github.com/Frityet/combustion.git"
}
description = {
   homepage = "https://github.com/Frityet/combustion",
   license = "MIT/X11"
}
dependencies = {
   "lua ~> 5.4",
   "luafilesystem",
   "penlight",
   "inspect"
}
build = {
   type = "builtin",

   install = {
      bin = {
         ["example"] = "src/main.lua"
      }
   },

   modules = {
      ["mod"] = "src/mod.lua"
   }
}
