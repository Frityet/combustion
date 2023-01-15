local zip = require("brimworks.zip")
local path = require("pl.path")
local file = require("pl.file")
local utilities = require("utilities")

local EXECUTABLE_ENTRY = [[
    #if !defined(_WIN32)
    #include <zip.h>
    #include <stdlib.h>
    #include <stdio.h>
    #include <string.h>
    #include <sys/stat.h>
    #include <unistd.h>
    #include <limits.h>
    #include <stdarg.h>
    #include <libgen.h>
    extern int errno;

    static void perror_f(const char *fmt, ...)
    {
        static char buffer[1024];
        va_list args;
        va_start(args, fmt);
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        va_end(args);
        perror(buffer);
    }

    extern unsigned char module_archive[];
    extern size_t module_archive_size;

    static int execute_lua( const char *entrypoint,
                            const char *bin, const char *lua_modules, const char *c_modules,
                            int argc, const char *argv[static argc]);

    /* recursive mkdir */
    //Taken from https://gist.github.com/ChisholmKyle/0cbedcd3e64132243a39
    int mkdir_p(const char *dir, const mode_t mode) {
        char tmp[PATH_MAX];
        char *p = NULL;
        struct stat sb;
        size_t len;

        /* copy path */
        len = strnlen (dir, PATH_MAX);
        if (len == 0 || len == PATH_MAX) {
            return -1;
        }
        memcpy (tmp, dir, len);
        tmp[len] = '\0';

        /* remove trailing slash */
        if(tmp[len - 1] == '/') {
            tmp[len - 1] = '\0';
        }

        /* check if path exists and is a directory */
        if (stat (tmp, &sb) == 0) {
            if (S_ISDIR (sb.st_mode)) {
                return 0;
            }
        }

        /* recursive mkdir */
        for(p = tmp + 1; *p; p++) {
            if(*p == '/') {
                *p = 0;
                /* test path */
                if (stat(tmp, &sb) != 0) {
                    /* path does not exist - create directory */
                    if (mkdir(tmp, mode) < 0) {
                        return -1;
                    }
                } else if (!S_ISDIR(sb.st_mode)) {
                    /* not a directory */
                    return -1;
                }
                *p = '/';
            }
        }
        /* test path */
        if (stat(tmp, &sb) != 0) {
            /* path does not exist - create directory */
            if (mkdir(tmp, mode) < 0) {
                return -1;
            }
        } else if (!S_ISDIR(sb.st_mode)) {
            /* not a directory */
            return -1;
        }
        return 0;
    }

    static void extract_file(struct zip *zip, const struct zip_stat *stat, const char *to)
    {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", to, stat->name);

        const char *parent_dir = dirname(path);
        mkdir_p(parent_dir, 0755);

        struct zip_file *file = zip_fopen_index(zip, stat->index, 0);
        if (file == NULL) {
            fprintf(stderr, "Could not open file %s\n", stat->name);
            return;
        }

        FILE *out = fopen(path, "w+b");
        if (out == NULL) {
            perror_f("Could not open file %s for writing", path);
            return;
        }

        char buf[4096];
        int n;
        while ((n = zip_fread(file, buf, sizeof(buf))) > 0) {
            fwrite(buf, 1, n, out);
        }

        fclose(out);
        zip_fclose(file);
    }

    int main(int argc, const char *argv[])
    {
        struct zip_error ziperr;
        zip_source_t *src = zip_source_buffer_create(module_archive, module_archive_size, 0, &ziperr);
        if (src == NULL) {
            fprintf(stderr, "Could not create zip source: %s", zip_error_strerror(&ziperr));
            return 1;
        }

        struct zip *zip = zip_open_from_source(src, ZIP_CHECKCONS | ZIP_RDONLY, &ziperr);
        if (zip == NULL) {
            fprintf(stderr, "Could not open module archive: %s", zip_error_strerror(&ziperr));
            return 1;
        }


        const char *td = getenv("TMPDIR");

        int entryc = zip_get_num_entries(zip, 0);
        for (int i = 0; i < entryc; i++) {
            struct zip_stat st;
            if (zip_stat_index(zip, i, 0, &st) == 0) {
                if (st.name[strlen(st.name) - 1] != '/') {
                    extract_file(zip, &st, td);
                } else {
                    char path[PATH_MAX] = {0};
                    snprintf(path, sizeof(path), "%s/%s", td, st.name);
                    mkdir_p(path, 0755);
                }
            }
        }

        zip_close(zip);
        zip_source_close(src);

        char entrypoint_def_path[PATH_MAX] = {0};
        snprintf(entrypoint_def_path, sizeof(entrypoint_def_path), "%s/bin/_ENTRYPOINT_", td);

        char entrypoint[PATH_MAX] = {0};
        FILE *f = fopen(entrypoint_def_path, "rb");
        if (f == NULL) {
            perror_f("Could not open entrypoint file (%s)", entrypoint_def_path);
            return 1;
        }

        fread(entrypoint, 1, sizeof(entrypoint), f);
        fclose(f);

        char bin_tmp[PATH_MAX] = {0}, lua_tmp[PATH_MAX] = {0}, lib_tmp[PATH_MAX] = {0};

        snprintf(bin_tmp, sizeof(bin_tmp), "%s/bin/", td);
        snprintf(lua_tmp, sizeof(lua_tmp), "%s/lua/", td);
        snprintf(lib_tmp, sizeof(lib_tmp), "%s/lib/", td);

        return execute_lua(entrypoint, bin_tmp, lua_tmp, lib_tmp, argc, argv);
    }

    static int execute_lua( const char *entrypoint,
                            const char *bin, const char *lua_modules, const char *c_modules,
                            int argc, const char *argv[static argc])
    {
        char    lua_modules_abs[PATH_MAX] = {0}, c_modules_abs[PATH_MAX] = {0}, bin_abs[PATH_MAX] = {0}, entrypoint_abs[PATH_MAX] = {0},
                cwd[PATH_MAX] = {0}, interpreter_abs[PATH_MAX] = {0};

        realpath(lua_modules, lua_modules_abs);
        realpath(c_modules, c_modules_abs);
        realpath(bin, bin_abs);

        {
            char tmp[PATH_MAX] = {0};
            snprintf(tmp, sizeof(entrypoint_abs), "%s%s", lua_modules, entrypoint);
            realpath(tmp, entrypoint_abs);
        }

        getcwd(cwd, sizeof(cwd));

        snprintf(interpreter_abs, sizeof(interpreter_abs), "%s/lua", bin_abs);

        size_t path_code_length = sizeof("package.path=\"\";package.cpath=\"\";") + sizeof(lua_modules_abs) + sizeof("/?.lua") + sizeof("/?/init.lua")
                                                                                  + sizeof(c_modules_abs) + sizeof("/?.so")
                                                                                  + sizeof(cwd) + sizeof("/?.lua") + sizeof("/?/init.lua") + sizeof("/?.so");
        char *path_code = malloc(path_code_length + 1);
        if (path_code == NULL) {
            perror_f("Could not allocate memory for path code. Attempted to allocate %zu bytes", path_code_length);
            return 1;
        }

        {
            char *p = path_code;
            p += snprintf(p, path_code_length, "package.path=\"%s/?.lua;%s/?/init.lua;%s/?.lua;%s/?/init.lua;\";", lua_modules_abs, lua_modules_abs, cwd, cwd);
            p += snprintf(p, path_code_length - (p - path_code), "package.cpath=\"%s/?.so;%s/?.so;\";", c_modules_abs, cwd);
        }

        char **args = calloc(argc + 5, sizeof(char *));
        if (args == NULL) {
            perror_f("Could not allocate memory for args. Attempted to allocate %zu bytes", sizeof(char *) * (argc + 5));
            return 1;
        }

        memcpy(args, (const char *[4]) {
            cwd, //arg[0], must be the current working directory
            "-e", path_code, //Set the path for the interpreter
            entrypoint_abs, //The entrypoint file
        }, sizeof(char *) * 4);

        memcpy(args + 4, argv + 1, sizeof(char *) * (argc));

        chmod(interpreter_abs, 0755);
        int err = execv(interpreter_abs, args);
        if (err == -1) {
            perror_f("Could not execute interpreter (%s)", interpreter_abs);
            return 1;
        }

        return err;
    }

    #else

    #endif

]]

