# Combustion - Compile Lua projects into a single binary

Combustion is a tool for compiling Lua projects into a single binary.
Combustion works with *any* interpreter and language version, as long as the interpreter supports the `-e` flag
It also packs in C .dylib/.so/.dll dependencies, if the directory that contains them is specified in the combust-config

## Usage

- Create a file called `combust-config.lua` in the root of your project
- Add this template

> ```lua
> ---Execute a command and return a coroutine that yields each line of output
> ---@param prog string
> ---@param ... string
> ---@return fun(): string
> local function execute(prog, ...)
>     local args = {...}
>     local proc = assert(io.popen(prog.." "..table.concat(args, ' '), "r"))
>
>     return coroutine.wrap(function ()
>         local out = ""
>         for line in proc:lines() do
>             out = out..line.."\n"
>             coroutine.yield(line)
>         end
>
>         return out, proc:close()
>     end)
> end
>
> local prefix = os.getenv("PREFIX") or "/usr/local"
> local libzip_basedir = os.getenv("LIBZIP_DIR") or prefix
> local lua_basedir = os.getenv("LUA_DIR") or prefix
>
> local osname = execute("uname")():gsub("\n", "")
>
> --LuaJIT
> return {
>     --The entry script of the program, must be relative to the values in `path`
>     entry = "main.lua",
>
>     --Lua module search paths, will recursively search for .lua files
>     path = {
>         "lua_modules/share/lua/5.1/",
>         "src/"
>     },
>
>     --Lua module cpath, will recursively search for .so files
>     cpath = {
>         "lua_modules/lib/lua/5.1/",
>     },
>
>     lua = {
>         version     = "JIT",
>         --Path to the interpreter, will be copied, not executed
>         interpreter = lua_basedir.."/bin/luajit",
>
>         --Command to compile a Lua file to bytecode, $(input) is the .lua file, $(output) is the output bytecode
>         compiler    = lua_basedir.."/bin/luajit -b -s -t raw $(input) $(output)",
>
>         --liblua, libluajit, etc
>         runtime     = lua_basedir..(osname == "Darwin" and "/lib/libluajit.dylib" or "/lib/libluajit.so"),
>     },
>
>     c = {
>         compiler = os.getenv("CC") or "cc",
>
>         --Additional flags to pass to the compiler
>         flags = {
>
>         },
>
>         linker = os.getenv("CC") or "cc",
>
>         --Additional flags to pass to the linker
>         ldflags = {
>             "-flto"
>         }
>     },
>
>     libzip = {
>         include = (libzip_basedir or prefix).."/include",
>         lib     = (libzip_basedir or prefix).."/lib",
>     },
>
>     output_format = "self-extract"
> }
> ```

- Run `combust` in the root of your project and wait for it to build into `build/bin`

## Installation

`luarocks install --server=https://luarocks.org/dev combustion`
