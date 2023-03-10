#!/usr/bin/env luajit

local TEST_DIR = "build-test"

os.execute("rm -rf "..TEST_DIR)

print("Copying contents of self-extract...")
---@type string
local selfextract do
    local f = assert(io.open("src/executables/loaders/self-extract/self-extract.c", "r"))
    selfextract = f:read("*a")
    f:close()
end

local selfextract_lua = assert(io.open("src/executables/loaders/self-extract/loader.lua", "w+"))
selfextract_lua:write(string.format("return [[\n%s\n]]", selfextract))
selfextract_lua:close()

print("Building executables...")
os.execute("./luarocks --lua-version=5.1 init")
os.execute("./luarocks make")

os.execute("./lua_modules/bin/combust "..table.concat(arg, " ").." -o build --name=test")

print("Testing binary")
os.execute("./build/bin/test "..table.concat(arg, " ").." -o build-test --name=test")
