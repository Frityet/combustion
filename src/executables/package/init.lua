local utilities = require("utilities")

---@param objs Module[]
---@param cmods Module[]
---@param out string
---@param config Config
return function (objs, cmods, out, config)
    return require("executables.package."..utilities.platform())(objs, cmods, out, config)
end
