local systolic={}

systolicModuleFunctions = {}
systolicModuleMT={__index=systolicModuleFunctions}

systolicInstanceFunctions = {}

local function typecheck(ast)
  assert(darkroom.ast.isAST(ast))

  if ast.kind=="readram128" then
    local t = ast:shallowcopy()
    t.type=darkroom.type.bool()
    return systolicAST.new(t):copyMetadataFrom(ast)
  elseif ast.kind=="readreg" or ast.kind=="readinput" then
    local t = ast:shallowcopy()
    t.type = t.inst.type
    return systolicAST.new(t):copyMetadataFrom(ast)
  else
    return darkroom.typedAST.typecheckAST(ast, filter(ast,function(n) return systolicAST.isSystolicAST(n) end), systolicAST.new )
  end
end

local function convert(ast)
  if getmetatable(ast)==systolicASTMT then
    return ast
  elseif type(ast)=="number" or type(ast)=="boolean" then
    local t = darkroom.ast.new({kind="value", value=ast}):setLinenumber(0):setOffset(0):setFilename("")
    return typecheck(t)
  else
    print(type(ast))
    assert(false)
  end
end

function checkReserved(k)
  if k=="input" or k=="output" or k=="reg" then
    print("Error, variable name ",k," is a reserved keyword in verilog")
    assert(false)
  end
end

local definitionCache = {}
function systolic.addDefinition(X)
  if definitionCache[X:getDefinitionKey()]==nil then
    definitionCache[X:getDefinitionKey()] = X:getDefinition()
  end
end

function systolic.getDefinitions()
  local t = ""
  for k,v in pairs(definitionCache) do
    t = t..table.concat(v)
  end

  return t
end

local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||"}

function declareReg(ty, name, initial, comment)
  assert(type(name)=="string")

  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..valueToVerilog(initial,ty)
  end

  if ty:isBool() then
    return "reg "..name..initial..";"..comment.."\n"
  else
    return "reg ["..(ty:sizeof()*8-1)..":0] "..name..initial..";"..comment.."\n"
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

function declarePort(ty,name,isInput)
  assert(type(name)=="string")

  local t = "input "
  if isInput==false then t = "output " end

  if ty:isBool()==false then
    t = t .."["..(ty:sizeof()*8-1)..":0] "
  end
  t = t..name
  
  return t
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

function systolic.module(name)
  assert(type(name)=="string")
  local t = {name=name,instances={},functions={}, instanceMap={}, usedInstanceNames = {}}
  return setmetatable(t,systolicModuleMT)
end

function systolicModuleFunctions:add(inst)
  assert(systolicInstance.isSystolicInstance(inst))
  assert( (inst.kind=="instance" and inst.pure==nil) or inst.kind=="reg" or inst.kind=="ram128")

  checkReserved(inst.name)
  if self.usedInstanceNames[inst.name]~=nil then
    print("Error, name "..inst.name.." already in use")
    assert(false)
  end

  self.instanceMap[inst] = 1
  self.usedInstanceNames[inst.name] = 1

  table.insert(self.instances,inst)
  return inst
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
  elseif ty:isBool() then
    if value then
      return "1'd1"
    else
      return "1'd0"
    end
  else
    assert(false)
  end
end

function systolicModuleFunctions:instantiate(name)
  assert(type(name)=="string")
  return systolicInstance.new({kind="module",module=self,name=name,callsites={}})
end

function systolicModuleFunctions:getInstance(instname,callsites)
  local t = {}
  table.insert(t,self.name.." "..instname.."(.CLK(CLK)")

  for fnname,v in pairs(callsites) do
    assert(type(v)=="table")
    local fn = self.functions[fnname]
    assert(fn~=nil)

    for id,vv in pairs(v) do
      assert(type(vv[1].valid)=="string")
      table.insert(t,", .C"..id.."_"..fnname.."_valid("..vv[1].valid..")")

      for _,inout in pairs(joinTables(fn.inputs,fn.outputs)) do
        assert(inout.kind=="input" or inout.kind=="output")
        local actual = vv[1][inout.varname]
        if actual==nil then actual = vv[2][inout.varname] else assert(vv[2][inout.varname]==nil) end
        if type(actual)~="string" and type(actual)~="number" then
          print("Error, missing input/output ",inout.varname," on function ",fnname)
        end
        
        table.insert(t,", .C"..id.."_"..inout.varname.."("..actual..")")
      end
    end
  end

  table.insert(t,");\n")
  return t
