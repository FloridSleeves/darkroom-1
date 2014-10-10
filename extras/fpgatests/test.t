import "darkroom"
fpga = terralib.require("fpga")
fpgaEstimate = terralib.require("fpgaEstimate")
darkroomSimple = terralib.require("darkroomSimple")
terralib.require("image")

if arg[1]=="cpu" then
  testinput = darkroomSimple.load(arg[2])
else
  testinput = darkroom.input(uint8)
end



function test(inast, inputList)

  local BLOCKX = 74
  local BLOCKY = 6

  if darkroom.ast.isAST(inast) then
  elseif type(inast)=="table" then
    for k,v in ipairs(inast) do
      local sz = math.floor(74/v[3]:sizeof())
      BLOCKX = math.min(sz,BLOCKX)
    end
  else
    assert(false)
  end

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
    io.output("out/"..arg[0]..".est.txt")
    io.write(est)
    io.close()
    io.output("out/"..arg[0]..".perlineest.txt")
    io.write(pl)
    io.close()
  elseif arg[1]=="build" then
    local hwinputs = inputList
    if hwinputs==nil then hwinputs={{testinput,"uart",darkroom.type.uint(8)}} end
    local hwoutputs = inast
    if darkroom.ast.isAST(hwoutputs) then
      hwoutputs = {{inast,"uart", darkroom.type.uint(8)}}
    end

    local v, metadata = fpga.compile(hwinputs, hwoutputs, 128, 64, BLOCKX, BLOCKY, fpga.util.deviceToOptions(arg[3]))
    local s = string.sub(arg[0],1,#arg[0]-4)
    io.output("out/"..s..".v")
    io.write(v)
    io.close()

    io.output("out/"..s..".metadata.lua")
    io.write("return {minX="..metadata.maxStencil:min(1)..",maxX="..metadata.maxStencil:max(1)..",minY="..metadata.maxStencil:min(2)..",maxY="..metadata.maxStencil:max(2)..",outputShift="..metadata.outputShift..",outputChannels="..metadata.outputChannels..",outputBytes="..metadata.outputBytes.."}")
    io.close()
  elseif arg[1]=="test" then
    print("TEST")

    local metadata = dofile(arg[3])

    local uartDevice = arg[4] or "/dev/tty.usbserial-142B"
    local outputFile = "out/"..arg[0]..".fpga.bmp"

    local terra test()
      var inputImg : Image
      inputImg:load([arg[2]])

      var outputImg = fpga.util.test(uartDevice, &inputImg, BLOCKX, BLOCKY, metadata.minX, metadata.minY, metadata.maxX, metadata.maxY, metadata.outputShift, metadata.outputChannels, metadata.outputBytes )

      outputImg:save(outputFile)
    end

    test()
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