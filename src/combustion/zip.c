/**
 * Copyright (c) 2023 Amrit Bhogal
 *
 * This software is released under the MIT License.
 * https://opensource.org/licenses/MIT
 */

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "miniz.h"

#if defined(_WIN32)
#   include <windows.h>
#   include <direct.h>
#   define mkdir(path, mode) _mkdir(path)
#   define getcwd(buf, size) _getcwd(buf, size)
#   define mkstemp(buf) _mktemp(buf)
#   define stat(path, buf) _stat(path, buf
#   define PATH_SEPARATOR '\\'
#   define PATH_MAX MAX_PATH
#else
#   include <sys/stat.h>
#   include <sys/types.h>
#   include <unistd.h>
#   include <dirent.h>
#   define PATH_SEPARATOR '/'
#   if(defined(__linux__))
#       include <linux/limits.h>
#   else
#       include <limits.h>
#   endif
#endif




static int zip(lua_State *L), add_files_to_zip(mz_zip_archive *zip, const char *dir, const char *prefix);

/*
---Recursively creates a zip file from a directory, preserving the directory structure
---@param dir string The directory to compress
---@return string? contents of the zip size_t? The size of the zip file, string? The error message
function zip(dir) end
*/
static int zip(lua_State *L)
{
    const char *dir = luaL_checkstring(L, 1);
    char errbuf[512] = {0};
    struct stat st = {0};
    if (stat(dir, &st) == -1) {
        lua_pushnil(L);
        lua_pushnil(L);
        snprintf(errbuf, sizeof(errbuf) - 1, "Failed to stat directory: %s", dir);
        lua_pushstring(L, errbuf);
        return 3;
    } else if (!(st.st_mode & S_IFDIR)) {
        lua_pushnil(L);
        lua_pushnil(L);
        snprintf(errbuf, sizeof(errbuf) - 1, "Not a directory: %s", dir);
        lua_pushstring(L, errbuf);
        return 3;
    }

    mz_zip_archive zip = {0};
    if (!mz_zip_writer_init_heap(&zip, 0, 0)) {
        lua_pushnil(L);
        lua_pushnil(L);
        snprintf(errbuf, sizeof(errbuf) - 1, "Failed to initialize zip archive\nReason: %s", mz_zip_get_error_string(mz_zip_get_last_error(&zip)));
        lua_pushstring(L, errbuf);
        return 3;
    }

    if (add_files_to_zip(&zip, dir, ".") != 0) {
        mz_zip_writer_end(&zip);
        lua_pushnil(L);
        lua_pushnil(L);
        snprintf(errbuf, sizeof(errbuf) - 1, "Failed to add files to zip archive\nReason: %s", mz_zip_get_error_string(mz_zip_get_last_error(&zip)));
        lua_pushstring(L, errbuf);
        return 3;
    }

    char *zip_data = NULL;
    size_t zip_size = 0;
    if (!mz_zip_writer_finalize_heap_archive(&zip, (void **)&zip_data, &zip_size)) {
        mz_zip_writer_end(&zip);
        lua_pushnil(L);
        lua_pushnil(L);
        snprintf(errbuf, sizeof(errbuf) - 1, "Failed to finalize zip archive\nReason: %s", mz_zip_get_error_string(mz_zip_get_last_error(&zip)));
        lua_pushstring(L, errbuf);
        return 3;
    }

    mz_zip_writer_end(&zip);
    lua_pushlstring(L, zip_data, zip_size);
    lua_pushinteger(L, zip_size);
    mz_free(zip_data);
    return 2;
}

static int add_files_to_zip(mz_zip_archive *zip, const char *dir, const char *prefix)
{
#if defined(_WIN32)
    char filepath[PATH_MAX] = {0}, subprefix[PATH_MAX] = {0};

    WIN32_FIND_DATA find_data;
    HANDLE find_handle = INVALID_HANDLE_VALUE;

    // Build a wildcard pattern for the files in the directory
    snprintf(filepath, sizeof(filepath) - 1, "%s\\*", dir);

    // Find the first file in the directory
    find_handle = FindFirstFile(filepath, &find_data);
    if (find_handle == INVALID_HANDLE_VALUE) {
        return -1;
    }

    // Iterate over all files in the directory
    do {
        if (strcmp(find_data.cFileName, ".") == 0 || strcmp(find_data.cFileName, "..") == 0) {
            continue;
        }

        // Build the full path to the file
        snprintf(filepath, sizeof(filepath) - 1, "%s\\%s", dir, find_data.cFileName);

        // Build the zip path for the file
        snprintf(subprefix, sizeof(subprefix) - 1, "%s\\%s", prefix, find_data.cFileName);

        if (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            // Recursively add files in subdirectories
            if (add_files_to_zip(zip, filepath, subprefix) != 0) {
                FindClose(find_handle);
                return -1;
            }
        } else {
            // Add regular files to the zip
            if (!mz_zip_writer_add_file(zip, subprefix, filepath, NULL, 0, MZ_BEST_COMPRESSION)) {
                FindClose(find_handle);
                return -1;
            }
        }
    } while (FindNextFile(find_handle, &find_data) != 0);

    FindClose(find_handle);
    return 0;
#else
    DIR *dp = opendir(dir);
    if (dp == NULL) return -1;


    struct dirent *ep;
    char filepath[512] = {0};
    while ((ep = readdir(dp)) != NULL) {
        if (ep->d_type == DT_DIR) {
            if (strcmp(ep->d_name, ".") == 0 || strcmp(ep->d_name, "..") == 0)
                continue;

            snprintf(filepath, sizeof(filepath) - 1, "%s/%s", dir, ep->d_name);
            char subprefix[512] = {0};
            snprintf(subprefix, sizeof(subprefix) - 1, "%s/%s", prefix, ep->d_name);
            if (add_files_to_zip(zip, filepath, subprefix) != 0)
                return 1;

        } else if (ep->d_type == DT_REG) {
            snprintf(filepath, sizeof(filepath) - 1, "%s/%s", dir, ep->d_name);
            char zippath[512] = {0};
            snprintf(zippath, sizeof(zippath) - 1, "%s/%s", prefix, ep->d_name);
            if (!mz_zip_writer_add_file(zip, zippath, filepath, NULL, 0, MZ_BEST_COMPRESSION))
                return 1;

        }
    }

    closedir(dp);
    return 0;
}
#endif

int luaopen_combustion_zip(lua_State *L)
{
    lua_pushcfunction(L, zip);
    return 1;
}