end


local function checkArgList( fn, args, calltable )
  assert(systolicFunction.isSystolicFunction(fn))

  calltable.type = darkroom.type.null()
  if fn.output~=nil then calltable.type=fn.output.type end

  if fn.inputs==nil or keycount(fn.inputs)==0 then
    assert(args==nil or keycount(args)==0)
    return true
  end

  assert(type(args)=="table")
  assert(systolicAST.isSystolicAST(args)==false)
  assert(type(calltable)=="table")
  local correct = keycount(args)==keycount(fn.inputs)

  map(fn.inputs, function(v,k) 
        assert(systolicInstance.isSystolicInstance(v))
        correct = correct and args[v.name]~=nil and (args[v.name].type==v.type)
        calltable["input"..k] = args[v.name]
                 end)
  
  if correct==false then
    print("Error, pure function call incorrect argument type")
    print("Expected:")
    map(fn.inputs,function(v,k) print(v.name..":"..tostring(v.type)) end)
    print("Actual:")
    map(args,function(v,k) print(k..":"..tostring(v.type)) end)
    assert(false)
  end
end

systolicFunctionFunctions = {}
systolicFunctionMT={__index=systolicFunctionFunctions, 
                    __call = function(self,args) -- args is a table of key,value pairs for the named arguments
                      assert(self.pure)
                      local t = {kind="call",func=self,pure=true,type=self.outputtype,valid="placeholder"}
                      checkArgList( self, args, t)
                      return systolicAST.new(t):setLinenumber(0):setOffset(0):setFilename("")
                    end
}

systolicFunction = {}
function systolicFunction.isSystolicFunction(t)
  return getmetatable(t)==systolicFunctionMT
end

