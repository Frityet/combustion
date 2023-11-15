local src, dest = arg[1], arg[2]
if not src or not dest then error "Must have both arguments (src and dest) provided" end


if arg[3] then
    local src, header = src, dest
    dest = arg[3]

    local src_contents = assert(io.open(src, "rb"))
    local header_contents = assert(io.open(header, "rb"))
    local out = assert(io.open(dest, "w+b"))

    out:write("return {\n    header = [=[", header_contents:read("*a"), "\n]=],\n")
    out:write("    source = [=[\n", src_contents:read("*a"), "]=]\n}")

    return
end

local contents = assert(io.open(src, "rb"))
local out = assert(io.open(dest, "w+b"))

out:write("return [=[\n", contents:read("*a"), "\n]=]")

contents:close()
out:close()
