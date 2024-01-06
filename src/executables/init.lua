---@type { [string] : fun(args: Combustion.BuildOptions) }
local packages = {
    ["self-extract"] = require("combustion.executables.self-extract"),
    ["static"] = require("combustion.executables.static")
}

return packages
