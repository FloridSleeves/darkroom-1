import "darkroom"
fpga = require("fpga")
fpgaEstimate = require("fpgaEstimate")
darkroomSimple = require("darkroomSimple")
require("image")
require("darkroomDebug")

if arg[1]=="cpu" then
  testinput = darkroomSimple.load(arg[2])
else
  testinput = darkroom.input(uint8)
end



function test(inast, inputList)


  print("TEST",arg[1],arg[2])
  if arg[1]=="est" then
    local cpuinast
    if darkroom.ast.isAST(inast) then 
      cpuinast = {inast} 
    else
      cpuinast={}
      for k,v in ipairs(inast) do table.insert(cpuinast, v[1]) end
    end

    local est,pl = fpgaEstimate.compile(cpuinast, 640)
    io.output("out/"..arg[0]..".est.lua")
    io.write(est)
    io.close()
    io.output("out/"..arg[0]..".perlineest.txt")
    io.write(pl)
    io.close()
  elseif arg[1]=="builduart" or arg[1]=="buildaxi" or arg[1]=="buildsim" then

    local s = ""
    local hwinputs = nil
    local hwoutputs = nil
    local opt
    if arg[1]=="builduart" then
      hwinputs = inputList
      if hwinputs==nil then hwinputs={{testinput,"uart","frame_128.bmp"}} end
      hwoutputs = inast
      if darkroom.ast.isAST(hwoutputs) then
        hwoutputs = {{inast,"uart"}}
      end
      s = ".uart"
      opt = fpga.util.deviceToOptions(arg[3])
    elseif arg[1]=="buildsim" then
      hwinputs = inputList
      if hwinputs==nil then 
         hwinputs={{testinput,"sim","frame_128.raw"}} 
      else
         for k,v in pairs(inputList) do
            hwinputs[k] = {v[1],"sim",v[2]..".raw"}
         end
      end
      hwoutputs = inast
      if darkroom.ast.isAST(hwoutputs) then
        hwoutputs = {{inast,"sim"}}
      end
      
      s = ".sim"
      opt = fpga.util.deviceToOptions(arg[3])
    elseif arg[1]=="buildaxi" then
      print("BUILDAXI")
      hwinputs = inputList
      if hwinputs==nil then hwinputs={{testinput,"axi","frame_128.raw"}} end
      hwoutputs = inast
      if darkroom.ast.isAST(hwoutputs) then
        hwoutputs = {{inast,"axi"}}
      end
      
      s = ".axi"
      opt = fpga.util.deviceToOptions(arg[3])
    end

    s = string.sub(arg[0],1,#arg[0]-4)..s
    opt.debugImages = s..".debugimage."
    local v, metadata = fpga.compile(hwinputs, hwoutputs, 128, 64, opt)
    io.output("out/"..s..".v")
    io.write(v)
    io.close()
    
    fpga.util.writeMetadata("out/"..s..".metadata.lua", metadata)
  else
    local cpuinast
    if darkroom.ast.isAST(inast) then 
      cpuinast = {inast} 
    else
      cpuinast={}
      for k,v in ipairs(inast) do table.insert(cpuinast, v[1]) end
    end

    local terra dosave(img: &Image, filename : &int8)
      img:save(filename)
      img:free()
    end

    local tprog = darkroomSimple.compile(cpuinast,{debug=true, verbose=true, printruntime=true})

    local res = pack(unpacktuple(tprog()))
    for k,v in ipairs(res) do
      print(v)
      local st = ""
      if k>1 then st = "."..k end
      dosave(v,"out/"..arg[0]..st..".bmp")
    end
  end
end