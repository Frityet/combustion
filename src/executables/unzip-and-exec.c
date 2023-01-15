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
                        const char *rt, const char *lua_modules, const char *c_modules,
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
    int err = 0;
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
    snprintf(entrypoint_def_path, sizeof(entrypoint_def_path), "%s/modules/rt/_ENTRYPOINT_", td);

    char entrypoint[PATH_MAX] = {0};
    FILE *f = fopen(entrypoint_def_path, "rb");
    if (f == NULL) {
        perror_f("Could not open entrypoint file (%s)", entrypoint_def_path);
        return 1;
    }

    fread(entrypoint, 1, sizeof(entrypoint), f);
    fclose(f);

    char rt_tmp[PATH_MAX] = {0}, lua_tmp[PATH_MAX] = {0}, lib_tmp[PATH_MAX] = {0};

    snprintf(rt_tmp, sizeof(rt_tmp), "%s/modules/rt/", td);
    snprintf(lua_tmp, sizeof(lua_tmp), "%s/modules/lua/", td);
    snprintf(lib_tmp, sizeof(lib_tmp), "%s/modules/lib/", td);

    return execute_lua(entrypoint, rt_tmp, lua_tmp, lib_tmp, argc, argv);
}

static int execute_lua( const char *entrypoint,
                        const char *rt, const char *lua_modules, const char *c_modules,
                        int argc, const char *argv[static argc])
{
    char    lua_modules_abs[PATH_MAX] = {0}, c_modules_abs[PATH_MAX] = {0}, rt_abs[PATH_MAX] = {0}, entrypoint_abs[PATH_MAX] = {0},
            cwd[PATH_MAX] = {0}, interpreter_abs[PATH_MAX] = {0};

    realpath(lua_modules, lua_modules_abs);
    realpath(c_modules, c_modules_abs);
    realpath(rt, rt_abs);

    {
        char tmp[PATH_MAX] = {0};
        snprintf(tmp, sizeof(entrypoint_abs), "%s%s", lua_modules, entrypoint);
        realpath(tmp, entrypoint_abs);
    }

    getcwd(cwd, sizeof(cwd));

    snprintf(interpreter_abs, sizeof(interpreter_abs), "%s/lua", rt_abs);

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

    char **args = malloc(sizeof(char *) * (argc + 4));
    if (args == NULL) {
        perror_f("Could not allocate memory for args. Attempted to allocate %zu bytes", sizeof(char *) * (argc + 4));
        return 1;
    }

    memcpy(args, (const char *[4]) {
        cwd, //arg[0], must be the current working directory
        "-e", path_code, //Set the path for the interpreter
        entrypoint_abs, //The entrypoint file
    }, sizeof(char *) * 4);

    memcpy(args + 4, argv + 1, sizeof(char *) * (argc - 1));

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
