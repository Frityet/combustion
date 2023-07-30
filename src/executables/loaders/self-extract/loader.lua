return [[
 /**
 * Copyright (c) 2023 Amrit Bhogal
 *
 * This software is released under the MIT License.
 * https://opensource.org/licenses/MIT
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include "miniz.h"
//Just here for intellisense, it will be replaced by the build script
#if !defined(COMBUSTION_ENTRY)
#   define COMBUSTION_ENTRY $COMBUSTION_ENTRY$
#   define COMBUSTION_DATA_MAGIC $COMBUSTION_DATA_MAGIC$
#   define COMBUSTION_DATA_MAGIC_NUMBER 0x0
#endif
#define _STR(x) #x
#define STR(x) _STR(x)
#define LUA_BOOTSTRAP   "package.path=\"%s/lua/?.lua;%s/lua/?/init.lua\"\n"\
                        "package.cpath=\"%s/lib/?"DLL_EXT"\"\n"\
                        "dofile(\"%s\")\n"\
                        "os.exit()"

#if defined(_WIN32)
#   include <windows.h>
#   include <direct.h>
#   define mkdir(path, mode) _mkdir(path)
#   define getcwd(buf, size) _getcwd(buf, size)
#   define mkstemp(buf) _mktemp(buf)
#   define stat(path, buf) _stat(path, buf)
#   define spawnv(mode, path, argv) _spawnv(mode, path, argv)
#   define rmdir(path) _rmdir(path)
#   define PATH_SEPARATOR '\\'
#   define PATH_MAX MAX_PATH
#   define DLL_EXT ".dll"
#else
#   include <sys/stat.h>
#   include <sys/types.h>
#   include <unistd.h>
#   include <spawn.h>
#   include <sys/mman.h>
#   define PATH_SEPARATOR '/'
#   if(defined(__linux__))
#       include <linux/limits.h>
#   else
#       include <limits.h>
#   endif
#   define DLL_EXT ".so"
#endif


struct Buffer {
    uint32_t size;
    uint8_t data[];
};

static void perror_f(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    if (errno != 0)
        perror("System error:");
}
#define error(fmt, ...)\
 do { perror_f("[COMBUSTION LOADER - "__FILE__":"STR(__LINE__)"] \x1b[31m" fmt "\n" __VA_OPT__(,) __VA_ARGS__); exit(1); } while (0)

bool debug_output;
static void debug_f(const char *fmt, ...)
{
    if (!debug_output)
        return;
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}
#define debug(fmt, ...) do { debug_f("[COMBUSTION LOADER - "__FILE__":"STR(__LINE__)"] " fmt "\n" __VA_OPT__(,) __VA_ARGS__); } while (0)

//`mmap` wrapper, on windows it uses win32 api, on any other system it uses `mmap`
static uint8_t *memory_map(const char path[static PATH_MAX], size_t *size)
{
#if defined(_WIN32)
    HANDLE file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        error("Error opening file: %d", GetLastError());
        return NULL;
    }

    HANDLE mapping = CreateFileMappingA(file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (mapping == NULL) {
        error("Error creating file mapping: %d", GetLastError());
        return NULL;
    }

    uint8_t *data = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    if (data == NULL) {
        error("Error mapping view of file: %d", GetLastError());
        return NULL;
    }

    LARGE_INTEGER file_size;
    if (!GetFileSizeEx(file, &file_size)) {
        error("Error getting file size: %d", GetLastError());
        return NULL;
    }

    *size = file_size.QuadPart;
    return data;
#else
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) {
        error("Error opening file: %s", path);
        return NULL;
    }

    fseek(fp, 0, SEEK_END);
    *size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    uint8_t *data = mmap(NULL, *size, PROT_READ, MAP_PRIVATE, fileno(fp), 0);
    if (data == MAP_FAILED) {
        error("Error mapping file: %s", path);
        return NULL;
    }

    return data;
#endif
}

static uint8_t *find_bytes(size_t haystack_len, uint8_t haystack[static haystack_len], size_t needle_len, uint8_t needle[static needle_len])
{
#if defined(_WIN32)
    if (haystack == NULL || needle == NULL || haystack_len < needle_len)
        return NULL;

    for (uint8_t *ptr = haystack; haystack_len >= needle_len; ++ptr, --haystack_len) {
        if (memcmp(ptr, needle, needle_len) == 0)
            return ptr;
    }
    return NULL;
#else
    //The system one is probably better
    return memmem(haystack, haystack_len, needle, needle_len);
#endif
}


//Located at the end of the binary, past COMBUSTION_DATA_MAGIC
static struct Buffer *get_zipfile(const char this_binary[static PATH_MAX])
{
    size_t size = 0;
    uint8_t *data = memory_map(this_binary, &size);
    debug("Loaded binary: %p (size: %lu)", data, size);

    const char MAGIC[] = STR(COMBUSTION_DATA_MAGIC);
    uint8_t magic[sizeof(MAGIC) + 4] = {0};
    memcpy(magic, MAGIC, sizeof(MAGIC) - 1);
    memcpy(magic + sizeof(MAGIC) - 1, &(uint32_t){COMBUSTION_DATA_MAGIC_NUMBER}, 4);

    //2140215F434F4D42555354494F4E5F4D414749435F21402135B1
    debug("Searching for bytes:");
    for (size_t i = 0; i < sizeof(magic); i++)
        debug_f(" %X", magic[i]);
    debug_f("\n");

    uint8_t *zipfile = find_bytes(size, data, sizeof(magic)-1, magic);
    if (zipfile == NULL) {
        error("Error finding zip file: ");
        return NULL;
    }

    return (struct Buffer *)(zipfile + sizeof(magic) - 1);
}

/* recursive mkdir */
//Taken from https://gist.github.com/ChisholmKyle/0cbedcd3e64132243a39
int mkdir_p(const char dir[static PATH_MAX]) {
    char tmp[PATH_MAX] = {0};
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
                if (mkdir(tmp, 0777) < 0) {
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
        if (mkdir(tmp, 0777) < 0) {
            return -1;
        }
    } else if (!S_ISDIR(sb.st_mode)) {
        /* not a directory */
        return -1;
    }
    return 0;
}

static char *dirname(char *path)
{
    char *last_slash = strrchr(path, PATH_SEPARATOR);

    if (last_slash != NULL)
        *last_slash = '\0';

    return path;
}


static int unzip_recursive(mz_zip_archive *zip, const char dir[static PATH_MAX])
{
    size_t num_files = mz_zip_reader_get_num_files(zip);
    for (size_t i = 0; i < num_files; i++) {
        mz_zip_archive_file_stat file_stat;
        if (!mz_zip_reader_file_stat(zip, i, &file_stat)) {
            error("Error getting file stat: %s", mz_zip_get_error_string(mz_zip_get_last_error(zip)));
            return 1;
        }

        //Get the path to the file in the zip, then create parent directories, then extract the file
        char outf[PATH_MAX] = {0};
        size_t len = snprintf(outf, PATH_MAX, "%s%c%s\n", dir, PATH_SEPARATOR, file_stat.m_filename);

        if (file_stat.m_is_directory) {
            if (mkdir_p(outf) != 0) {
                error("Error creating directory: %s", outf);
                return 1;
            }
        } else {
            //Mutates outf, but the filename is still there
            if (mkdir_p(dirname(outf)) != 0) {
                error("Error creating directory: %s", outf);
                return 1;
            }


            //So just remove the null terminator and add the filename back
            // size_t len = strnlen(outf, PATH_MAX);
            //I think there is a good reason I use 2 `strlen`s here
            //I am too scared to change it
            outf[strlen(outf)] = PATH_SEPARATOR;
            outf[strlen(outf) - 1] = '\0'; //For some reason the last char seems to be a newline?
            if (mz_zip_reader_extract_to_file(zip, i, outf, 0) != MZ_TRUE) {
                error("Error extracting file: %s", outf);
                return 1;
            }
        }
    }
    return 0;
}


static int run_lua(const char tmpdir[const PATH_MAX], int argc, char *argv[static argc])
{
#if defined(_WIN32)
    char lua_path[PATH_MAX] = {0};
    snprintf(lua_path, PATH_MAX, "%s\\bin\\lua.exe", tmpdir);
    char entrypoint_path[PATH_MAX] = {0};
    snprintf(entrypoint_path, PATH_MAX, "%s\\lua\\%s", tmpdir, STR(COMBUSTION_ENTRY));

    char bootstrap[sizeof(LUA_BOOTSTRAP) + PATH_MAX * 4] = {0};
    snprintf(bootstrap, sizeof(bootstrap), LUA_BOOTSTRAP, tmpdir, tmpdir, tmpdir, entrypoint_path);

    //argv[0] is the path to the lua interpreter, argv[1] is the path to the entrypoint file
    char **args = calloc(argc + 2 + 2, sizeof(char *));
    memcpy(args, (char *[]) {
         lua_path, "-e", bootstrap, entrypoint_path
    }, 4 * sizeof(char *));
    memcpy(args + 4, argv + 1, argc * sizeof(char *));

    //Spawn the lua interpreter
    int ret = spawnv(P_WAIT, lua_path, args);
    free(args);
    return ret;
#else
    char lua_path[PATH_MAX] = {0};
    snprintf(lua_path, PATH_MAX, "%s/bin/lua", tmpdir);
    debug("Lua path: %s", lua_path);
    chmod(lua_path, 0755); //Make sure the lua interpreter is executable
    char entrypoint_path[PATH_MAX] = {0};
    snprintf(entrypoint_path, PATH_MAX, "%s/lua/%s", tmpdir, STR(COMBUSTION_ENTRY));
    debug("Entrypoint path: %s", entrypoint_path);

    char bootstrap[sizeof(LUA_BOOTSTRAP) + PATH_MAX * 4] = {0};
    snprintf(bootstrap, sizeof(bootstrap), LUA_BOOTSTRAP, tmpdir, tmpdir, tmpdir, entrypoint_path);

    //argv[0] is the path to the lua interpreter, argv[1] is the path to the entrypoint file
    char **args = calloc(argc + 2 + 2, sizeof(char *));
    memcpy(args, (char *[]) {
         lua_path, "-e", bootstrap, entrypoint_path
    }, 4 * sizeof(char *));
    memcpy(args + 4, argv + 1, argc * sizeof(char *));

    int ret = execv(lua_path, args);
    free(args);
    if (ret == -1)
        error("Error executing lua: %s", lua_path);

    return ret;
#endif
}

unsigned long gettmpdir(char buf[static PATH_MAX])
{
    unsigned long id = 0;
 #if defined(_WIN32)
    id = GetCurrentProcessId();
    DWORD len = GetTempPathA(PATH_MAX, buf);
    if (len == 0 || len > PATH_MAX) {
        error("Error getting temp path: %d", GetLastError());
        return NULL;
    }
#else
    id = getpid();
    const char *tmpdir = NULL, **env_vars = NULL;
    for (env_vars = (const char *[]){ "TMPDIR", "TMP", "TEMP", "TEMPDIR", NULL }, tmpdir = getenv(*env_vars);
         tmpdir == NULL && *++env_vars;
         tmpdir = getenv(*env_vars));

    if (tmpdir == NULL) {
        puts("Couldn't get with an env call");
        snprintf(buf, PATH_MAX, "/tmpd"); //the d is a shitty workaround
        tmpdir = buf;
    }
#endif
    size_t len = strnlen(tmpdir, PATH_MAX);
    memcpy(buf, tmpdir, len);

    //Finally, append the id to the path
    snprintf(&buf[len - 1], PATH_MAX - len - 1, "%ccombustion-%lu", PATH_SEPARATOR, id);
    mkdir_p(buf);
    return id;
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
    if (argc > 1) {
        debug_output = strcmp(argv[1], "$COMBUSTION_VERBOSE$") == 0;
        if (debug_output) {
            argv++;
            argv[0] = argv[-1]; // need proper argv[0] for debug output
            argc--;
        }
    }

    srand(time(NULL));
    //Directory setup
    char cwd[PATH_MAX] = {0}, tmpdir[PATH_MAX] = {0};
    getcwd(cwd, PATH_MAX);
    unsigned long id = gettmpdir(tmpdir);
    debug("tmpdir: %s (id: %ul)", tmpdir, id);

    mz_zip_archive zip_archive = {0};

    errno = 0;
    struct Buffer *zipfile = get_zipfile(argv[0]);

    debug("Found zipfile: %p (size: %zu)", zipfile, zipfile->size);

#define ZIP_ERR(archive) (mz_zip_get_error_string(mz_zip_get_last_error(archive)))
    //Open the zip file
    if (!mz_zip_reader_init_mem(&zip_archive, zipfile->data, zipfile->size, 0)) {
        error("Error opening zip file: %s", ZIP_ERR(&zip_archive));
        return EXIT_FAILURE;
    }

    //Extract the zip file, and create the directories preserving the file structure
    if (unzip_recursive(&zip_archive, tmpdir) != 0) {
        error("Error extracting zip file: %s", ZIP_ERR(&zip_archive));
        return EXIT_FAILURE;
    }
#undef ZIP_ERR
    //Close the zip file
    mz_zip_reader_end(&zip_archive);

    debug("Running lua with args: ");
    for (int i = 0; i < argc; i++)
        debug("  [%d] = \"%s\"", i, argv[i]);

    //Run the lua interpreter located in `tmpdir`/bin/lua[.exe]
    int ret = run_lua(tmpdir, argc, argv);
    rmdir(tmpdir);
}

]]