function systolic.makeFunction(name, inputs, output, valid)
  assert(type(inputs)=="table")
  assert(#inputs==keycount(inputs))
  for k,v in ipairs(inputs) do assert(type(k)=="number");assert(systolicInstance.isSystolicInstance(v));assert(v.kind=="input") end
  assert(systolicInstance.isSystolicInstance(output) or output==nil)

  if valid==nil then
    valid = systolic.input("valid",darkroom.type.bool())
  end

  local t = {name=name, inputs=inputs, output=output, assignments={}, ram128assignments={}, asserts={}, pure=true, usedInstanceNames = {}, instanceMap = {}, valid=valid:read()}

  t.instanceMap[valid] = 1
  t.usedInstanceNames[valid.name] = 1

  if output~=nil then
    t.instanceMap[output] = 1
    t.usedInstanceNames[output.name] = 1
  end

  map(inputs, function(n) assert(t.instanceMap[n]==nil);
        assert(t.usedInstanceNames[n.name]==nil);
        t.instanceMap[n] = 1;
        t.usedInstanceNames[n.name] = 1
              end)

  return setmetatable(t,systolicFunctionMT)
end

function systolicModuleFunctions:addFunction( name, inputs, output )
  assert(type(name)=="string")

  local valid = systolic.input(name.."_valid", darkroom.type.bool())
  local fn = systolic.makeFunction( name, inputs, output, valid )

  assert(systolicFunction.isSystolicFunction(fn))
  if self.usedInstanceNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  self.functions[fn.name]=fn
  fn.pure = false
  fn.module = self
  return fn
end

function systolicFunctionFunctions:getDelay()
  local maxd = 0
  for _,v in pairs(self.assignments) do
    if v.dst.kind=="output" and v.retiming[v.expr]>maxd then 
      maxd = v.retiming[v.expr] 
    end
  end
  return maxd
end

local function retime(expr)
  local retiming = {}

  expr:visitEach(
    function(n, inputs)
      local maxDelay = 0
      for k,v in n:inputs() do
        -- only retime nodes that are actually used
        if inputs[k]>maxDelay then maxDelay = inputs[k] end
      end
      retiming[n] = maxDelay + n:internalDelay(expr)
      return retiming[n]
    end)

  return retiming
end

function systolicFunctionFunctions:addAssign( dst, expr )
  assert(systolicInstance.isSystolicInstance(dst) or (dst.kind=="output" or dst.kind=="reg"))
  expr = convert(expr)
  table.insert(self.assignments,{dst=dst,expr=expr,retiming=retime(expr)})
end

function systolicFunctionFunctions:writeRam128( ram128, addr, expr )
  assert(systolicAST.isSystolicAST(ram128))
  assert(ram128.kind=="ram128")
  assert(systolicAST.isSystolicAST(addr))
  assert(systolicAST.isSystolicAST(expr))

  table.insert(self.ram128assignments,{dst=ram128,expr=expr,addr=addr,retiming=retime(expr)})
end

local function codegen(ast, callsiteId)
  assert(systolicAST.isSystolicAST(ast))
  assert(type(callsiteId)=="number" or callsiteId==nil)

  local callsite = ""
  if type(callsiteId)=="number" then callsite = "C"..callsiteId.."_" end


  local finalOut = ast:visitEach(
    function(n, args)
      local inputs = {}
      local inputResDeclarations = {}
      local inputResClockedLogic = {}
      
      map( args, function(v,k) inputs[k]=v[1]; inputResDeclarations[k]=v[2]; inputResClockedLogic[k]=v[3]; end)

      -- 'used' are declarations from inputs that we actually end up using
      -- 'res' are declarations from this node
      local usedResDeclarations = {}
      local usedResDeclarationsSeen = {}
      local usedResClockedLogic = {}
      local usedResClockedLogicSeen = {}
      local resDeclarations = {}
      local resClockedLogic = {}

      local function addInput(key)
        for k,v in pairs(inputResDeclarations[key]) do
          if usedResDeclarationsSeen[v]==nil then
            table.insert(usedResDeclarations,v)
          end
          usedResDeclarationsSeen[v] = 1
        end

        for k,v in pairs(inputResClockedLogic[key]) do
          if usedResClockedLogicSeen[v]==nil then
            table.insert(usedResClockedLogic,v)
          end
          usedResClockedLogicSeen[v] = 1
        end
      end

      local finalOut = {}

      for c=1,n.type:channels() do
        local res

        if n.kind=="binop" then
          table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c),"", " // binop "..n.op.." result" ))
          addInput("lhs")
          addInput("rhs")

          if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
            if n.type:baseType():isBool() and n.lhs.type:baseType():isInt() and n.rhs.type:baseType():isInt() then
              table.insert(resClockedLogic, callsite..n:name().."_c"..c.." <= ($signed("..inputs.lhs[c]..")"..n.op.."$signed("..inputs.rhs[c].."));\n")
            elseif n.type:baseType():isBool() and n.lhs.type:baseType():isUint() and n.rhs.type:baseType():isUint() then
              table.insert(resClockedLogic, callsite..n:name().."_c"..c.." <= (("..inputs.lhs[c]..")"..n.op.."("..inputs.rhs[c].."));\n")
            else
              print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
              assert(false)
            end
          elseif n.type:isBool() then
            local op = binopToVerilogBoolean[n.op]
            if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
            table.insert(resClockedLogic, callsite..n:name().."_c"..c.." <= "..inputs.lhs[c]..op..inputs.rhs[c]..";\n")
          else
            local op = binopToVerilog[n.op]
            if type(op)~="string" then print("OP",n.op); assert(false) end
            local lhs = inputs.lhs[c]
            if n.lhs.type:baseType():isInt() then lhs = "$signed("..lhs..")" end
            local rhs = inputs.rhs[c]
            if n.rhs.type:baseType():isInt() then rhs = "$signed("..rhs..")" end
            table.insert(resClockedLogic, callsite..n:name().."_c"..c.." <= "..lhs..op..rhs..";\n")
          end

          res = callsite..n:name().."_c"..c
        elseif n.kind=="unary" then
          if n.op=="abs" then
            if n.type:baseType():isInt() then
              table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c) ))
              table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs\n")
              res = callsite..n:cname(c)
            else
              return inputs.expr[c] -- must be unsigned
            end
          elseif n.op=="-" then
            assert(n.type:baseType():isInt())
            table.insert(resDeclarations, declareReg(n.type:baseType(), callsite..n:cname(c)))
            table.insert(resClockedLogic, callsite..n:cname(c).." <= -"..inputs.expr[c].."; // unary sub\n")
            res = callsite..n:cname(c)
          else
            print(n.op)
            assert(false)
          end
        elseif n.kind=="select" or n.kind=="vectorSelect" then
          addInput("cond"); addInput("a"); addInput("b");
          table.insert(resDeclarations,declareReg( n.type:baseType(), callsite..n:cname(c), "", " // "..n.kind.." result" ))
          local condC = 1
          if n.kind=="vectorSelect" then condC=c end

          table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n")
          res = callsite..n:cname(c)
        elseif n.kind=="cast" then
          addInput("expr")
          local expr
          local cmt = " // cast "..tostring(n.expr.type).." to "..tostring(n.type)
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
          
          table.insert(resDeclarations, declareWire( n.type:baseType(), callsite..n:cname(c), "",cmt))
          table.insert(resDeclarations, "assign "..callsite..n:cname(c).." = "..expr..";"..cmt.."\n")
          res = callsite..n:cname(c)
        elseif n.kind=="value" then
          local v
          if type(n.value)=="table" then 
            v = valueToVerilog(n.value[c], n.type:baseType()) 
          else
            v = valueToVerilog(n.value, n.type:baseType())
          end
          table.insert(resDeclarations,declareWire( n.type:baseType(), callsite..n:cname(c), v, " //value" ))
          res = callsite..n:cname(c)
        elseif n.kind=="array" then
          addInput("expr"..c)
          res = inputs["expr"..c][1]
        elseif n.kind=="index" then
          local flatIdx = 0

          local dim = 1
          local scalefactor = 1
          while n["index"..dim] do
            assert(n["index"..dim].constLow == n["index"..dim].constHigh)
            flatIdx = flatIdx + (n["index"..dim].constLow)*scalefactor
            dim = dim + 1
          end

          addInput("expr")
          res = inputs["expr"][flatIdx+1]

