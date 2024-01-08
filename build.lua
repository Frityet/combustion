#!/usr/bin/env lua

local TEST_DIR = "build-test"

local function execute(...)
    local ok, err = os.execute(table.concat({...}, " "))

    if not ok then
        error(err)
    end

    return ok
end

execute("rm", "-rf", TEST_DIR)

print("Copying contents of self-extract...")
do
    ---@type string
    local selfextract do
        local f = assert(io.open("src/combustion/executables/loaders/self-extract/self-extract.c", "r"))
        selfextract = f:read("*a")
        f:close()
    end

    local selfextract_lua = assert(io.open("src/combustion/executables/loaders/self-extract/loader.lua", "w+"))
    selfextract_lua:write(string.format("return [[\n%s\n]]", selfextract))
    selfextract_lua:close()
end

print("Copying contents of static...")
do
    ---@type string
    local selfextract do
        local f = assert(io.open("src/combustion/executables/loaders/static/static.c", "r"))
        selfextract = f:read("*a")
        f:close()
    end

    local selfextract_lua = assert(io.open("src/combustion/executables/loaders/static/loader.lua", "w+"))
    selfextract_lua:write(string.format("return [[\n%s\n]]", selfextract))
    selfextract_lua:close()

    ---@type string
    local template do
        local f = assert(io.open("src/combustion/executables/loaders/static/module-template.c", "r"))
        template = f:read("*a")
        f:close()
    end

    local template_lua = assert(io.open("src/combustion/executables/loaders/static/module-template.lua", "w+"))
    template_lua:write(string.format("return [[\n%s\n]]", template))
    template_lua:close()
end

print("Building executables...")
execute("luarocks", "--lua-version=5.1", "init")
execute("./luarocks", "make")

local only_copy = arg[1] == "--only-copy"

if not only_copy then
    execute("./lua_modules/bin/combust", "-S", "src", "lua_modules/share/lua/5.1/", "-Llua_modules/lib/lua/5.1", "--lua=/usr/local/bin/luajit", "-v", "-o", "build", "--name=test")
end

if not only_copy and arg[1] == "test" then
    print("Testing binary")
    execute("./build/bin/test "..table.concat(arg, " ").." -o build/test --name=test")
end
