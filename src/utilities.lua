local export = {}


---@param data string
---@param symname string
---@return string
function export.bin2c(data, symname)
    local out = "#include <stddef.h>\n\n"
    out = out.."const unsigned char "..symname.."[] = {\n"
    for i = 1, #data do
        out = out..string.format("0x%02x,", string.byte(data, i))
        if i % 16 == 0 then
            out = out..'\n'
        end
    end
    out = out.."\n};\n"
    return out.."const size_t "..symname.."_size = "..#data..";\n"
end

return export