--[=[          else
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
          end]=]
        elseif n.kind=="readinput" then
          res = callsite..n.inst.name
        elseif n.kind=="readreg" then
          res = n.inst.name
        elseif n.kind=="readram128" then
          table.insert(resDeclarations,"assign "..n.inst.name.."_readAddr = "..inputs.addr[1]..";\n")
          res = n.inst.name.."_readOut"
        elseif n.kind=="call" then
          if n.pure then
            systolic.addDefinition( n.func )
            
            local fndecl = {}
            table.insert(fndecl, n.func.name.." "..n:name().."(.CLK(CLK)")
            map(n.func.inputs, function(v,k) addInput("input"..k); table.insert(fndecl, ", ."..v.name.."("..inputs["input"..k][1]..")") end)
            
            if n.func.output~=nil then
              res = n:name().."_"..c
              table.insert(resDeclarations, declareWire( n.type, res,""," // pure function output"))
              table.insert(fndecl, ", ."..n.func.output.name.."("..res..")")
            else
              res = "__NILVALUE_ERROR"
            end
            table.insert(fndecl,");\n")

            resDeclarations = concat(resDeclarations, fndecl)
          else
            systolic.addDefinition( n.inst )
            
            local call_callsite = ""
            if #n.inst.callsites[n.func.name]>1 and n.func:isAccessor()==false then
              call_callsite = "C"..n.callsiteid.."_"
            end

            if n.func:isPure()==false then
              addInput("valid")
              table.insert(resDeclarations, "assign "..n.inst.name.."_"..call_callsite..n.func.name.."_valid = "..inputs.valid[1]..";\n")
            end

            map(n.func.inputs, function(v,k) 
                  addInput("input"..k)
                  table.insert(resDeclarations, "assign "..n.inst.name.."_"..call_callsite..v.name.." = "..inputs["input"..k][1]..";\n") end)

            if n.func.output~=nil then
              res = n.inst.name.."_"..call_callsite..n.func.output.name
            else
              res = "__NILVALUE_ERROR"
            end
          end
        elseif n.kind=="fndefn" then
          for id=1,n.callsites do
            table.insert(resDeclarations,"  // function: "..n.fn.name.." callsite "..id.." delay ".."".."\n")

            local assn = 1
            while n["dst"..assn] do
              local callsite = "C"..id.."_"
              if n.callsites==1 then callsite="" end
              
              addInput("expr"..assn)
              if n["dst"..assn].kind=="reg" and n.callsites>1 then table.insert( resDeclarations, declareWire(n["dst"..assn].type,callsite..n["dst"..assn].name,""," // callsite local destination")) end
              
              if (n.callsites>1) or n["dst"..assn].kind=="output" then
                table.insert(resDeclarations, "assign "..callsite..n["dst"..assn].name.." = "..inputs["expr"..assn][1]..";  // function output assignment\n")
              else
                table.insert(resClockedLogic, "if ("..inputs.valid[1]..") begin "..n["dst"..assn].name.." <= "..inputs["expr"..assn][1].."; end  // function register assignment\n")
              end
              assn = assn + 1
            end
          end

          if n.callsites>1 then
            table.insert(resDeclarations," // merge: "..n.fn.name.."\n")
            for id=1,n.callsites do
              local assn = 1
              while n["dst"..assn] do
                if id==1 then
                  if n["dst"..assn].kind=="reg" then