---@param prog string
---@param ... string
---@return fun(): string
local function execute(prog, ...)
    local args = {...}
    local proc = assert(io.popen(prog.." "..table.concat(args, ' '), "r"))

    return coroutine.wrap(function ()
        local out = ""
        for line in proc:lines() do
            out = out..line.."\n"
            coroutine.yield(line)
        end

        return out, proc:close()
    end)
end

---Self-extracting executable that extracts the required modules to a temporary directory and executes the main program
---@param objs Module[]
---@param cmods Module[]
---@param out string
---@param config Config
return function (objs, cmods, out, config)
    file.delete(path.join(out, "module_archive.zip"))

    print("\x1b[33mCreating archive\x1b[0m")
    local archive = assert(zip.open(path.join(out, "module_archive.zip"), zip.OR(zip.CREATE, zip.EXCL)))

    local archive_paths = {
        base= "",
        lua = "lua",
        lib = "lib",
        bin = "bin",
    }

    for _, dir in pairs(archive_paths) do
        archive:add_dir(dir)
    end

    print("\x1b[33mAdding lua modules\x1b[0m")
    for _, obj in ipairs(objs) do
        archive:add(path.join(archive_paths.lua, obj.name), "file", obj.path)
        print("- \x1b[32mCompressed\x1b[0m "..obj.name)
    end

    print("\x1b[33mAdding native modules\x1b[0m")
    for _, cmod in ipairs(cmods) do
        archive:add(path.join(archive_paths.lib, cmod.name), "file", cmod.path)
        print("- \x1b[32mCompressed\x1b[0m "..cmod.name)
    end

    print("\x1b[33mAdding runtime\x1b[0m")
    archive:add(path.join(archive_paths.bin, "lua"), "file", config.lua.interpreter)
    print("- \x1b[32mCompressed\x1b[0m lua")
    archive:add(path.join(archive_paths.bin, "liblua.dylib"), "file", config.lua.runtime)
    print("- \x1b[32mCompressed\x1b[0m liblua.dylib")
    archive:add(path.join(archive_paths.bin, "_ENTRYPOINT_"), "string", config.entry)
    print("- \x1b[32mCompressed\x1b[0m _ENTRYPOINT_")

    print("\x1b[33mNote: if you receive a crash here, just run the program again (library issue)\x1b[0m")
    archive:close()


    ---@param code string
    ---@param out string
    ---@param ... string
    local function compile(code, out, ...)
        local cmd = string.format("%s -x c -c %s -o %s -", config.c_compiler, table.concat({...}, " "), out)

        local f = assert(io.popen(cmd, "w"))
        f:write(code)
        f:close()
    end

    ---@param objs string[]
    ---@param out string
    ---@param ... string
    local function link(objs, out, ...)
        local cmd = string.format("%s %s -o %s %s", config.c_compiler, table.concat({...}, " "), out, table.concat(objs, " "))

        os.execute(cmd)
    end

    ---@param opt { [string] : string }
    local function define(opt)
        local out = {}
        for k, v in pairs(opt) do
            table.insert(out, string.format("-D%s=%s", k, v))
        end
        return table.unpack(out)
    end

    ---@param opt string[]
    local function warning(opt)
        local out = {}
        for _, v in ipairs(opt) do
            table.insert(out, string.format("-W%s", v))
        end
        return table.unpack(out)
    end

    print("\x1b[33mCompiling module archive\x1b[0m")
    local modarch_obj = path.join(out, "module_archive.o")
    compile(utilities.bin2c(file.read(path.join(out, "module_archive.zip")) --[[@as string]], "module_archive"),
            modarch_obj,

            "-Os", "-std=c99",
            warning {
                "all", "extra", "pedantic", "error"
            }
    )
    print("- \x1b[32"..modarch_obj.."\x1b[0m")

    local libzip_include= execute("pkg-config", "--cflags-only-I", "libzip")()
    local libzip_lib    = execute("pkg-config", "--libs-only-L", "libzip")()

    local exentry_obj = path.join(out, "main.o")
    if not path.exists(exentry_obj) then
        -- print("Compiling executable entry")
        print("\x1b[33mCompiling executable entry\x1b[0m")
        compile(EXECUTABLE_ENTRY, exentry_obj,
            "-Os",
            "-std=c99",

            warning {
                "all", "extra", "pedantic", "error"
            },

            libzip_include
        )
        print("- \x1b[32"..exentry_obj.."\x1b[0m")
    end

    print("\x1b[33mLinking executable\x1b[0m")
    link({ modarch_obj, exentry_obj }, path.join(out, path.basename(path.currentdir())),
         "-flto",
         libzip_lib,
         "-lzip"
    )
    print("- \x1b[32"..path.join(out, path.basename(path.currentdir())).."\x1b[0m")
    print("\x1b[32mDone\x1b[0m")
end
