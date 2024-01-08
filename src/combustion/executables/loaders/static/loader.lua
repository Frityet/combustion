return [[
/**
 * Copyright (c) 2023 Amrit Bhogal
 *
 * This software is released under the MIT License.
 * https://opensource.org/licenses/MIT
 */

#include <stdbool.h>
#include <time.h>

#include "compat-5.3.h"

//Just here for intellisense, it will be replaced by the build script
#if !defined(COMBUSTION_ENTRY)
#   define COMBUSTION_ENTRY ERROR_COMBUSTION_ENTRY_NOT_DEFINED
#   define COMBUSTION_MODULE_DEFINITIONS
#   define COMBUSTION_MODULE_LIST { "", ERROR_COMBUSTION_MODULE_LIST_NOT_DEFINED },
static int ERROR_COMBUSTION_MODULE_LIST_NOT_DEFINED(lua_State *lua)
{
    return 0;
}
#endif

#define _EVAL(x) x
#define EVAL(...) _EVAL(__VA_ARGS__)

#define CONCAT(x, y) EVAL(x##y)
#define _STRINGIFY(x) #x
#define STRINGIFY(...) _STRINGIFY(__VA_ARGS__)

#define MODULE(x) CONCAT($internal_module$_, x)
#define DECLARE_MODULE(x) __attribute__((used)) int MODULE(x)(lua_State *lua)

static bool debug_output;
static void debug_f(const char *fmt, ...)
{
    if (!debug_output)
        return;
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}
#define debug(fmt, ...) do { debug_f("["__FILE__":"STRINGIFY(__LINE__)"] " fmt __VA_OPT__(,) __VA_ARGS__); } while (0)

static void perror_f(lua_State *lua, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    static char buf[1024] = {0};
    vsnprintf(buf, 1024, fmt, args);
    va_end(args);

    if (lua != NULL)
        luaL_error(lua, "%s: %s", buf, strerror(errno));
    else
        perror(buf);
}
#define error(lua, fmt, ...) do { perror_f(lua, "["__FILE__":"STRINGIFY(__LINE__)"] " fmt __VA_OPT__(,) __VA_ARGS__); exit(1); } while (0)

COMBUSTION_MODULE_DEFINITIONS
static luaL_Reg MODULES[] = {
    COMBUSTION_MODULE_LIST
    {0}
};

static int internal_module_searcher(lua_State *lua)
{
    size_t nlen = 0;
    const char *name = luaL_checklstring(lua, 1, &nlen);
    const luaL_Reg *module = MODULES;
    for (; module->name; module++) {
        if (strncmp(module->name, name, nlen) == 0) {
            debug("Found module %s (match %s)\n", module->name, name);
            lua_pushcfunction(lua, module->func);
            return 1;
        }
    }

    return 0;
}

static struct Arguments {
    const char  *program_name,
                **arguments;
    size_t      count;
} arguments;

static int setup_arg_table(lua_State *lua)
{
    debug("Setting up arg table\n");
    lua_newtable(lua);
    //make sure arg[0] is the program name
    lua_pushstring(lua, arguments.program_name);
    lua_rawseti(lua, -2, 0);

    for (size_t i = 0; i < arguments.count; i++) {
        debug("Setting arg[%zu] to %s\n", i + 1, arguments.arguments[i]);
        lua_pushstring(lua, arguments.arguments[i]);
        lua_rawseti(lua, -2, i + 1);
    }

    lua_setglobal(lua, "arg");
    return 0;
}

#if defined(WIN32_GRAPHICAL)
static int main(int argc, const char *argv[const argc]);
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    int argc;
    char **argv = CommandLineToArgvA(GetCommandLineA(), &argc);
    return main(argc, argv);
}
static
#endif
//This program will be run when the executable is run, and it will unpack the zip file to tmpdir, and run the lua interpreter on the entrypoint file
int main(int argc, char *argv[static argc])
{
    arguments.program_name = argv[0];
    arguments.arguments = (const char **)argv + 1;
    arguments.count = argc - 1;

    const char *dbg_env = getenv("COMBUSTION_LOADER_VERBOSE");
    debug_output = dbg_env != NULL ? (dbg_env[0] == '1') : false;
    srand(time(NULL));

    lua_State *lua = luaL_newstate();
    if (lua == NULL) {
        error(NULL, "Failed to create new Lua state");
        return 1;
    }

    //pause GC while we load the modules and install the searcher
    lua_gc(lua, LUA_GCSTOP, 0);
    {
        luaL_openlibs(lua);

        //Install the searcher,
        {
            debug("Installing searcher\n");

            lua_getglobal(lua, LUA_LOADLIBNAME);
            if (!lua_istable(lua, -1)) {
                error(lua, "Failed to get "LUA_LOADLIBNAME" table!");
                return 1;
            }

            const char *searcher = "searchers";
            lua_getfield(lua, -1, searcher);
            if (!lua_istable(lua, -1)) {
                debug("Failed to get "LUA_LOADLIBNAME".searchers table, trying "LUA_LOADLIBNAME".loaders\n");
                searcher = "loaders";
                debug("Checking in "LUA_LOADLIBNAME".loaders (type %s)\n", lua_typename(lua, lua_type(lua, -2)));
                lua_getfield(lua, -2, searcher);
                if (!lua_istable(lua, -1)) {
                    error(lua, "Failed to get "LUA_LOADLIBNAME".searchers or "LUA_LOADLIBNAME".loaders table!");
                    return 1;
                }

                debug("Found "LUA_LOADLIBNAME".%s\n", searcher);
            }

            lua_pushcfunction(lua, internal_module_searcher);
            lua_rawseti(lua, -2, lua_rawlen(lua, -2) + 1);

            lua_pop(lua, 2);

            debug("Installed searcher\n");
        }


        lua_pushcfunction(lua, setup_arg_table);
        if (lua_pcall(lua, 0, 0, 0) != LUA_OK) {
            error(lua, "Failed to setup arg table");
            return 1;
        }
    }
    lua_gc(lua, LUA_GCRESTART, -1); //https://github.com/LuaJIT/LuaJIT/blob/e826d0c101d750fac8334d71e221c50d8dbe236c/src/luajit.c#L535C2-L535C2

    extern int MODULE(COMBUSTION_ENTRY)(lua_State *L);

    debug("Executing entrypoint "STRINGIFY(MODULE(COMBUSTION_ENTRY))"\n");
    // MODULE(COMBUSTION_ENTRY)(lua);
    lua_pushcfunction(lua, MODULE(COMBUSTION_ENTRY));
    lua_call(lua, 0, 0);
    // int stat = lua_pcall(lua, 0, 1, 0);
    // if (stat != LUA_OK) {
    //     error(lua, "Error executing entrypoint");
    //     return 1;
    // }

    debug("Program exited\n");
    lua_close(lua);

    return 0;
}

]]