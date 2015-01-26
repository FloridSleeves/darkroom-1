local fpga = {}
fpga.util = terralib.require("fpgautil")


BRAM_SIZE_BYTES = 2048

function concat(t1,t2)
    for i=1,#t1 do
      if type(t1[i])~="string" then
        print(t1[i])
        assert(false)
      end
    end

    for i=1,#t2 do
      assert(type(t2[i])=="string")
      t1[#t1+1] = t2[i]
    end
    return t1
end

function declareReg(type, name, initial, comment)
  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..initial
  end

  if type:isBool() then
    return "reg "..name..initial..";"..comment.."\n"
  else
    return "reg ["..(type:sizeof()*8-1)..":0] "..name..initial..";"..comment.."\n"
 end
end

function declareWire(ty, name, str, comment)
  assert(type(str)=="string" or str==nil)

  if comment==nil then comment="" end

  if str == nil or str=="" then
    str = ""
  else
    str = " = "..str
  end

  if ty:isBool() then
    return "wire "..name..str..";"..comment.."\n"
  else
    return "wire ["..(ty:sizeof()*8-1)..":0] "..name..str..";"..comment.."\n"
  end
end

function numToVarname(x)
  if x>0 then return x end
  if x==0 then return "0" end
  return "m"..math.abs(x)
end

function pointerToVarname(x)
  assert(type(x)=="table")
  return tostring(x):sub(10)
end

function kernelToVarname(x)
  if type(x)=="number" then return "_"..x
  else return "_"..x:name() end
end

fpga.modules = terralib.require("fpgamodules")

function getStencilCoord(rel, irRoot)
  assert(darkroom.IR.isIR(irRoot))
  if type(rel)=="number" then return rel end
  local s = rel:eval(1,irRoot)
  if s:area()==1 then
    return numToVarname(s:min(1))
  else
    -- this involves something like a mapreducevar
    return pointerToVarname(rel)
  end
end

function valueToVerilogLL(value,signed,bits)
  assert(type(value)=="number")

  if signed then
    if value==0 then
      return bits.."'d0"
    elseif value<0 then
      return "-"..bits.."'d"..math.abs(value)
    else
      return bits.."'d"..value
    end
  else
    assert(value>=0)
    return bits.."'d"..math.abs(value)
  end
end

function valueToVerilog(value,ty)

  if ty:isInt() then
    assert(type(value)=="number")
    if value==0 then
      return (ty:sizeof()*8).."'d0"
    elseif value<0 then
      return "-"..(ty:sizeof()*8).."'d"..math.abs(value)
    else
      return (ty:sizeof()*8).."'d"..value
    end
  elseif ty:isUint() then
    assert(type(value)=="number")
    assert(value>=0)
    return (ty:sizeof()*8).."'d"..value
  else
    assert(false)
  end
end

function astFunctions:codegenHW(kernel)
  assert(darkroom.typedAST.isTypedAST(kernel))
  if self.kind=="value" then
    return self.value
  elseif self.kind=="binop" and self.op=="+" then
    return "("..self.lhs:codegenHW(kernel)..")+("..self.rhs:codegenHW(kernel)..")"
  elseif self.kind=="binop" and self.op=="-" then
    return "("..self.lhs:codegenHW(kernel)..")-("..self.rhs:codegenHW(kernel)..")"
  elseif self.kind=="binop" and self.op=="*" then
    return "("..self.lhs:codegenHW(kernel)..")*("..self.rhs:codegenHW(kernel)..")"
  elseif self.kind=="unary" and self.op=="-" then
    return "-("..self.expr:codegenHW(kernel)..")"
  elseif self.kind=="iterationvar" then
    local I = kernel:lookup(self.iterateNode)
    return I._iterationvar:name()
  else
    print("internal error, couldn't codegen ast ", self.kind)
    assert(false)
  end

end

function astFunctions:evalFunrolled(dim, mrvValues)
  assert(type(dim)=="number")
  assert(type(mrvValues)=="table")

  if self.kind=="value" then
    assert(type(self.value)=="number")
    return Stencil.new():addDim(dim, self.value)
  elseif self.kind=="unary" and self.op=="-" then
    return self.expr:evalFunrolled(dim, mrvValues):flipDim(dim)
  elseif self.kind=="mapreducevar" then
    assert(false)
    print(type(mrvValues[self.variable]))
    assert(type(mrvValues[self.variable])=="number")
    return Stencil.new():addDim(dim, mrvValues[self.variable])
  elseif self.kind=="binop" and self.op=="+" then
    return self.lhs:evalFunrolled(dim, mrvValues):sum(self.rhs:evalFunrolled(dim, mrvValues))
  elseif self.kind=="binop" and self.op=="-" then
    return self.lhs:evalFunrolled(dim, mrvValues):sum(self.rhs:evalFunrolled(dim, mrvValues):flipDim(dim))
  elseif self.kind=="binop" and self.op=="*" then
    return self.lhs:evalFunrolled(dim, mrvValues):product(self.rhs:evalFunrolled(dim, mrvValues))
  else
    print("internal error, couldn't statically evaluate ", self.kind)
    assert(false)
  end
end

function getStencilCoordFunrolled(rel, mrvValues)
  if type(rel)=="number" then return rel end
  local s = rel:evalFunrolled(1, mrvValues)
  s:print()
  assert(s:area()==1)
  return numToVarname(s:min(1))
end

function delayToXY(delay, width)
  local lines = math.floor(delay/width)
  local xpixels = delay - lines*width
  return xpixels, lines
end

STUPIDGLOBALinternalDelays = {}

function kernelGraphFunctions:internalDelay()
  return STUPIDGLOBALinternalDelays[self]
end

function kernelGraphFunctions:xySource(root, pipelineRetiming)
  local xys
  print("START")
  for _,v in self:inputs() do
    -- I think at least one input should have a delay difference of 0
    -- Use this for the x,y input so that we don't have to retime it
    print(pipelineRetiming[self],self:internalDelay(),pipelineRetiming[v])
    if pipelineRetiming[self]-self:internalDelay()-pipelineRetiming[v]==0 then
      xys=v
    end
  end
  assert(xys~=nil or self:inputCount()==0) -- this means that every kernel we read from has a delay? Is this possible?
  return xys
end

function typedASTFunctions:cname(c)
  return self:name().."_c"..c
end

function typedASTFunctions:internalDelay(root)
  assert(darkroom.typedAST.isTypedAST(root))

  if self.kind=="gatherColumn" then
    return 2
  elseif self.kind=="binop" or self.kind=="unary" or self.kind=="select" or self.kind=="crop" or self.kind=="vectorSelect" then
    return 1
  elseif self.kind=="load" or self.kind=="value" or self.kind=="cast" or self.kind=="position" or self.kind=="mapreducevar" or self.kind=="array" or self.kind=="iterationvar" or self.kind=="iterateload" then
    return 0
  elseif self.kind=="lifted"  then
    -- nasty: lifted variables have to have their delay be correct, 
    -- so we need to look up where the variable is actually calculated, and get its retiming delay
    local MR = root:lookup(self.liftedTarget)
    local R
    for k,v in pairs(MR) do 
      local tk = "lifted"..self.id
      if k:sub(1,#tk)==tk then
        local liftedNode = v
        local RT = fpga.trivialRetime(liftedNode,root)
        local res =  RT[liftedNode]
        if R==nil then R=res
        else assert(R==res) end
      end
    end
    return R
  elseif self.kind=="index" then
    local area = self.index:eval(1,root):bbArea()
    if area==1 then
      return 0
    else
      return math.ceil(math.log(area)/math.log(2)) -- for the reduce
    end
  elseif self.kind=="iterate" then
    return self.iterationSpaceHigh-self.iterationSpaceLow+1
  elseif self.kind=="mapreduce" then
    -- the reason we don't have to account for the math within the loop is
    -- that this node points to that math, so its delay on the input will include the delay of the inside of the loop
    local area = 1
    local i=1
    while self["varname"..i] do
      area = area * (self["varhigh"..i]-self["varlow"..i]+1)
      i = i + 1
    end

    return math.ceil(math.log(area)/math.log(2)) -- for the reduce
  elseif self.kind=="reduce" then
    return math.ceil(math.log(self:arraySize("expr"))/math.log(2)) -- for the reduce
  elseif self.kind=="gather" then
    local area = (self.maxX*2+1)*(self.maxY*2+1)
    -- for the reduce, and one extra to calculate the valid pixel
    return math.ceil(math.log(area)/math.log(2))+1
  else
    print(self.kind)
    assert(false)
  end
end

-- The retiming number is the delay at the output of the node.
-- This dumb retiming function puts all the input (leaf) nodes at delay 0.
-- The one output node's delay is the delay for the entire pipeline.
-- Nodes can have 'internal' delays. These are the delays inside the node.
-- eg a big reduce takes 5 cycles etc. The number of pipelining registers
-- we need to create is the difference in delays minus the internal delays.
--
-- Remember, this is not at all affected by the darkroom schedule shifts.
-- the darkroom schedules takes a pipeline, and produces a pipeline.
-- There is no side-band information needed to implement the pipeline the
-- scheduler produces. So we can totally ignore the darkroom schedule here,
-- and just rate match due to the extra retiming registers we introduced.
function fpga.trivialRetime(AST,root)
  assert(darkroom.typedAST.isTypedAST(AST) or darkroom.kernelGraph.isKernelGraph(AST))
  assert(darkroom.typedAST.isTypedAST(root) or darkroom.kernelGraph.isKernelGraph(root))
  local retiming = {}

  AST:visitEach(
    function(n, inputs)
      local maxDelay = 0
      for k,v in n:inputs() do
        -- only retime nodes that are actually used
        if (darkroom.typedAST.isTypedAST(v)==false or v:codegened(root)) and inputs[k]>maxDelay then maxDelay = inputs[k] end
      end
      retiming[n] = maxDelay + n:internalDelay(root)
      return retiming[n]
    end)

  return retiming
end

local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}
local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!="}

function fpga.codegenKernel(compilerState, kernelGraphNode, retiming, imageWidth, imageHeight, kernelGraphRoot, pipelineRetiming, shift, inputLinebuffers, outputUsedAsRegular, options,largestEffectiveCycles)
  assert(type(imageWidth)=="number")
  assert(type(imageHeight)=="number")
  assert(darkroom.kernelGraph.isKernelGraph(kernelGraphRoot))
  assert(type(pipelineRetiming)=="table")
  assert(type(shift)=="number")
  assert(type(inputLinebuffers)=="table")
  assert(type(options)=="table")

  local kernel = kernelGraphNode.kernel

  local inputs = ""

  if kernelGraphNode:inputCount()==0 then
    assert(kernel:S("load"):count()<=1)
    kernel:S("load"):traverse(
      function(n)
        inputs = "input ["..(n.type:sizeof()*8-1)..":0] in_"..n.from.."_x0_y0,\n"
      end)
  else
    for _, inputLinebuffer in pairs(inputLinebuffers) do
      if inputLinebuffer.kind=="regular" then
        for k,v in kernelGraphNode:inputs() do
          if outputUsedAsRegular[kernelGraphNode][v] then
            local s = kernel:stencil(v,kernel)
            for x=s:min(1),s:max(1) do
              for y=s:min(2), s:max(2) do
                inputs = inputs.."input ["..(v.kernel.type:sizeof()*8-1)..":0] in_"..v:name().."_x"..numToVarname(x).."_y"..numToVarname(y)..",\n"
              end
            end
          end
        end
        
      elseif inputLinebuffer.kind=="gatherColumn" then
        local bytesPerPixel = inputLinebuffer.from.kernel.type:baseType():sizeof()
        local extraBits = math.log(bytesPerPixel)/math.log(2)
        inputs = inputs.."output ["..(10-extraBits)..":0] gatherAddress_"..pointerToVarname(inputLinebuffer.key)..","
        inputs = inputs.."output gatherReadInNextCycleX_"..pointerToVarname(inputLinebuffer.key)..","
        inputs = inputs.."output gatherReadInNextCycleY_"..pointerToVarname(inputLinebuffer.key)..","
        inputs = inputs.."output gatherValidInNextCycle_"..pointerToVarname(inputLinebuffer.key)..","

        for y=-inputLinebuffer.linebufferSizeY,0 do
          inputs = inputs.."input ["..(bytesPerPixel*8-1)..":0] in_gatherColumn_"..pointerToVarname(inputLinebuffer.key).."_x0_y"..numToVarname(y)..","
        end
      else
        assert(false)
      end
    end
  end

  local result = {"module Kernel_"..kernelGraphNode:name().."(input CLK, input[12:0] inX, input[12:0] inY, output[12:0] outX, output[12:0] outY, input [7:0] cycle, output [7:0] cycleOut, \n"..inputs.."output ["..(kernel.type:sizeof()*8-1)..":0] out, input validIn, output validOut, output rwValidOutX, output rwValidOutY);\n"}
  local clockedLogic = {}

  table.insert(result,"wire [12:0] inX_0;\n")
  table.insert(result,"assign inX_0 = inX;\n")
  table.insert(result,"wire [12:0] inY_0;\n")
  table.insert(result,"assign inY_0 = inY;\n")
  table.insert(result,"wire [7:0] cycle_0;\n")
  table.insert(result,"assign cycle_0 = cycle;\n")

  local shiftX, shiftY = delayToXY(shift, options.stripWidth)
  local shiftT={shiftX,shiftY}

  table.insert(result,"wire validOut_0;\n")
  table.insert(result,"assign validOut_0 = validIn;\n")

  for i=1,2 do
    local coord = "X"
    if i==2 then coord="Y" end
    table.insert(result,"wire [12:0] in"..coord.."_internal;\n")
    table.insert(result,"wire [12:0] in"..coord.."_shifted;\n")
    table.insert(result,"assign in"..coord.."_shifted = in"..coord.." - 13'd"..shiftT[i]..";\n")
    table.insert(result,"wire rwValidOut"..coord.."_0;\n")
    if i==2 then table.insert(result,"wire [7:0] cycle_internal_0;\n") end
    
    local rate = looprate(kernel["scaleN"..i],kernel["scaleD"..i],1)

    if rate==1 then
      table.insert(result,"assign in"..coord.."_internal = in"..coord..";\n")        
      if i==2 then table.insert(result,"assign cycle_internal_0 = cycle;\n") end
      if largestEffectiveCycles>1 then
        table.insert(result,"assign rwValidOut"..coord.."_0 = (cycle=="..valueToVerilogLL(largestEffectiveCycles-1,false,8)..");\n")
      else
        table.insert(result,"assign rwValidOut"..coord.."_0 = 1;\n")
      end
    else

      local sft = math.log(rate)/math.log(2)
      assert(math.floor(sft)==sft)
      table.insert(result,"assign in"..coord.."_internal = in"..coord.." >> "..sft..";\n")
      if i==1 then
        table.insert(result,"assign rwValidOut"..coord.."_0 = ( in"..coord.."_shifted["..(sft-1)..":0] =="..sft.."'d"..(rate-1)..") & (cycle=="..valueToVerilogLL(largestEffectiveCycles-1,false,8)..");\n")
      else
        table.insert(result,"assign rwValidOut"..coord.."_0 = ( (in"..coord.."_shifted["..(sft-1)..":0] =="..sft.."'d0 & inX!=12'd"..(options.stripWidth-1+options.padMinX)..") | ((inX==12'd"..(options.stripWidth-1+options.padMinX)..") & (inY_shifted["..(sft-1)..":0]=="..sft.."'d"..(rate-1).."))) & (cycle=="..valueToVerilogLL(largestEffectiveCycles-1,false,8)..");\n")
      end
      if i==2 then table.insert(result,"assign cycle_internal_0 = {cycle["..(7-sft)..":0],inX_shifted["..(sft-1)..":0]};\n") end
    end
  end

  local mdeclarationsSeen = {}
  local mdeclarations = {}
  local mclockedLogicSeen = {}
  local mclockedLogic = {}

  local function addtab(bb,decl,tab,tabSeen,contents)
    assert(type(decl)=="table")

    tab[bb] = tab[bb] or {}
    tabSeen[bb] = tabSeen[bb] or {}

    if contents~=nil then
      assert(type(contents)=="table")
      for k,v in pairs(contents) do
        for kk,vv in pairs(v) do
          assert(type(vv)=="string")
          assert(tabSeen[bb][vv] == nil);
        end
      end
    end
    
    for k,v in ipairs(decl) do
      assert(type(v)=="string")
--      print("SEEN",v)
--      assert(tabSeen[bb][v] == nil);
      table.insert(tab[bb],v)
      tabSeen[bb][v] = 1
    end
  end
  local function adddecl(bb,decl,contents) addtab(bb,decl,mdeclarations,mdeclarationsSeen,contents) end
  local function addclocked(bb,decl,contents) addtab(bb,decl,mclockedLogic,mclockedLogicSeen,contents) end

  local interface = {}
  local function recordInterface(n,inputs)
    local nbb = n:calculateMinBB(kernel)
    for k,v in n:inputs() do
      local outer = v:calculateMinBB(kernel)
      local inner = nbb
      -- we need to thread this up through all the enclosing scopes
      -- we only care about threading stuff from outer scopes into inner scopes, not the other way around
      while inner~=outer and inner.level > outer.level do
        interface[inner] = interface[inner] or {}
        interface[inner][outer] = interface[inner][outer] or {}
        for c,vv in pairs(inputs[k]) do
          table.insert(interface[inner][outer], {vv,v.type:baseType()})
        end
        print(inner.level, outer.level, #inner.parents)
        assert(keycount(inner.parents)>0)
        -- just choose arbitrarily
        local p
        for k,v in pairs(inner.parents) do p=k end
        inner = p
      end
    end
  end
  local function getInterface(bb,formal)
    if interface[bb]==nil or bb==darkroom.typedAST._topbb then return {} end
    local t = {}
    local seen = {}
    for _,obb in pairs(interface[bb]) do
      for _,variable in pairs(obb) do
        if seen[variable[1]]==nil then
          if formal then
            table.insert(t,"input ["..(variable[2]:sizeof()*8-1)..":0] "..variable[1]..", // from parent scope\n")
          else
            table.insert(t,",."..variable[1].."("..variable[1]..")")
          end
          seen[variable[1]]=1
        end
      end
    end
    return t
  end

  -- these variable only serve to delay the input x,y to the output x,y
  -- They are not used internally by this kernel - the x,y used
  -- internally by the kernel are delayed using the normal retiming infrastructure.
  -- Potentially, we could accomplish the same thing with adding a delay
  -- to x,y using an add operator, which may be better in some cases?
  for i=1,retiming[kernel] do
    adddecl(darkroom.typedAST._topbb,{"reg [12:0] inX_"..i..";\n"})
    adddecl(darkroom.typedAST._topbb,{"reg [12:0] inY_"..i..";\n"})
    adddecl(darkroom.typedAST._topbb,{"reg [7:0] cycle_"..i.." = "..valueToVerilogLL(largestEffectiveCycles-1,false,8)..";\n"})
    adddecl(darkroom.typedAST._topbb,{"reg [7:0] cycle_internal_"..i..";\n"})
    adddecl(darkroom.typedAST._topbb,{"reg rwValidOutX_"..i.." = 1'b0;\n"})
    adddecl(darkroom.typedAST._topbb,{"reg rwValidOutY_"..i.." = 1'b0;\n"})
    adddecl(darkroom.typedAST._topbb,{"reg validOut_"..i.." = 1'b0;\n"})
    addclocked(darkroom.typedAST._topbb, {"inX_"..i.." <= inX_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"inY_"..i.." <= inY_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"cycle_"..i.." <= cycle_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"cycle_internal_"..i.." <= cycle_internal_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"rwValidOutX_"..i.." <= rwValidOutX_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"rwValidOutY_"..i.." <= rwValidOutY_"..(i-1)..";\n"})
    addclocked(darkroom.typedAST._topbb, {"validOut_"..i.." <= validOut_"..(i-1)..";\n"})
  end

  adddecl(darkroom.typedAST._topbb,{"assign outX = inX_"..retiming[kernel]..";\n"})
  adddecl(darkroom.typedAST._topbb,{"assign outY = inY_"..retiming[kernel]..";\n"})
  adddecl(darkroom.typedAST._topbb,{"assign cycleOut = cycle_"..retiming[kernel]..";\n"})
  adddecl(darkroom.typedAST._topbb,{"assign rwValidOutX = rwValidOutX_"..retiming[kernel]..";\n"})
  adddecl(darkroom.typedAST._topbb,{"assign rwValidOutY = rwValidOutY_"..retiming[kernel]..";\n"})
  adddecl(darkroom.typedAST._topbb,{"assign validOut = validOut_"..retiming[kernel]..";\n"})

  local finalOut = kernel:visitEach(
    function(n, args)

      if n:codegened(kernel)==false then
        local t = {}
        for c=1,n.type:channels() do t="ERROR_UNUSED_VAR" end
        return {t}
      end

      local inputs = {}

      for k,v in pairs(args) do
        inputs[k] = {}
        for c=1,n[k].type:channels() do inputs[k][c] = args[k][1][c] end
      end

      recordInterface(n,inputs) -- used to make argument list for modules

      if not (n.type:baseType():isInt() or n.type:baseType():isUint() or n.type:baseType():isBool()) then
        darkroom.error("Only integer types are allowed "..n.type:str(), n:linenumber(), n:offset(), n:filename())
      end

      local bb = n:calculateMinBB(kernel)

      -- insert pipeline delays
      local retimeSeen = {} -- it's possible for a node to use another node multiple times.  Don't double add its retiming delays.
      for k,v in n:inputs() do
        if v:codegened(kernel) and k:sub(1,1)~="_" and (n.kind=="mapreduce" and k=="expr")==false and (n.kind=="iterate" and k=="expr")==false then -- only retime nodes we actually use
          local delays = retiming[n] - retiming[v] - n:internalDelay(kernel)
          assert(delays>=0)
          
          local inputbb = v:calculateMinBB(kernel)
          -- we should only be retiming stuff from shallower scopes to deeper scopes
          -- we place the retiming delays in the deeper scope, b/c this is where they will be consumed
          assert(inputbb.level<=bb.level)

          for c=1,v.type:channels() do
            local prev = inputs[k][c]
            for i=1, delays do
              local sn = inputs[k][c].."_to_"..n:cname(c).."_retime"..i
              -- type is determined by producer, b/c consumer op can change type
              local d = declareReg( v.type:baseType(), sn, "", " // retiming "..retiming[v].." to "..retiming[n].."-"..n:internalDelay(kernel) )
              local cl = sn.." <= "..prev.."; // retiming\n"
              if retimeSeen[d]==nil then adddecl(bb, {d}); retimeSeen[d]=1 end
              if retimeSeen[cl]==nil then addclocked(bb, {cl}); retimeSeen[cl]=1 end
              prev = sn
            end
            if delays>0 then inputs[k][c] = inputs[k][c].."_to_"..n:cname(c).."_retime"..delays end
          end
        end
      end

      local finalOut = {}

      -- mapreduce mixes channels is weird ways, so codegen this separately
      if n.kind=="mapreduce" then
        local moduledef = {"module Map_"..n:name().."(input CLK, input[12:0] inX_internal, input[12:0] inY_internal, \n"}

        local exprbb = n.expr:calculateMinBB(kernel)
        local declexprbb = mdeclarations[exprbb]
        local clockedexprbb = mclockedLogic[exprbb]
        local extraInterfaceFormal = {}
        local extraInterfaceActual = {}
        if bb==exprbb then 
          -- even though we don't calculate anything inside the module, we need to thread the output
          for k,v in pairs(inputs.expr) do
            table.insert(extraInterfaceFormal, "input ["..(n.expr.type:sizeof()*8-1)..":0] "..v..",")
            table.insert(extraInterfaceActual, ",."..v.."("..v..")")
          end
          declexprbb={};clockedexprbb={} 
        end

        local i = 1
        while n["varname"..i] do
          table.insert(moduledef,"input[31:0] mrvar_"..n["varname"..i]..",\n")
          i=i+1
        end

        for i=1,n["countLifted"] do
          table.insert(moduledef,"input ["..(n["typeLifted"..i]:sizeof()*8-1)..":0] lifted"..i..",\n")
        end
        moduledef = concat(moduledef,getInterface(exprbb,true))

        table.insert(moduledef,"output ["..(n.expr.type:sizeof()*8-1)..":0] out);\n\n")

        table.insert(moduledef,table.concat(declexprbb,""))
        table.insert(moduledef,"always @ (posedge CLK) begin\n"..table.concat(clockedexprbb,"").."end\n")

        table.insert(moduledef,"assign out = {"..inputs.expr[#inputs.expr])
        local c = #inputs.expr-1
        while c>=1 do table.insert(moduledef,","..inputs.expr[c]); c=c-1 end
        table.insert(moduledef, "};\n")
        table.insert(moduledef,"endmodule\n\n")

        result = concat(moduledef,result)

        for k,v in pairs(n) do
          if k:sub(0,6)=="lifted" then
            -- assert(retiming[v]==0) -- we don't support pipelining lifted stuff
            assert(v.kind=="load" or v.kind=="index" or v.kind=="lifted")
          end
        end

        -- funroll
        local partials = -1
        local argminPartials = ""
        local funroll = {function(inputList, mrvValues) 
                           partials = partials+1; 
                           if n.reduceop=="argmin" then argminPartials = argminPartials..",.partial"
                             local i=1
                             while n["varname"..i] do argminPartials = argminPartials.."_"..n["varname"..i]..numToVarname(mrvValues[n["varname"..i]]); i=i+1; end
                             argminPartials = argminPartials.."("..n:name().."_partial"..partials..")"
                           end
                           local liftedInputs = ""
                           local term = ""
                           local i=1
                           while n["varname"..i] do
                             term = term.."_"..n["varname"..i]..numToVarname(mrvValues[n["varname"..i]])
                             i = i + 1
                           end
                           for i=1,n["countLifted"] do
                             local v = "lifted"..i..term
                             liftedInputs = liftedInputs..",.lifted"..i.."({"
                             -- pack the channels
                             local c = n[v].type:channels()
                             while c>=1 do
                               liftedInputs = liftedInputs..args[v][1][c]
                               if c~=1 then liftedInputs = liftedInputs.."," end
                               c = c - 1
                             end
                             liftedInputs = liftedInputs.."})"
                           end

                           return {declareWire(n.expr.type,n:name().."_partial"..partials).."Map_"..n:name().." map_"..n:name().."_"..partials.."(.CLK(CLK),.out("..n:name().."_partial"..partials.."),.inX_internal(inX_internal),.inY_internal(inY_internal)"..inputList..liftedInputs..table.concat(getInterface(exprbb,false),"")..");\n"} end}

        local i = 1
        while n["varname"..i] do
          local ii = i
          table.insert(funroll, function(inputList, mrvValues) local res = {}; for j=n["varlow"..ii],n["varhigh"..ii] do mrvValues[n["varname"..ii]]=j; res = concat(res, funroll[ii](",.mrvar_"..n["varname"..ii].."("..j..")"..inputList, mrvValues)) end; return res end)
          i=i+1
        end
        
        adddecl(bb, funroll[#funroll]("",{}))

        local rtype = n.expr.type:baseType()
        if n.reduceop=="argmin" then rtype=n.expr.type:baseType() end
        local rname, rmod = fpga.modules.reduce(compilerState, n.reduceop, partials+1, rtype, n)

        result = concat(rmod, result)

        local finalOut = {}

        if n.reduceop=="argmin" then
          for c=1,n.type:channels() do adddecl(bb, {declareWire(n.type:baseType(), n:cname(c))}) end
          adddecl(bb,{rname.." reduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(n.type:channels())..")"})
          for c=1,n.type:channels()-1 do adddecl(bb, {",.out_"..n["varname"..c].."("..n:cname(c)..")"}) end
          adddecl(bb,{argminPartials..");\n"})
          for c=1,n.type:channels() do table.insert(finalOut, n:cname(c)) end
        else
          for c=1,n.type:channels() do
            adddecl(bb, {declareWire(n.type:baseType(), n:cname(c))})
            adddecl(bb, {rname.." reduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(c)..")"})
            local bits = n.type:baseType():sizeof()*8
            for i=0,partials do adddecl(bb,{",.partial_"..i.."("..n:name().."_partial"..i.."["..(bits*c-1)..":"..(bits*(c-1)).."])"}) end
            adddecl(bb,{");\n"})
            table.insert(finalOut, n:cname(c))
          end
        end
        return {finalOut}
      elseif n.kind=="iterate" then
        local moduledef = {"module Iterate_"..n:name().."(input CLK, input[12:0] inX_internal, input[12:0] inY_internal, input [7:0] cycle_internal_0,\n"}

        local gatherInputs = ""
        local i=1
        while n["loadname"..i] do
          local le = n["_loadexpr"..i]
          if le.kind=="gatherColumn" then
            local bytesPerPixel = le._input.from.kernel.type:baseType():sizeof()
            local extraBits = math.log(bytesPerPixel)/math.log(2)
            table.insert(moduledef,"output ["..(10-extraBits)..":0] gatherAddress_"..pointerToVarname(le.__key)..",")
            gatherInputs = gatherInputs..",.gatherAddress_"..pointerToVarname(le.__key).."(gatherAddress_"..pointerToVarname(le.__key)..")"
            for y=-(le.columnEndY-le.columnStartY),0 do
              table.insert(moduledef,"input ["..(bytesPerPixel*8-1)..":0] in_gatherColumn_"..pointerToVarname(le.__key).."_x0_y"..numToVarname(y)..",")
              gatherInputs = gatherInputs..",.in_gatherColumn_"..pointerToVarname(le.__key).."_x0_y"..numToVarname(y).."(in_gatherColumn_"..pointerToVarname(le.__key).."_x0_y"..numToVarname(y)..")"
            end
          else
            assert(false)
          end

          i = i + 1
        end

        local exprbb = n.expr:calculateMinBB(kernel)
        local declexprbb = mdeclarations[exprbb]
        local clockedexprbb = mclockedLogic[exprbb]
        local extraInterfaceFormal = {}
        local extraInterfaceActual = {}
        if bb==exprbb then 
          -- even though we don't calculate anything inside the module, we need to thread the output
          for k,v in pairs(inputs.expr) do
            table.insert(extraInterfaceFormal, "input ["..(n.expr.type:sizeof()*8-1)..":0] "..v..",")
            table.insert(extraInterfaceActual, ",."..v.."("..v..")")
          end
          declexprbb={};clockedexprbb={} 
        end

        moduledef = concat(moduledef,getInterface(exprbb,true))
        moduledef = concat(moduledef,extraInterfaceFormal)

        table.insert(moduledef,"output ["..(n.expr.type:sizeof()*8-1)..":0] out);\n\n")

        table.insert(moduledef,table.concat(declexprbb,""))
        table.insert(moduledef,"always @ (posedge CLK) begin\n"..table.concat(clockedexprbb,"").."end\n")

        table.insert(moduledef,"assign out = {"..inputs.expr[#inputs.expr])
        local c = #inputs.expr-1
        while c>=1 do table.insert(moduledef,","..inputs.expr[c]); c=c-1 end
        table.insert(moduledef, "};\n")
        table.insert(moduledef,"endmodule\n\n")

        result = concat(moduledef,result)

        adddecl(bb,{declareWire(n.expr.type,"iterate_"..n:name().."_out")})
        adddecl(bb,{"Iterate_"..n:name().." iterate_"..n:name().."(.CLK(CLK),.inX_internal(inX_internal),.inY_internal(inY_internal),.cycle_internal_0(cycle_internal_0)"..table.concat(getInterface(exprbb,false))..table.concat(extraInterfaceActual)..gatherInputs..",.out(iterate_"..n:name().."_out));\n"})

        local finalOut = {}
        if n.reduceop=="sum" then
          for c=1,n.type:channels() do
            adddecl(bb,{declareReg(n.expr.type,n:cname(c))})
            -- implement the serial reduction
            addclocked(bb,{[=[if (cycle_internal_]=]..(retiming[n]-n:internalDelay(kernel))..[=[==0) begin
  ]=]..n:cname(c)..[=[ <= iterate_]=]..n:name()..[=[_out;
  end else if (cycle_internal_]=]..(retiming[n]-n:internalDelay(kernel))..[=[ < ]=]..n.cycles..[=[) begin
  ]=]..n:cname(c)..[=[ <= ]=]..n:cname(c)..[=[ + iterate_]=]..n:name()..[=[_out;
end
]=]})
            table.insert(finalOut, n:cname(c))
          end
        else
          assert(false)
        end

        return {finalOut}
      end

      for c=1,n.type:channels() do
        local res
        local resDeclarations = {}
        local resClockedLogic = {}

        if n.kind=="binop" then
          table.insert(resDeclarations, declareReg( n.type:baseType(), n:cname(c) ))

          if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
            if n.type:baseType():isBool() and n.lhs.type:baseType():isInt() and n.rhs.type:baseType():isInt() then
              table.insert(resClockedLogic, n:name().."_c"..c.." <= ($signed("..inputs.lhs[c]..")"..n.op.."$signed("..inputs.rhs[c].."));\n")
            elseif n.type:baseType():isBool() and n.lhs.type:baseType():isUint() and n.rhs.type:baseType():isUint() then
              table.insert(resClockedLogic, n:name().."_c"..c.." <= (("..inputs.lhs[c]..")"..n.op.."("..inputs.rhs[c].."));\n")
            else
              print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
              assert(false)
            end
          elseif n.type:isBool() then
            local op = binopToVerilogBoolean[n.op]
            if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
            table.insert(resClockedLogic, n:name().."_c"..c.." <= "..inputs.lhs[c]..op..inputs.rhs[c]..";\n")
          else
            local op = binopToVerilog[n.op]
            if type(op)~="string" then print("OP",n.op); assert(false) end
            local lhs = inputs.lhs[c]
            if n.lhs.type:baseType():isInt() then lhs = "$signed("..lhs..")" end
            local rhs = inputs.rhs[c]
            if n.rhs.type:baseType():isInt() then rhs = "$signed("..rhs..")" end
            table.insert(resClockedLogic, n:name().."_c"..c.." <= "..lhs..op..rhs..";\n")
          end

          res = n:name().."_c"..c
        elseif n.kind=="unary" then
          if n.op=="abs" then
            if n.type:baseType():isInt() then
              table.insert(resDeclarations, declareReg( n.type:baseType(), n:cname(c) ))
              table.insert(resClockedLogic, n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs\n")
              res = n:cname(c)
            else
              return inputs.expr[c] -- must be unsigned
            end
          elseif n.op=="-" then
            assert(n.type:baseType():isInt())
            table.insert(resDeclarations, declareReg(n.type:baseType(),n:cname(c)))
            table.insert(resClockedLogic, n:cname(c).." <= -"..inputs.expr[c].."; // unary sub\n")
            res = n:cname(c)
          else
            print(n.op)
            assert(false)
          end
        elseif n.kind=="select" or n.kind=="vectorSelect" then
          table.insert(resDeclarations,declareReg( n.type:baseType(), n:cname(c), "", " // "..n.kind.." result" ))
          local condC = 1
          if n.kind=="vectorSelect" then condC=c end

          table.insert(resClockedLogic, n:cname(c).." <= ("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n")
          res = n:cname(c)
        elseif n.kind=="load" then
          assert(retiming[n]==0)
          local v = "in"..kernelToVarname(n.from).."_x"..getStencilCoord(n.relX,kernel).."_y"..getStencilCoord(n.relY,kernel)
          local tys = n.type:baseType():sizeof()*8
          table.insert(resDeclarations,declareWire( n.type:baseType(), n:cname(c), v.."["..(c*tys-1)..":"..((c-1)*tys).."]"," // load" ))
          res = n:cname(c)
        elseif n.kind=="position" then
          assert(retiming[n]==0)
          local str = "inX_internal"
          if n.coord=="y" then str="inY_internal" end
          table.insert(resDeclarations, declareWire(n.type, n:name(), str))
          res = n:name()
        elseif n.kind=="crop" then
          local delay = retiming[n] - n:internalDelay(kernel)
          table.insert(resDeclarations, declareReg( n.type:baseType(), n:cname(c) ))
          -- hilariously, this also checks for values <0, b/c values <= in 2s complement are large, larger than image width...
          table.insert(resClockedLogic, n:cname(c).." <= ((inX_"..delay.."-"..n.shiftX..")>="..imageWidth.." || (inY_"..delay.."-"..n.shiftY..")>="..imageHeight..")?(0):("..inputs.expr[c].."); // crop\n")
          res = n:cname(c)
        elseif n.kind=="cast" then
          local expr
          local cmt = " // cast "..n.expr.type:str().." to "..n.type:str()
          if n.type:isArray() and n.expr.type:isArray()==false then
            expr = inputs["expr"][1] -- broadcast
            cmt = " // broadcast "..n.expr.type:str().." to "..n.type:str()
          else
            expr = inputs["expr"][c]
          end

          if n.type:isInt() and n.expr.type:isInt() and n.type:sizeof()>n.expr.type:sizeof() then
            -- must sign extend
            expr = "{ {"..(8*(n.type:sizeof()-n.expr.type:sizeof())).."{"..expr.."["..(n.expr.type:sizeof()*8-1).."]}},"..expr.."["..(n.expr.type:sizeof()*8-1)..":0]}"
          end
          
          table.insert(resDeclarations, declareWire(n.type:baseType(), n:cname(c), "",cmt))
          table.insert(resDeclarations, "assign "..n:cname(c).." = "..expr..";"..cmt.."\n")
          res = n:cname(c)
        elseif n.kind=="value" then
          local v
          if type(n.value)=="table" then 
            v = valueToVerilog(n.value[c], n.type:baseType()) 
          else
            v = valueToVerilog(n.value, n.type:baseType())
          end
          table.insert(resDeclarations,declareWire(n.type:baseType(), n:cname(c), v, " //value" ))
          res = n:cname(c)
        elseif n.kind=="mapreducevar" then
          local MR = kernel:lookup(n.mapreduceNode)
          res = "mrvar_"..MR["varname"..n.id]
        elseif n.kind=="iterationvar" then
          --res = "iterationvar_"..n.varname

          local I = kernel:lookup(n.iterateNode)
print("CGIV",n.iterateNode,n,I._iterationvar,I._iterationvar.kind)
          table.insert(resDeclarations, declareWire(n.type:baseType(), n:name(), ""," // iteration var"))
          table.insert(resDeclarations, "assign "..n:name().." = cycle_internal_0+("..valueToVerilogLL(I.iterationSpaceLow,true,32).."); // iteration var\n")
          res = n:name()
        elseif n.kind=="iterateload" then
          res = "iterateload_"..n.varname.."_c"..c
        elseif n.kind=="array" then
          res = inputs["expr"..c][1]
        elseif n.kind=="index" then
          if n.index:eval(1,kernel):bbArea()==1 then
            res = inputs["expr"][n.index:eval(1,kernel):min(1)+1]
        else
        for k,v in pairs(n) do print(k,v) end
            local range = n.index:eval(1,kernel)
            -- synth a reduction tree to select the element we want
            local rname, rmod = fpga.modules.reduce(compilerState, "valid", range:bbArea(), n.type)
            result = concat(rmod, result)
            table.insert(resDeclarations, declareWire(n.type, n:cname(c),"", "// index result"))
            local str = rname.." indexreduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(c)..")"
            for i=range:min(1), range:max(1) do
              local idx = i-range:min(1)
              str = str..",.partial_"..idx.."("..inputs["expr"][i+1]..")"
              str = str..",.partial_valid_"..idx.."("..n.index:codegenHW(kernel).." == "..valueToVerilogLL(i,true,32)..")"
            end
            table.insert(resDeclarations,str..");\n")
            res = n:cname(c)
          end
        elseif n.kind=="reduce" then
          local rname, rmod = fpga.modules.reduce(compilerState, n.op, n:arraySize("expr"), n.type)
          result = concat(rmod, result)
          table.insert(resDeclarations, declareWire(n.type, n:cname(c),"", "// reduce result"))
          local str = rname.." reduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(c)..")"
          n:map("expr",function(_,i) str = str..",.partial_"..(i-1).."("..inputs["expr"..i][c]..")" end)
          table.insert(resDeclarations,str..");\n")
          res = n:cname(c)
        elseif n.kind=="gather" then
          local area = (n.maxX*2+1)*(n.maxY*2+1)
          local rname, rmod = fpga.modules.reduce(compilerState, "valid", area, n.type)
          result = concat(rmod, result)
          
          table.insert(resDeclarations, declareWire(n.type, n:cname(c),"", "// gather result"))

          local str = rname.." gatherreduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(c)..")"
          local cnt = 0
          for gx=-n.maxX, n.maxX do
            for gy=-n.maxY, n.maxY do
              local relX = n._input.relX
              local relY = n._input.relY
              if type(relX)~="number" then
                relX = relX:eval(1,kernel)
                assert(relX:area()==1)
                relX = relX:min(1,kernel)
              end

              if type(relY)~="number" then
                relY = relY:eval(1,kernel)
                assert(relY:area()==1)
                relY = relY:min(1,kernel)
              end

              local v = n:cname(c).."_valid_x"..numToVarname(gx+relX).."_y"..numToVarname(gy+relY)
              
              -- gather is weird b/c it reads the whole stencil, so instead of using the regular retiming infrastructure, we do the retiming here
              -- TODO: should probably modify this so that it uses the regular retiming infrasturcture.
              -- plus, it takes one clock cycle to calculate the valid bits, so we also need to delay the input stencil 1 extra clock cycle
              local gatherRetimeDelay = retiming[n] - n:internalDelay(kernel) + 1
              for d=1,gatherRetimeDelay do
                table.insert(resDeclarations, declareReg(n._input.type, n:cname(c).."_partial_"..cnt.."_"..d,"", "// gather input delay"))
                if d==1 then
                  table.insert(resClockedLogic, n:cname(c).."_partial_"..cnt.."_"..d.." <= in"..kernelToVarname(n._input.from).."_x"..numToVarname(gx+relX).."_y"..numToVarname(gy+relY).."; // gather input delay\n")
                else
                  table.insert(resClockedLogic, n:cname(c).."_partial_"..cnt.."_"..d.." <= "..n:cname(c).."_partial_"..cnt.."_"..(d-1).."; // gather input delay\n")
                end
              end

              str = str .. ",.partial_"..cnt.."("..n:cname(c).."_partial_"..cnt.."_"..gatherRetimeDelay..")"
              str = str .. ",.partial_valid_"..cnt.."("..v..")"
              cnt = cnt + 1
              table.insert(resDeclarations, declareReg(darkroom.type.bool(), v,"", "// gather valid"))
              table.insert(resClockedLogic, v.." <= ("..inputs.x[1].."=="..valueToVerilog(gx,n.x.type)..") && ("..inputs.y[1].."=="..valueToVerilog(gy,n.y.type).."); // gather select\n")
            end
          end

          table.insert(resDeclarations,str..");\n")
          res = n:cname(c)
        elseif n.kind=="gatherColumn" then
          -- we delay the input address 1 cycle: this is so that the kernel that we're consuming from has time
          -- to complete its write. Ie, it writes in cycles 0, if we put the address in on cycle 0, we will 
          -- get the old value. So instead we wait until cycle 1.

          local relX = n._input.relX
          local relY = n._input.relY
          if type(relX)~="number" then
            relX = relX:eval(1,kernel)
            assert(relX:area()==1)
            relX = relX:min(1,kernel)
          end
          
          if type(relY)~="number" then
            relY = relY:eval(1,kernel)
            assert(relY:area()==1)
            relY = relY:min(1,kernel)
          end
          
          if c==1 then
            adddecl(darkroom.typedAST._topbb,{"assign gatherReadInX_"..pointerToVarname(n.__key).." = rwValidOutX_"..(retiming[n.x]+1)..";\n"})
            adddecl(darkroom.typedAST._topbb,{"assign gatherReadInY_"..pointerToVarname(n.__key).." = rwValidOutY_"..(retiming[n.x]+1)..";\n"})
            adddecl(darkroom.typedAST._topbb,{"assign gatherValidIn_"..pointerToVarname(n.__key).." = validOut_"..(retiming[n.x]+1)..";\n"})
                                               
            local bytesPerPixel = n._input.from.kernel.type:baseType():sizeof()
            local extraBits = math.log(bytesPerPixel)/math.log(2)
                                          
            table.insert(resDeclarations,"reg ["..(10-extraBits)..":0] gatherAddress_"..n:name()..";\n")
            table.insert(resClockedLogic,"gatherAddress_"..n:name().." <= "..inputs.x[1].."+"..valueToVerilogLL(relX,true,(10-extraBits))..";\n")
            table.insert(resDeclarations,"assign gatherAddress_"..pointerToVarname(n.__key).." = gatherAddress_"..n:name()..";\n")
          end
          local tys = n.type:baseType():sizeof()*8
          local ypos = c-(n.columnEndY-n.columnStartY+1)
          local subc = 1
          table.insert(resDeclarations,declareWire( n.type:baseType(), n:cname(c), "in_gatherColumn_"..pointerToVarname(n.__key).."_x0_y"..numToVarname(ypos).."["..(subc*tys-1)..":"..((subc-1)*tys).."]"," // gatherColumn" ))
          res = n:cname(c)
        elseif n.kind=="lifted" then
          local src = "lifted"..n.id
          local tys = n.type:baseType():sizeof()*8
          table.insert(resDeclarations,declareWire( n.type:baseType(), n:cname(c), src.."["..(c*tys-1)..":"..((c-1)*tys).."]"," // channelselect lifted" ))
          res = n:cname(c)
        else
          print(n.kind)
          assert(false)
        end

        assert(type(res)=="string")
        assert(res:match("[%w%[%]]")) -- should only be alphanumeric
        finalOut[c] = res

        adddecl(bb,resDeclarations)
        addclocked(bb,resClockedLogic)
      end

      return {finalOut}
    end)

  local outputName = finalOut[1]

  for k,v in ipairs(mdeclarations[darkroom.typedAST._topbb]) do table.insert(result,v) end
  table.insert(result,"always @ (posedge CLK) begin\n"..table.concat(mclockedLogic[darkroom.typedAST._topbb],"").."end\n")
  table.insert(result,"assign out = {"..outputName[#outputName])
  local c = #outputName-1
  while c>=1 do table.insert(result,","..outputName[c]); c=c-1 end
  table.insert(result, "};\n")

--  table.insert(result,[=[initial begin 
--$display("]=]..kernelGraphNode:name()..[=[");
--$monitor("]=]..kernelGraphNode:name()..[=[ nextX %d nextY %d x %d y %d clock %d\n",validOutNextCycleX_0,validOutNextCycleY_0,inX_0,inY_0,cycle); end
--]=])

  table.insert(result,"endmodule\n\n")
  return result
end

local function calcMaxStencil(kernelGraph)
  local maxStencil = Stencil.new()
  kernelGraph:visitEach(
    function(node)
      for k,v in node:inputs() do
        if node.kernel~=nil then print("ST",node.kernel:stencil(v,node.kernel):min(1),node.kernel:stencil(v,node.kernel):max(1),"Y",node.kernel:stencil(v,node.kernel):min(2),node.kernel:stencil(v,node.kernel):max(2)) end
      end
      if node.kernel~=nil then maxStencil = maxStencil:unionWith(neededStencil(true,kernelGraph,node,1,nil)) end
    end)
  return maxStencil
end

local function chooseStrip(options, inputs, kernelGraph, imageWidth, imageHeight, smallestScaleX, smallestScaleY)
  assert(type(imageWidth)=="number")
  assert(type(imageHeight)=="number")
  assert(type(smallestScaleX)=="number")
  assert(type(smallestScaleY)=="number")

  local maxStencil=calcMaxStencil(kernelGraph)

  print("CHOOSE STRIP",inputs[1][2])
  if inputs[1][2]=="sim" or inputs[1][2]=="axi" then
    print("SIM STRIP SIZE",maxStencil:max(2),maxStencil:min(2))
    local padMinX = downToNearest(smallestScaleX,maxStencil:min(1))
    local padMaxX = upToNearest(smallestScaleX,maxStencil:max(1))
    local padMinY = downToNearest(smallestScaleY,maxStencil:min(2))
    local padMaxY = upToNearest(smallestScaleY,maxStencil:max(2))
    return imageWidth+padMaxX-padMinX, imageHeight+padMaxY-padMinY, padMinX, padMaxX, padMinY, padMaxY
  end

  if options.stripWidth~=nil or options.stripHeight~=nil then 
    assert(type(options.stripWidth)=="number")
    assert(type(options.stripHeight)=="number")
    return options.stripWidth, options.stripHeight,0,0,0,0
  end

  local BLOCKX = 74
  local BLOCKY = 6

  for k,v in ipairs(inputs) do
    assert(v[1].kind=="crop" and v[1].expr.kind=="load")
    BLOCKX = math.floor(BLOCKX/v[1].expr.type:sizeof())
  end

  local OUTPUT_BLOCKX = 74

  assert(kernelGraph.kernel==nil)
  local i = 1
  while kernelGraph["child"..i] do
    local v = kernelGraph["child"..i].kernel
    OUTPUT_BLOCKX = math.floor(OUTPUT_BLOCKX/v.type:sizeof())
    i = i+1
  end

  if OUTPUT_BLOCKX < BLOCKX then
    BLOCKX = OUTPUT_BLOCKX
    print("Setting blockX based on outputs",BLOCKX)
  end


--  assert( (maxStencil:max(1)-maxStencil:min(1)+1) < BLOCKX )
--  assert( (maxStencil:max(2)-maxStencil:min(2)+1) < BLOCKY )
  
  if (maxStencil:max(1)-maxStencil:min(1)+1) >= BLOCKX then
    print("Expanding strip width to contain stencil.")
    print("oldwidth", BLOCKX)
    BLOCKX = maxStencil:max(1)-maxStencil:min(1)+2
    print("newwidth", BLOCKX)
  end

  if (maxStencil:max(2)-maxStencil:min(2)+1) >= BLOCKY then
    print("Expanding strip height to contain stencil.")
    print("oldheight", BLOCKY)
    BLOCKY = maxStencil:max(2)-maxStencil:min(2)+2
    print("newheight", BLOCKY)
  end

  return upToNearest(smallestScaleX,BLOCKX), upToNearest(smallestScaleY,BLOCKY),0,0,0,0
end

local function parentIsOutput(node, kernelGraph)
  assert(type(kernelGraph)=="table")
  for v,k in node:parents(kernelGraph) do if v==kernelGraph then return true end end
    return false
end

function fpga.collectLinebuffers(kernelGraph, options, pipelineRetiming, largestEffectiveCycles)
  assert(type(options)=="table")
  assert(type(pipelineRetiming)=="table")
  assert(type(largestEffectiveCycles)=="number")

  local inputLinebuffers = {}
  local outputLinebuffers = {}
  local outputUsedAsRegular = {} -- parent->input->1

  kernelGraph:visitEach(
    function(n)
      inputLinebuffers[n] = {}
      outputLinebuffers[n] = {}
      outputUsedAsRegular[n] = {}

      if n.kernel~=nil then
        n.kernel:S("load"):process(
          function(v)
            if v:parentCount(n.kernel)==0 then
              -- regular load
              inputLinebuffers[n]["regular"] = {kind="regular"}
              if darkroom.kernelGraph.isKernelGraph(v.from) then
                outputLinebuffers[v.from]["regular"] = {kind="regular"}
                outputUsedAsRegular[n][v.from]=1
              end
            else
              for vv,_ in v:parents(n.kernel) do
                if vv.kind~="gatherColumn" then
                  -- regular load
                  inputLinebuffers[n]["regular"] = {kind="regular"}
                  if darkroom.kernelGraph.isKernelGraph(v.from) then
                    outputLinebuffers[v.from]["regular"] = {kind="regular"}
                    outputUsedAsRegular[n][v.from]=1
                  end
                else
                  assert(darkroom.kernelGraph.isKernelGraph(v.from))
                  local extraPipeDelay = pipelineRetiming[n]-pipelineRetiming[v.from]-n:internalDelay(n.kernel)
                  assert(extraPipeDelay==0)
                  local s = n.kernel:stencil(v.from, n.kernel)
                  print("SMax",s:max(2),s:min(2),vv.columnEndY,vv.columnStartY)
                  assert(s:max(2)==0)
                  assert(s:min(2)==-(vv.columnEndY-vv.columnStartY))

                  local t = {kind="gatherColumn",consumers={Stencil.new():add(0,0,0):add(0,s:min(2),0)},scale=looprate(n.kernel.scaleN1,n.kernel.scaleD1,1),to=n, from=v.from,key=vv.__key}
                  t.effStripWidth = options.stripWidth/t.scale
                  assert(t.effStripWidth==math.floor(t.effStripWidth))

                  
                  --                  t.wasUpsampledY = (v.from.kernel.scaleN2/v.from.kernel.scaleD2)>(n.kernel.scaleN2/n.kernel.scaleD2)
                  -- we want to have the extra BRAM so that we can gather from it
                  t.wasUpsampledY = true 

                  t.linebufferSizeX = -s:min(1)
                  t.linebufferSizeY = -s:min(2)
                  print("t.linebufferSize",t.linebufferSizeX,t.linebufferSizeY)
                  t.declarations={}
                  t.lboutputs =""

                  for y=s:min(2),s:max(2) do
                    local wirename = v.from:name().."_to_"..n:name().."_gatherColumn_"..pointerToVarname(t.key).."_x0_y"..numToVarname(y)
                    table.insert(t.declarations,"wire ["..(v.from.kernel.type:sizeof()*8-1)..":0] "..wirename..";\n")
                    t.lboutputs = t.lboutputs..".out1_x0_y"..numToVarname(y).."("..wirename.."),"                    
                  end

                  inputLinebuffers[n][vv] = t
                  outputLinebuffers[v.from][vv] = t
               
                end
              end
            end
          end)
      end
    end)

  kernelGraph:visitEach(
    function(node)
      if outputLinebuffers[node]["regular"]~=nil then
        local res = {kind="regular"}
        res.lboutputs = ""
        
        res.consumers = {}
        res.declarations = {}
        res.linebufferSizeX = 0 -- note: this code duplicates kernelGraph:bufferSize()
        res.linebufferSizeY = 0 -- note: this code duplicates kernelGraph:bufferSize()
        res.scale = looprate(node.kernel.scaleN1,node.kernel.scaleD1,1)
        res.effStripWidth = options.stripWidth/res.scale
        print("EFFSW", res.effStripWidth, options.stripWidth,node.kernel.scaleD1)
        assert(res.effStripWidth==math.floor(res.effStripWidth))
        
        -- if the kernel is never upsampled in Y, we can make certain simpliciations
        res.wasUpsampledY = false
        
        for v,_ in node:parents(kernelGraph) do
          if v.kernel~=nil and outputUsedAsRegular[v][node] then
            local stencil = v.kernel:stencil(node,v.kernel)

            assert(stencil:max(1)<=0) -- needed for our stupid linebuffer design
            table.insert(res.consumers, stencil)
            
            -- note: this code duplicates kernelGraph:bufferSize()
            local b = -stencil:min(1)-stencil:min(2)*res.effStripWidth
            res.linebufferSizeX = math.max(res.linebufferSizeX,-stencil:min(1))
            res.linebufferSizeY = math.max(res.linebufferSizeY,-stencil:min(2))

            local extraPipeDelay = (pipelineRetiming[v]-pipelineRetiming[node]-v:internalDelay())
            
            for x=stencil:min(1),stencil:max(1) do
              for y=stencil:min(2), stencil:max(2) do
                local wirename = node:name().."_to_"..v:name().."_x"..numToVarname(x).."_y"..numToVarname(y)
                table.insert(res.declarations,"wire ["..(node.kernel.type:sizeof()*8-1)..":0] "..wirename..";\n")

                local startwire = wirename
                if extraPipeDelay>0 then
                  startwire = startwire.."_0"
                  table.insert(res.declarations,"wire ["..(node.kernel.type:sizeof()*8-1)..":0] "..wirename.."_0;\n")

                  for d=1,extraPipeDelay do
                    table.insert(res.declarations,"reg ["..(node.kernel.type:sizeof()*8-1)..":0] "..wirename.."_"..(d)..";\n")
                    table.insert(res.declarations,"always @ (posedge CLK) begin "..wirename.."_"..(d).." <= "..wirename.."_"..(d-1).."; end\n")
                  end

                  table.insert(res.declarations,"assign "..wirename.." = "..wirename.."_"..extraPipeDelay..";\n")
                end

                res.lboutputs = res.lboutputs..".out"..(#res.consumers).."_x"..numToVarname(x).."_y"..numToVarname(y).."("..startwire.."),"
              end
            end
            
            if (v.kernel.scaleN2/v.kernel.scaleD2)>(node.kernel.scaleN2/node.kernel.scaleD2) then
              res.wasUpsampledY = true
            end
          end

          res.callsites = {load={}}
          for v,_ in node:parents(kernelGraph) do
            if v.kernel~=nil and outputUsedAsRegular[v][node] then
              local loads = {}
              for x=-res.linebufferSizeX,0 do
                for y=-res.linebufferSizeY,0 do
                  loads["out_x"..numToVarname(x).."_y"..numToVarname(y)]=node:name().."_to_"..v:name().."_x"..numToVarname(x).."_y"..numToVarname(y)
                end
              end
              table.insert(res.callsites.load,{{["strideX"]=looprate(v.kernel.scaleN1, v.kernel.scaleD1, 1),["valid"]="readValid_"..v:name()},loads})
            end
          end
        end
        outputLinebuffers[node]["regular"]=res
      end
    end)

  return inputLinebuffers, outputLinebuffers, outputUsedAsRegular
end

function fpga.allocateLinebuffers(node, kernelGraph, outputLinebuffers, largestEffectiveCycles)
  assert(type(outputLinebuffers)=="table")
  assert(type(largestEffectiveCycles)=="number")

  local pipeline = {}
  local result = {}

  for k,v in pairs(outputLinebuffers) do
    if v.kind=="regular" then
      local lbmodule = fpga.modules.linebuffer(v.linebufferSizeX, v.linebufferSizeY, node.kernel.type, v.effStripWidth, v.consumers, v.scale > 1 or largestEffectiveCycles>1, v.wasUpsampledY)
      v.callsites.store={{{["in"]="kernelOut_"..node:name(),["valid"]="writeValid_"..node:name()},{}}}
      result = concat(result, lbmodule:getDefinition(v.callsites))
      pipeline = concat(pipeline,v.declarations)
      --table.insert(pipeline,lbname.." kernelBuffer_"..node:name().."(.CLK(CLK),"..v.lboutputs..".in(kernelOut_"..node:name().."),.readInNextCycleX(kernelRWValidOutNextCycleX_"..node:name().."),.readInNextCycleY(kernelRWValidOutNextCycleY_"..node:name().."),.writeInNextCycleX(kernelRWValidOutNextCycleX_"..node:name().."),.writeInNextCycleY(kernelRWValidOutNextCycleY_"..node:name().."),.readValidInNextCycle(kernelValidOutNextCycle_"..node:name().."),.writeValidInNextCycle(kernelValidOutNextCycle_"..node:name().."));\n")
      pipeline = concat(pipeline, lbmodule:getInstance("kernelBuffer_"..node:name(),v.callsites))
    else
      local bytesPerPixel = node.kernel.type:sizeof()
      local extraBits = math.log(bytesPerPixel)/math.log(2)
      local varname = "gatherAddress_"..v.from:name().."_to_"..v.to:name().."_"..pointerToVarname(v.key)
      table.insert(pipeline, "wire ["..(10-extraBits)..":0] "..varname..";\n")

      local varname_readx = "gatherReadInNextCycleX_"..v.from:name().."_to_"..v.to:name().."_"..pointerToVarname(v.key)
      table.insert(pipeline, "wire "..varname_readx..";\n")

      local varname_ready = "gatherReadInNextCycleY_"..v.from:name().."_to_"..v.to:name().."_"..pointerToVarname(v.key)
      table.insert(pipeline, "wire "..varname_ready..";\n")

      local varname_valid = "gatherValidInNextCycle_"..v.from:name().."_to_"..v.to:name().."_"..pointerToVarname(v.key)
      table.insert(pipeline, "wire "..varname_valid..";\n")

      for y=-v.linebufferSizeY,0 do
        table.insert(pipeline, "wire ["..(bytesPerPixel*8-1)..":0] "..v.from:name().."_to_"..v.to:name().."_gatherColumn_"..pointerToVarname(v.key).."_x0_y"..numToVarname(y)..";\n")
      end

      local lbname, lbmod = fpga.modules.linebuffer(v.linebufferSizeX, v.linebufferSizeY, node.kernel.type, v.effStripWidth, v.consumers, v.scale > 1, v.wasUpsampledY, true)
      result = concat(result, lbmod)
      table.insert(pipeline,lbname.." kernelBufferGatherColumn_"..node:name().."_"..pointerToVarname(v.key).."(.CLK(CLK),"..v.lboutputs..".in(kernelOut_"..node:name().."),.writeInNextCycleX(kernelRWValidOutNextCycleX_"..node:name().."),.writeInNextCycleY(kernelRWValidOutNextCycleY_"..node:name().."),.readInNextCycleX("..varname_readx.."),.readInNextCycleY("..varname_ready.."),.gatherAddress("..varname.."),.readValidInNextCycle("..varname_valid.."),.writeValidInNextCycle(kernelValidOutNextCycle_"..node:name().."));\n")
    end
  end
  return pipeline, result
end

function fpga.codegenPipeline( inputs, kernelGraph, shifts, options, largestEffectiveCycles, imageWidth, imageHeight )
  assert(darkroom.kernelGraph.isKernelGraph(kernelGraph))
  assert(type(largestEffectiveCycles)=="number")
  assert(type(imageWidth)=="number")
  assert(type(imageHeight)=="number")

  local totalInputBytes = 0
  for k,v in ipairs(inputs) do totalInputBytes = totalInputBytes + inputs[k][1].expr.type:sizeof() end

  local outputBytes = kernelGraph.child1.kernel.type:sizeof()

  local compilerState = {declaredReductionModules = {}}

  local definitions = {}
  local pipeline = {[=[module Pipeline(
input CLK, input[12:0] inX, input[12:0] inY,
output [12:0] outX, output [12:0] outY,
input validInNextCycle,
output validOut,
input [7:0] cycle,
input []=]..(totalInputBytes*8-1)..[=[:0] packedinput,
output []=]..(outputBytes*8-1)..[=[:0] out);
]=]}

  -- map the packed input bytes into a variable for each image
  local packedInputPos = 0
  for k,v in ipairs(inputs) do 
    assert(inputs[k][1].expr.kind=="load")
    local ty = inputs[k][1].expr.type
    table.insert(pipeline, declareWire(ty, "in_"..inputs[k][1].expr.from,"packedinput["..(packedInputPos+ty:sizeof()*8-1)..":"..packedInputPos.."]"," // unpack input"))
    packedInputPos = packedInputPos + ty:sizeof()*8
  end

  local kernelRetiming = {}
  kernelGraph:visitEach(
    function(node, inputArgs)
      if node.kernel~=nil then
        kernelRetiming[node] = fpga.trivialRetime(node.kernel, node.kernel)
        STUPIDGLOBALinternalDelays[node] = kernelRetiming[node][node.kernel]
        assert(type(STUPIDGLOBALinternalDelays[node])=="number")
        if parentIsOutput(node,kernelGraph)==false and node:bufferSize(kernelGraph,options.stripWidth)>0 then 
          STUPIDGLOBALinternalDelays[node] = STUPIDGLOBALinternalDelays[node]
        end
      else
        STUPIDGLOBALinternalDelays[node] = 0
      end
    end)

  -- now we retime the whole pipeline, to account for the delays of each kernel
  local pipelineRetiming = fpga.trivialRetime(kernelGraph, kernelGraph)

  local inputLinebuffers, outputLinebuffers, outputUsedAsRegular = fpga.collectLinebuffers(kernelGraph, options, pipelineRetiming, largestEffectiveCycles)

  local totalDelay = kernelGraph:visitEach(
    function(node, inputArgs)
      if node.kernel~=nil then
        local verilogKernel = fpga.codegenKernel(compilerState, node, kernelRetiming[node], imageWidth, imageHeight, kernelGraph, pipelineRetiming, shifts[node], inputLinebuffers[node], outputUsedAsRegular, options, largestEffectiveCycles)
        definitions = concat(definitions, verilogKernel)
        
        local inputs = ""
        local inputXY = ""
        if node:inputCount()==0 then
          assert(node.kernel:S("load"):count()<=1)
          node.kernel:S("load"):traverse(
            function(n)
              inputs = ".in_"..n.from.."_x0_y0(in_"..n.from.."),"
            end)
          inputXY = ".inX(inX),.inY(inY),.validIn(validIn),.cycle(cycle)"
        else
          for _,inputBuffer in pairs(inputLinebuffers[node]) do
            if inputBuffer.kind=="regular" then
              for _,v in node:inputs() do
                if outputUsedAsRegular[node][v] then
                  local s = node.kernel:stencil(v,node.kernel)
                  for x=s:min(1),s:max(1) do
                    for y=s:min(2), s:max(2) do
                      inputs = inputs..".in_"..v:name().."_x"..numToVarname(x).."_y"..numToVarname(y).."("..v:name().."_to_"..node:name().."_x"..numToVarname(x).."_y"..numToVarname(y).."),"
                    end
                  end
                end
              end
            elseif inputBuffer.kind=="gatherColumn" then
              -- actually, this is an output
              inputs = inputs..".gatherAddress_"..pointerToVarname(inputBuffer.key).."(gatherAddress_"..inputBuffer.from:name().."_to_"..inputBuffer.to:name().."_"..pointerToVarname(inputBuffer.key).."),"
              inputs = inputs..".gatherReadInNextCycleX_"..pointerToVarname(inputBuffer.key).."(gatherReadInNextCycleX_"..inputBuffer.from:name().."_to_"..inputBuffer.to:name().."_"..pointerToVarname(inputBuffer.key).."),"
              inputs = inputs..".gatherReadInNextCycleY_"..pointerToVarname(inputBuffer.key).."(gatherReadInNextCycleY_"..inputBuffer.from:name().."_to_"..inputBuffer.to:name().."_"..pointerToVarname(inputBuffer.key).."),"
              inputs = inputs..".gatherValidInNextCycle_"..pointerToVarname(inputBuffer.key).."(gatherValidInNextCycle_"..inputBuffer.from:name().."_to_"..inputBuffer.to:name().."_"..pointerToVarname(inputBuffer.key).."),"

              for y=-inputBuffer.linebufferSizeY,0 do
                inputs = inputs..".in_gatherColumn_"..pointerToVarname(inputBuffer.key).."_x0_y"..numToVarname(y).."("..inputBuffer.from:name().."_to_"..inputBuffer.to:name().."_gatherColumn_"..pointerToVarname(inputBuffer.key).."_x0_y"..numToVarname(y).."),"
              end
            else
              assert(false)
            end
          end
          local xySource = node:xySource(kernelGraph,pipelineRetiming)
          inputXY = ".inX(kernelOutX_"..xySource:name().."),.inY(kernelOutY_"..xySource:name().."),.validIn(kernelValidOut_"..xySource:name().."),.cycle(kernelCycle_"..xySource:name()..")"
        end
        
        table.insert(pipeline,"wire ["..(node.kernel.type:sizeof()*8-1)..":0] kernelOut_"..node:name()..";\n")
        table.insert(pipeline,"wire [12:0] kernelOutX_"..node:name()..";\n")
        table.insert(pipeline,"wire [7:0] kernelCycle_"..node:name()..";\n")
        table.insert(pipeline,"wire [12:0] kernelOutY_"..node:name()..";\n")
        table.insert(pipeline,"wire kernelValidOut_"..node:name()..";\n")
        table.insert(pipeline,"wire kernelRWValidOutX_"..node:name()..";\n")
        table.insert(pipeline,"wire kernelRWValidOutY_"..node:name()..";\n")
        table.insert(pipeline,"Kernel_"..node:name().." kernel_"..node:name().."(.CLK(CLK),"..inputXY..",.outX(kernelOutX_"..node:name().."),.outY(kernelOutY_"..node:name().."),"..inputs..".out(kernelOut_"..node:name().."),.rwValidOutX(kernelRWValidOutX_"..node:name().."),.rwValidOutY(kernelRWValidOutY_"..node:name().."),.cycleOut(kernelCycle_"..node:name().."),.validOut(kernelValidOut_"..node:name().."));\n")
        
        local pipelineLB, resultLB = fpga.allocateLinebuffers(node, kernelGraph, outputLinebuffers[node], largestEffectiveCycles)
        pipeline = concat(pipeline,pipelineLB)
        definitions = concat(definitions, resultLB)
        return 0
      else
        local totalDelay = 0
        for k,v in pairs(inputArgs) do
          if v > totalDelay then totalDelay=v end
        end
        return totalDelay
      end

    end)

  -- account for the linebuffering delay
  -- it turns out that the linebuffer sizes / linebuffer doesn't actually impact the pipeline delay (pipe delay meaning: if we put
  -- a pixel in the pipe, how long until its output value comes out?). The reason is that, we always write to time=0 slot
  -- in the linebuffer, and then pipe stages that consume the same value just read it (results in delay of exactly 1 due to being passed through the ram).
  -- However, due to the fact that we are retiming each module, we have to add extra buffering to each input we read to account for
  -- the differences in pipe stages of the different modules (ie if we're reading from pipe delay 10 (for A) and 20 (for B), we need to add 
  -- an extra 10 buffers on the end of A to get the correct result. The observation is that we can implement this by simply shifting where
  -- we read in the linebuffer - we don't have to actually instantiate extra buffering.
  
  assert(kernelGraph.kernel==nil)
  assert(kernelGraph:inputCount()==1)

  totalDelay = pipelineRetiming[kernelGraph.child1]

  table.insert(pipeline, "assign out = kernelOut_"..kernelGraph.child1:name()..";\n")
  table.insert(pipeline, "assign outX = kernelOutX_"..kernelGraph.child1:name()..";\n")
  table.insert(pipeline, "assign outY = kernelOutY_"..kernelGraph.child1:name()..";\n")
  table.insert(pipeline, "reg kernelValidOutThisCycle_"..kernelGraph.child1:name()..";\n")
  table.insert(pipeline, "always @ (posedge CLK) begin kernelValidOutThisCycle_"..kernelGraph.child1:name().." <= kernelRWValidOutX_"..kernelGraph.child1:name().." & kernelRWValidOutY_"..kernelGraph.child1:name().."; end\n")
  table.insert(pipeline, "assign validOut = kernelValidOutThisCycle_"..kernelGraph.child1:name()..";\n")

  table.insert(pipeline,"endmodule\n\n")
  table.insert(pipeline,"parameter PIPE_DELAY = "..(totalDelay)..";\n")

  return pipeline, definitions
end

function fpga.codegenHarness( inputs, outputs, kernelGraph, shifts, options, largestEffectiveCycles, padMinX, padMinY, padMaxX, padMaxY, imageWidth, imageHeight)
  assert(type(padMaxY)=="number")

  local maxStencil = calcMaxStencil(kernelGraph)

  local shiftX, shiftY = delayToXY(shifts[kernelGraph.child1], options.stripWidth)
  maxStencil = maxStencil:translate(shiftX,shiftY,0)

  local totalInputBytes = 0
  for k,v in ipairs(inputs) do totalInputBytes = totalInputBytes + inputs[k][1].expr.type:sizeof() end

  local outputChannels = kernelGraph.child1.kernel.type:channels()
  local outputBytes = kernelGraph.child1.kernel.type:sizeof()

  local metadata = {minX = maxStencil:min(1), maxX=maxStencil:max(1), minY=maxStencil:min(2), maxY = maxStencil:max(2), outputShift = shifts[kernelGraph.child1], outputChannels = outputChannels, outputBytes = outputBytes, stripWidth = options.stripWidth, stripHeight=options.stripHeight, uartClock=options.uartClock, downsampleX=looprate(kernelGraph.child1.kernel.scaleN1,kernelGraph.child1.kernel.scaleD1,1), downsampleY=looprate(kernelGraph.child1.kernel.scaleN2,kernelGraph.child1.kernel.scaleD2,1), padMinX=padMinX, padMaxX=padMaxX, padMinY=padMinY, padMaxY=padMaxY, cycles = largestEffectiveCycles}

  for k,v in ipairs(inputs) do
    metadata["inputFile"..k] = v[3]
    metadata["inputBytes"..k] = inputs[k][1].expr.type:sizeof()
  end

  if outputs[1][2]=="vga" then
    return fpga.modules.stageVGA(), metadata
  elseif outputs[1][2]=="uart" then
    return fpga.modules.stageUART(options, totalInputBytes, outputBytes, options.stripWidth, options.stripHeight), metadata
  elseif outputs[1][2]=="sim" then
    for k,v in ipairs(inputs) do
      if v[3]:find(".raw")==nil then darkroom.error("sim only supports raw files") end
    end

    -- sim framework assumes this is the case
    print(imageWidth,imageHeight,options.stripWidth, options.stripHeight)
    assert(imageWidth+metadata.padMaxX-metadata.padMinX==options.stripWidth)
    assert(imageHeight+metadata.padMaxY-metadata.padMinY==options.stripHeight)
    return fpga.modules.sim(totalInputBytes, outputBytes, imageWidth, imageHeight, shifts[kernelGraph.child1], metadata), metadata
  elseif outputs[1][2]=="axi" then
    -- sim framework assumes this is the case
    print(imageWidth,imageHeight,options.stripWidth, options.stripHeight)
    assert(imageWidth+metadata.padMaxX-metadata.padMinX==options.stripWidth)
    assert(imageHeight+metadata.padMaxY-metadata.padMinY==options.stripHeight)
    return fpga.modules.axi(totalInputBytes, outputBytes, imageWidth, shifts[kernelGraph.child1], metadata), metadata
  else
    print("unknown data source "..outputs[1][2])
    assert(false)
  end

end

function fpga.compile(inputs, outputs, imageWidth, imageHeight, options)
  assert(#outputs==1)
  assert(type(options)=="table" or options==nil)

  if options.clockMhz==nil then options.clockMhz=32 end
  if options.uartClock==nil then options.uartClock=57600 end

  -- do the compile
  local newnode = {kind="outputs"}
  for k,v in ipairs(outputs) do
    newnode["expr"..k] = v[1]
  end
  local ast = darkroom.ast.new(newnode):setLinenumber(0):setOffset(0):setFilename("null_outputs")

  for k,v in ipairs(outputs) do
    if v[1]:parentCount(ast)~=1 then
      darkroom.error("Using image functions as both outputs and intermediates is not currently supported. Output #"..k)
    end
  end

  local kernelGraph, _, smallestScaleX, smallestScaleY, largestEffectiveCycles = darkroom.frontEnd( ast, {} )

  local padMinX, padMaxX, padMinY, padMaxY
  options.stripWidth, options.stripHeight, padMinX, padMaxX, padMinY, padMaxY = chooseStrip(options,inputs,kernelGraph,imageWidth,imageHeight, smallestScaleX, smallestScaleY)
  options.padMinX = padMinX -- used for valid bit calculation

  local shifts = schedule(kernelGraph, 1, options.stripWidth)
  kernelGraph, shifts = shift(kernelGraph, shifts, 1, options.stripWidth)

  ------------------------------
  local result = {}
  table.insert(result, "`timescale 1ns / 10 ps\n")

  local pipeline, pipelineDefinitions = fpga.codegenPipeline( inputs, kernelGraph, shifts, options, largestEffectiveCycles, imageWidth, imageHeight )
  result = concat(result, pipelineDefinitions)
  result = concat(result, pipeline)

  local harness, metadata = fpga.codegenHarness( inputs, outputs, kernelGraph, shifts, options, largestEffectiveCycles, padMinX, padMinY, padMaxX, padMaxY, imageWidth, imageHeight )
  result = concat(result, harness)

  return table.concat(result,""), metadata
end

return fpga