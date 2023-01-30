-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

local utilities = require("utilities")

---@type { [Platform] : fun(objs: Module[], cmods: Module[], out: string, config: Config) }
local platforms = {
    ["osx"] = require("executables.package.osx"),
    ["linux"] = require("executables.package.linux"),
    ["windows"] = require("executables.package.windows"),
    ["unknown"] = function (objs, cmods, out, config)
        error("Unsupported platform "..utilities.get_platform())
    end
}


---@param objs Module[]
---@param cmods Module[]
---@param out string
---@param config Config
return function (objs, cmods, out, config)
    return platforms[utilities.get_platform()](objs, cmods, out, config)
end