--                    table.insert(t, "always @ (posedge CLK) begin "..v.dst.varname.." <= C"..id.."_"..v.dst.varname.."; end\n")
                  elseif n["dst"..assn].kind=="output" then
                  else
                    print("VDK",v.dst.kind)
                    assert(false)
                  end
                end
                assn = assn + 1
              end

            end
          end

          res = "_ERR_NULL_FNDEFN"
        else
          print(n.kind)
          assert(false)
        end

        assert(type(res)=="string")
        assert(res:match("[%w%[%]]")) -- should only be alphanumeric
        finalOut[c] = res
      end

      assert(keycount(finalOut)>0)
      return {finalOut, concat(usedResDeclarations, resDeclarations), concat(usedResClockedLogic, resClockedLogic)}
    end)

  local resDeclarations = finalOut[2]
  local resClockedLogic = finalOut[3]
  finalOut = finalOut[1]

  if ast.type:isArray() then
    finalOut = "{"..table.concat(finalOut,",").."}"
  else
    finalOut = finalOut[1]
  end

  return resDeclarations, resClockedLogic, finalOut
end

-- some functions don't modify state. These do not need a valid bit
function systolicFunctionFunctions:isPure()
  return foldl( andop, true, map( self.assignments, function(n) return n.dst.kind=="output" end ) )
end

-- this is a pure function with no inputs. It only ever needs one callsite
function systolicFunctionFunctions:isAccessor()
  return self:isPure() and #self.inputs==0
end

function systolicFunctionFunctions:addAssert(expr)
  table.insert(self.asserts,expr)
end


function systolicFunctionFunctions:getDefinitionKey()
  assert(self.pure)
  return self
end

