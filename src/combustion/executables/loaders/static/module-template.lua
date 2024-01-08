return [[
/**
 * Copyright (c) 2023 Amrit Bhogal
 *
 * This software is released under the MIT License.
 * https://opensource.org/licenses/MIT
 */

#include <stdint.h>

#include "compat-5.3.h"

#define _EVAL(x) x
#define EVAL(...) _EVAL(__VA_ARGS__)

#define CONCAT(x, y) EVAL(x##y)
#define _STRINGIFY(x) #x
#define STRINGIFY(...) _STRINGIFY(__VA_ARGS__)

#define MODULE(x) CONCAT($internal_module$_, x)
#define DECLARE_MODULE(x) __attribute__((used)) int MODULE(x)(lua_State *lua)

// For clangd
#if !defined(COMBUSTION_MODULE_SYMBOL)
#   define COMBUSTION_MODULE_SYMBOL ERROR__MODULE_SYMBOL_NOT_DEFINED
#   define COMBUSTION_MODULE_NAME ERROR__MODULE_NAME_NOT_DEFINED
#   define COMBUSTION_MODULE_BYTECODE_SYMBOL ERROR_MODULE_BYTECODE_SYMBOL_NOT_DEFINED
#   define COMBUSTION_MODULE_BYTECODE_SIZE 1
#endif

extern const char COMBUSTION_MODULE_BYTECODE_SYMBOL[COMBUSTION_MODULE_BYTECODE_SIZE];

static void debug_f(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}
#define debug(fmt, ...) do { debug_f("["__FILE__":"STRINGIFY(__LINE__)"] " fmt __VA_OPT__(,) __VA_ARGS__); } while (0)

static void perror_f(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    static char buf[1024] = {0};
    vsnprintf(buf, 1024, fmt, args);
    va_end(args);
    perror(buf);
}
#define error(fmt, ...) do { perror_f("["__FILE__":"STRINGIFY(__LINE__)"] " fmt __VA_OPT__(,) __VA_ARGS__); exit(1); } while (0)


DECLARE_MODULE(COMBUSTION_MODULE_SYMBOL)
{
    debug("Loading module %s (size: %zu, id: %s)\n", STRINGIFY(COMBUSTION_MODULE_NAME), COMBUSTION_MODULE_BYTECODE_SIZE, STRINGIFY(MODULE(COMBUSTION_MODULE_SYMBOL)));
    int stat = luaL_loadbuffer(lua, COMBUSTION_MODULE_BYTECODE_SYMBOL, COMBUSTION_MODULE_BYTECODE_SIZE, STRINGIFY(COMBUSTION_MODULE_NAME));
    if (stat != LUA_OK) {
        error("Failed to load module %s: %s\n", STRINGIFY(COMBUSTION_MODULE_NAME), lua_tostring(lua, -1));
        exit(1);
    }

    int ret = lua_pcall(lua, 0, LUA_MULTRET, 0);
    if (ret != LUA_OK) {
        error("Failed to load module %s: %s\n", STRINGIFY(COMBUSTION_MODULE_NAME), lua_tostring(lua, -1));
        exit(1);
    }

    return 1;
};

]]