-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

---@enum Platform
local export = {
    Windows = 1,
    Linux = 2,
    MacOS = 3,
    OSX = 3,
    Unknown = 4
}

local ffi = require("ffi")

---@return Platform
function export.get_platform()
    return export[ffi.os] or export.Unknown
end

return export