function systolicFunctionFunctions:lower(callsites)
  local node = {kind="fndefn", callsites=#callsites,fn=self,type=darkroom.type.null(),valid=self.valid}

  local cnt = 1
  local drivenOutput = false
  for k,v in pairs(self.assignments) do
    if self.output~=nil and v.dst==self.output then drivenOutput = true end
    node["dst"..cnt] = v.dst
    node["expr"..cnt] = v.expr
    cnt = cnt+1
  end
  
  if drivenOutput==false and self.output~=nil  then
    print("undriven output, function",self.name)
    if self.module~=nil then print("module",self.module.name) end
    assert(false)
  end

  return systolicAST.new(node):copyMetadataFrom(node.expr1)
end

function systolicFunctionFunctions:getDefinition(callsites)
  assert(self.pure)
  local t = {}

    table.insert(t,"module "..self.name.."(input CLK")
    map(self.inputs, function(v) table.insert(t, ", "..declarePort(v.type, v.name, true)) end)
    if systolicInstance.isSystolicInstance(self.output) then
      table.insert(t, ", "..declarePort(self.output.type, self.output.name, false))
    elseif type(self.outputs)=="table" then 
      map(self.outputs, function(v) table.insert(t, ", "..declarePort(v.type, v.varname, false)) end) 
    end
    table.insert(t,");\n")
    callsites={"LOL"}

    -- pure functions must have inputs and outputs or it doesn't make sense
    if keycount(self.inputs)==0 then
      print("Error, pure function must have inputs, function ",self.name)
      assert(false)
    end

    assert(systolicInstance.isSystolicInstance(self.output))

    t = concat( t, self:lower(callsites):toVerilog({},{self}) )
  table.insert(t,"endmodule\n\n")

  return t
end



local function binop(lhs, rhs, op)
  lhs = convert(lhs)
  rhs = convert(rhs)
  return typecheck(darkroom.ast.new({kind="binop",op=op,lhs=lhs,rhs=rhs,type=lhs.type}):copyMetadataFrom(lhs))
end

systolic._callsites = {}
systolicInstance = {}
function systolicInstance.new(tab)
  return setmetatable(tab,systolicInstanceMT)
end

function systolicInstance.isSystolicInstance(tab)
  return getmetatable(tab)==systolicInstanceMT
end

function systolicInstanceFunctions:toVerilog()
  if self.kind=="reg" then
    return declareReg(self.type, self.name, self.initial)
  elseif self.kind=="ram128" then
    return [[ wire ]]..self.name..[[_WE;
wire ]]..self.name..[[_D;
wire ]]..self.name..[[_writeOut;
wire ]]..self.name..[[_readOut;
wire [6:0] ]]..self.name..[[_writeAddr;
wire [6:0] ]]..self.name..[[_readAddr;
RAM128X1D ]]..self.name..[[  (
  .WCLK(CLK),
  .D(]]..self.name..[[_D),
  .WE(]]..self.name..[[_WE),
  .SPO(]]..self.name..[[_writeOut),
  .DPO(]]..self.name..[[_readOut),
  .A(]]..self.name..[[_writeAddr),
  .DPRA(]]..self.name..[[_readAddr));
]]
  elseif self.kind=="module" then
    local wires = {}
    local arglist = {}
    
    for fnname,fn in pairs(self.module.functions) do
      local callsitecnt = #self.callsites[fnname]
      if fn:isAccessor() then callsitecnt=1 end

      for id=1,callsitecnt do
        local callsite = "C"..id.."_"
        if #self.callsites[fnname]==1 or fn:isAccessor() then callsite="" end
        table.insert(wires,"wire "..self.name.."_"..callsite..fnname.."_valid;\n")
        if fn:isPure()==false then table.insert(arglist,", ."..callsite..fnname.."_valid("..self.name.."_"..callsite..fnname.."_valid)") end
        map(fn.inputs, function(v) table.insert(wires,declareWire( v.type, self.name.."_"..callsite..v.name )); table.insert(arglist,", ."..v.name..callsite.."("..self.name.."_"..callsite..v.name..")") end)

        if fn.output~=nil then
          table.insert(wires, declareWire( fn.output.type, self.name.."_"..callsite..fn.output.name))
          table.insert(arglist,", ."..callsite..fn.output.name.."("..self.name.."_"..callsite..fn.output.name..")")
        end
      end
    end

    return table.concat(wires)..self:getDefinitionKey().." "..self.name.."(.CLK(CLK)"..table.concat(arglist)..");\n\n"
  else
    assert(false)
  end
end

function systolicInstanceFunctions:getDefinitionKey()
  assert(self.kind=="module")
  local key = self.module.name
  for k,v in pairs(sort(stripkeys(invertTable(self.module.functions)))) do
    local callsitecnt = #self.callsites[v]
    if self.module.functions[v]:isAccessor() then callsitecnt=1 end
    key = key.."_"..v..callsitecnt
  end
  return key
end

function systolicInstanceFunctions:getDefinition()
  assert(self.kind=="module")
  local t = {}

  table.insert(t,"module "..self:getDefinitionKey().."(input CLK")
  
  for fnname,v in pairs(self.callsites) do

    for id,vv in pairs(v) do
      local fn = self.module.functions[fnname]
      assert(fn~=nil)
      
      local callsite = "C"..id.."_"
      if #self.callsites[fnname]==1 then callsite="" end

      if fn:isPure()==false then table.insert(t,", input "..callsite..fnname.."_valid") end
      
      for _,input in pairs(fn.inputs) do
        table.insert(t,", input ["..(input.type:sizeof()*8-1)..":0] "..callsite..input.name)
      end
      
      if fn.output~=nil then
        table.insert(t,", "..declarePort(fn.output.type,callsite..fn.output.name,false))
      end
    end
  end
  table.insert(t,");\n")

  table.insert(t," // state\n")
  
  for k,v in pairs(self.module.instances) do
    table.insert(t, v:toVerilog() )
  end

  for k,v in pairs(self.module.functions) do
    if type(self.callsites[v.name])=="table" then -- only codegen stuff we actually used
      t = concat(t,v:lower(self.callsites[v.name]):toVerilog({},{v,self.module}))
    end
  end

  table.insert(t,"endmodule\n\n")

  return t
end

function systolicInstanceFunctions:read(addr)
  if self.kind=="reg" then
    assert(addr==nil)
    return typecheck(darkroom.ast.new({kind="readreg",inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
  elseif self.kind=="input" then
    assert(addr==nil)
    return typecheck(darkroom.ast.new({kind="readinput",inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
  elseif self.kind=="ram128" then
    addr = convert(addr)
    return typecheck(darkroom.ast.new({kind="readram128",addr=addr,inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
  else
    assert(false)
  end
end

systolicInstanceMT={
__index = function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = systolicInstanceFunctions[key]

  if v==nil and rawget(tab,"kind")=="module" then
    -- try to find key in function tab
    local fn = rawget(tab,"module").functions[key]
    if fn~=nil then
      return function(self, args, valid)
        assert(type(args)=="table" or args==nil)
        
        tab.callsites[fn.name] = tab.callsites[fn.name] or {}
        table.insert(tab.callsites[fn.name],1)
        if valid==nil then valid="placeholder" end

        local t = {kind="call",inst=self,valid=valid,func=fn,callsiteid = #tab.callsites[fn.name]}
        
        checkArgList( fn, args, t )
        
        return systolicAST.new(t):setLinenumber(0):setOffset(0):setFilename("")
             end
    end
    
  end
  return v
end}

systolicASTFunctions = {}
setmetatable(systolicASTFunctions,{__index=IRFunctions})
systolicASTMT={__index = systolicASTFunctions,
__add=function(l,r) return binop(l,r,"+") end, 
__sub=function(l,r) return binop(l,r,"-") end}

function systolicASTFunctions:init()
  setmetatable(self,nil)
  systolicAST.new(self)
end

-- ops
function systolic.index( expr, idx )
  assert(systolicAST.isSystolicAST(expr))
  assert(type(idx)=="table")
  local t = {kind="index", expr=expr}
  map(idx, function(n,i) t["index"..i] = convert(n);  end)
  return typecheck(darkroom.ast.new(t):copyMetadataFrom(expr))
end

function systolic.cast( expr, ty )
  expr = convert(expr)
  ty = darkroom.type.fromTerraType(ty,0,0,"")

  --assert(systolicAST.isSystolicAST(expr))
  --assert(darkroom.type.isType(ty))
  return typecheck(darkroom.ast.new({kind="cast",expr=expr,type=ty}):copyMetadataFrom(expr))
end

function systolic.array( expr )
  assert(type(expr)=="table")
  assert(#expr>0)
  local t = {kind="array"}
  for k,v in ipairs(expr) do
    assert(systolicAST.isSystolicAST(v))
    t["expr"..k] = v
  end
  return typecheck(darkroom.ast.new(t):copyMetadataFrom(expr[1]))
end

function systolic.select(cond,a,b)
  cond, a, b = convert(cond), convert(a), convert(b)
  return typecheck(darkroom.ast.new({kind="select",cond=cond,a=a,b=b}):copyMetadataFrom(cond))
end

function systolic.le(lhs, rhs) return binop(lhs,rhs,"<=") end
function systolic.eq(lhs, rhs) return binop(lhs,rhs,"==") end
function systolic.lt(lhs, rhs) return binop(lhs,rhs,"<") end
function systolic.ge(lhs, rhs) return binop(lhs,rhs,">=") end
function systolic.gt(lhs, rhs) return binop(lhs,rhs,">") end
function systolic.__or(lhs, rhs) return binop(lhs,rhs,"or") end
function systolic.__and(lhs, rhs) return binop(lhs,rhs,"and") end

function systolicASTFunctions:cname(c)
  return self:name().."_c"..c
end


function systolicASTFunctions:internalDelay()
  if self.kind=="binop" or self.kind=="select" or self.kind=="readram128" then
    return 1
  elseif self.kind=="readinput" or self.kind=="reg" or self.kind=="value" or self.kind=="index" or self.kind=="cast" or self.kind=="array" or self.kind=="readreg" then
    return 0
  else
    print(self.kind)
    assert(false)
  end
end

function checkForInst(inst, scopes)
  assert(systolicInstance.isSystolicInstance(inst))

  local fnd = false
  for k,scope in ipairs(scopes) do
    fnd = fnd or scope.instanceMap[inst]~=nil
  end
  
  if fnd==false then
    print("missing instance "..inst.name.." (kind "..inst.kind..")")
    map(scopes, function(n) print("scope",n.name) end)
    assert(false)
  end
end

-- check that all of the variables refered to are actually in scope
-- scopes goes from innermost (index 1) to outermost (index n)
function systolicASTFunctions:checkVariables(scopes)
  assert(type(scopes)=="table")

  local function astcheck(n)
    if n.kind=="readinput" or n.kind=="readreg" or n.kind=="readram128" or (n.kind=="call" and n.pure~=true) then
      checkForInst(n.inst, scopes)
    end

    if n.kind=="fndefn" then
      local i=1
      while n["dst"..i] do
        checkForInst(n["dst"..i], scopes)
        i = i + 1
      end
    end

    if n.kind=="call" and n.pure~=true then
      assert(systolicAST.isSystolicAST(n.valid))
    end
  end

  self:visitEach(astcheck)
end

function systolicASTFunctions:toVerilog( options, scopes )
  assert(type(scopes)=="table")

  local function addValidBit(ast,valid)
    valid = convert(valid)
    return ast:S("call"):process(
      function(n)
        if n.pure~=true and systolicAST.isSystolicAST(n.valid)==false then
          local nn = n:shallowcopy()
          nn.valid = valid
          assert(systolicAST.isSystolicAST(valid))
          return systolicAST.new(nn):copyMetadataFrom(n)
        end
      end)
  end

  local ast = self
  if options.valid~=nil then
    -- obviously, if there are any function calls in the condition, we want them to always run
    local valid = addValidBit(convert(options.valid),true)
    ast = addValidBit(ast,valid)

    print("ADDVALID")
  else
    print("SKIPVALID")
  end

  ast:checkVariables( scopes )
  ast = darkroom.optimize.optimize( ast, {})

  local decl, clocked, finalOut = codegen(ast)

  local t = decl
  if #clocked>0 then
    table.insert(t,"always @ (posedge CLK) begin\n")
    t = concat(t,clocked)
    table.insert(t,"end\n")
  end
  
  return t, finalOut
end

systolicAST = {}
function systolicAST.isSystolicAST(ast)
  return getmetatable(ast)==systolicASTMT
end

function systolicAST.new(tab)
  assert(type(tab)=="table")
  if tab.scaleN1==nil then tab.scaleN1=0 end
  if tab.scaleD1==nil then tab.scaleD1=0 end
  if tab.scaleN2==nil then tab.scaleN2=0 end
  if tab.scaleD2==nil then tab.scaleD2=0 end
  assert(darkroom.type.isType(tab.type))
  darkroom.IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end

function systolic.reg( name, ty, initial )
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="reg",name=name,initial=initial,type=ty})
end

function systolic.ram128( name )
  assert(type(name)=="string")
  checkReserved(name)
  return systolicInstance.new({kind="ram128",name=name,type=darkroom.type.null()})
end

function systolic.output(name, ty)
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="output",name=name,type=ty})
end

function systolic.input(name, ty)
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="input",name=name,type=ty})
end

return systolic