local tablex = require("pl.tablex")

print 'Small test of combustion'

print(package.path, package.cpath)

print("Arguments:")

for i, v in ipairs(arg) do
    print(i, v)
end

print("Env")

for k, v in pairs(_G) do
    print(k, v)
end
