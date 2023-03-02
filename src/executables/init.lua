---@type { [string] : fun(args: Combustion.BuildOptions) }
local packages = {
    ["self-extract"] = require("executables.self-extract")
}

return packages
