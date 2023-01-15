local export = {}


---@param data string
---@param symname string
---@return string
function export.bin2c(data, symname)
    local out = "#include <stddef.h>\n\n"
    out = out.."const unsigned char "..symname.."[] = {\n"

    io.write("\x1b[?25l")
    for i = 1, #data do
        out = out..string.format("0x%02x,", string.byte(data, i))
        -- io.write("\x1b[35mWrote \x1b[31m", i, "\x1b[35m bytes\x1b[0m\r")
        io.write(string.format("\x1b[33mWrote \x1b[32m%d\x1b[33m bytes \x1b[0m(\x1b[32m%.2f%%\x1b[0m)\r", i, i / #data * 100))
        if i % 16 == 0 then
            out = out..'\n'
        end
    end
    io.write("\x1b[?25h")
    out = out.."\n};\n"
    return out.."const size_t "..symname.."_size = "..#data..";\n"
end

return export
