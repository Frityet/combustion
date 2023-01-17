local entryf = assert(io.open("../Resources/_ENTRYPOINT_", "r"))
local entry = entryf:read("*a")
entryf:close()

package.path = "../Resources/?.lua;../Resources/?/init.lua;"
package.cpath = "../Frameworks/?.so;../Frameworks/?.dylib;"

if pcall(require, "ffi") then
    ---@type ffilib
    local ffi = require("ffi")
    local ljit_load = ffi.load

    ---@param libname string
    ---@param global boolean?
    ---@return ffi.namespace*
    function ffi.load(libname, global)
        local dylibpath = "./../Frameworks/"
        if libname:sub(1, 2) == "./" then
            dylibpath = dylibpath..libname:sub(3)
        else
            dylibpath = dylibpath.."lib"..libname..".dylib"
        end

        return ljit_load(dylibpath, global)
    end
end

return dofile("../Resources/"..entry)
