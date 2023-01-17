local path = require("pl.path")
local file = require("pl.file")
local directory = require("pl.dir")

local INFO_TEMPLATE = [[
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$(executable)</string>
    <key>CFBundleIconFile</key>
    <string>$(icon)</string>
    <key>CFBundleIdentifier</key>
    <string>$(bundleid)</string>
    <key>CFBundleName</key>
    <string>$(name)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(version)</string>
</dict>
</plist>
]]

---@param objs Module[]
---@param cmods Module[]
---@param out string
---@param config Config
return function (objs, cmods, out, config)
    ---@type { path: string, contents: string, macos: string, resources: string, frameworks: string, info: file* }
    local app = {
        path = path.join("out", path.basename(path.currentdir())..".app"),
    }
    app.contents = path.join(out, "Contents")
    app.macos = path.join(app.contents, "MacOS")
    app.resources = path.join(app.contents, "Resources")
    app.frameworks = path.join(app.contents, "Frameworks")
    app.info = assert(io.open(path.join(app.contents, "Info.plist"), "w+"))
    for _, dir in ipairs(app) do directory.makepath(dir) end

    --Copy the lua interpreter to the MacOS folder
    print("- \x1b[32mCopying\x1b[0m "..config.lua.interpreter)
    file.copy(config.lua.interpreter, path.join(app.macos, "lua"))

    --We also need an entry point which will set the paths and call the real entry point


    --Lua modules will be in

    app.info:close()
end
