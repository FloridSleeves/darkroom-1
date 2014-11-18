import "darkroom"
darkroomSimple = terralib.require("darkroomSimple")
fpga = terralib.require("fpga")


sensor = darkroomSimple.load("300d.bmp")
campipeline = im(x,y) {sensor >> [uint8](5), sensor+[uint8](10), sensor+[uint8](20)} end

campipeline:save("out/trivial.bmp")

print("Build For: "..arg[1])
local v, metadata = fpga.compile({{sensor,"uart","300d.bmp"}},{{campipeline,"uart"}}, 128,64, fpga.util.deviceToOptions(arg[1]))

local s = string.sub(arg[0],1,#arg[0]-2)
io.output("out/"..s..".v")
io.write(v)
io.close()

metadata.inputFile = "300d.bmp"
fpga.util.writeMetadata("out/"..s..".metadata.lua", metadata)
-----------------------------
local vVGA, metadata = fpga.compile({{sensor,"vga"}},{{campipeline,"vga"}}, 640,480, fpga.util.deviceToOptions(arg[1]))

local s = string.sub(arg[0],1,#arg[0]-2)
io.output("out/"..s..".vga.v")
io.write(vVGA)
io.close()
