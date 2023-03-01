---@type { [string] : fun(args: Combustion.BuildOptions): boolean, string? }
local packages = {
    ["self-extract"] = require("executables.self-extract")
}

return packages
