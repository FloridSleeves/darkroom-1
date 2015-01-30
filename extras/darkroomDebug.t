

function astFunctions:expectedKeycount()
  local baseSize = 1 -- kind

  if self.kind=="func" then
    return baseSize+self:arraySize("identifier")+self:arraySize("arg")
  elseif self.kind=="binop" then
    return baseSize+3
  elseif self.kind=="unary" then
    return baseSize+2
  elseif self.kind=="transform" then
    return baseSize+1+self:arraySize("arg")
  elseif self.kind=="apply" then
    return baseSize+1+self:arraySize("arg")
  elseif self.kind=="value" then
    return baseSize+1
  elseif self.kind=="select" or self.kind=="vectorSelect" then
    return baseSize+3
  elseif self.kind=="cast" then
    return baseSize+2
  elseif self.kind=="array" then
    local exprsize = self:arraySize("expr")
    return baseSize+exprsize
  elseif self.kind=="assert" then
    return baseSize+3
  elseif self.kind=="type" then
    return baseSize+1
  elseif self.kind=="special" then
    return baseSize+1
  elseif self.kind=="position" then
    return baseSize+1
  elseif self.kind=="mapreduce" then
    return baseSize+self:arraySize("varname")*4+2 -- name, high, low, id
  elseif self.kind=="mapreducevar" then
    return baseSize+4 -- name, high, low, id
  elseif self.kind=="letvar" then
    return baseSize+1 -- kind,variable
  elseif self.kind=="tap" then
    return 4
  elseif self.kind=="tapLUT" then
    return 5 -- kind, type, count, id, tapname
  elseif self.kind=="tapLUTLookup" then
    return 6 -- kind, type, count, id, index, tapname
  elseif self.kind=="lua" then
    return baseSize+1
  elseif self.kind=="reduce" then
    return baseSize+1+self:arraySize("expr")
  elseif self.kind=="crop" then
    -- shiftY means that instead of cropping outside of y=[0,height) we crop outside y=[shiftY, height+shiftY)
    assert(type(self.shiftY)=="number")
  elseif self.kind=="let" then
    local cnt = self:arraySize("expr")
    return baseSize+cnt*2+1
  elseif self.kind=="index" then
    return baseSize+2
  elseif self.kind=="multiout" then
    return 1+self:arraySize("expr")
  elseif self.kind=="switch" then
    return 1+self:arraySize("expr")+self:arraySize("val")+2 -- controlExpr, default
  elseif self.kind=="gather" then
    return 9 -- kind, input,x,y,maxX,maxY,clamp,hackBL, hackTR
  else
    print(self.kind)
    assert(false)
  end

end

function astFunctions:checkfn()
  assert(type(self.kind)=="string")
  
  if self.kind=="func" then

    local i = 1
    while self["identifier"..i] do
      local v = self["identifier"..i]
      -- the identifier can potentially contain expressions we haven't parsed yet
      assert(type(v)=="string" or type(v)=="number" or (type(v)=="table" and darkroom.ast.isAST(v)))
      i = i + 1
    end

    local j = 1
    while self["arg"..j] do
      assert(getmetatable(self["arg"..j])==getmetatable(self))
      j=j+1
    end

  elseif self.kind=="binop" then
    assert(getmetatable(self.lhs)==getmetatable(self))
    assert(getmetatable(self.rhs)==getmetatable(self))
    assert(type(self.op)=="string")
  elseif self.kind=="unary" then
    assert(type(self.op)=="string")
    assert(getmetatable(self.expr)==getmetatable(self))
  elseif self.kind=="transform" then
    assert(getmetatable(self.expr)==getmetatable(self))

    local i=1
    while self["arg"..i] do
      local v = self["arg"..i]
      assert(getmetatable(v)==getmetatable(self))
      i=i+1
    end
  elseif self.kind=="apply" then
    assert(getmetatable(self.expr)==getmetatable(self))

    local i=1
    while self["arg"..i] do
      local v = self["arg"..i]
      assert(getmetatable(v)==getmetatable(self))
      i=i+1
    end

  elseif self.kind=="value" then
    assert(type(self.value)=="number" or type(self.value)=="boolean" or type(self.value)=="table")

    if type(self.value)=="table" then
      for k,v in pairs(self.value) do
        assert(type(k)=="number")
        assert(type(v)=="number" or type(v)=="boolean")
      end
    end

    if self.type~=nil then
      if darkroom.type.isNumber(self.type) then assert(type(self.value)=="number") end
      if darkroom.type.isBool(self.type) then assert(type(self.value)=="boolean") end
      if darkroom.type.isArray(self.type) then assert(type(self.value)=="table") end
    end

  elseif self.kind=="select" or self.kind=="vectorSelect" then
    assert(getmetatable(self.cond)==getmetatable(self))
    assert(getmetatable(self.a)==getmetatable(self))
    assert(getmetatable(self.b)==getmetatable(self))
  elseif self.kind=="cast" then
    assert(getmetatable(self.type)==getmetatable(self))
    assert(self.type.kind=="type")
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(self:childrenCount()==2)
  elseif self.kind=="array" then
    local exprsize = self:arraySize("expr")
    self:map("expr", function(n) 
               assert(getmetatable(n)==getmetatable(self))
                     end)

  elseif self.kind=="asserttype" then
    -- asserts that _expr has type _type
    -- _type is either a type (it will do an exact match),
    -- or "float", "int", "uint", "bool", "number" which will match multiple types
    -- a noop (unless the assert fails). returns _expr
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(darkroom.type.isType(self.type))

  elseif self.kind=="assert" then
    -- asserts that cond is true at runtime. cond must yield a bool
    -- a noop (unless the assert fails). returns expr
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(getmetatable(self.printval)==getmetatable(self))
    assert(getmetatable(self.cond)==getmetatable(self))
  elseif self.kind=="call" then
    assert(type(_args)=="table")
    assert(terralib.isfunction(_tfunc))
    assert(darkroom.type.isType(_type))
  elseif self.kind=="type" then
    -- returns the type of _expr
    assert(darkroom.type.isType(self.type))

  elseif self.kind=="special" then
    assert(self:childrenCount()==0)
    assert(type(self.id)=="number")
  elseif self.kind=="position" then
    assert(type(self.coord)=="string")
    assert(self.coord=="x" or self.coord=="y" or self.coord=="z")
  elseif self.kind=="mapreduce" then

    local i=1
    while self["varname"..i]~=nil do
      assert(type(self["varname"..i])=="string")
      assert(darkroom.ast.isAST(self["varlow"..i]))
      assert(darkroom.ast.isAST(self["varhigh"..i]))
      i=i+1
    end

    assert(type(self.reduceop)=="string")
    assert(getmetatable(self.expr)==getmetatable(self))
  elseif self.kind=="mapreducevar" then
    assert(type(self.variable)=="string")
    assert(darkroom.ast.isAST(self.low))
    assert(darkroom.ast.isAST(self.high))
  elseif self.kind=="letvar" then
    assert(type(self.variable)=="string")
  elseif self.kind=="tap" then
    assert(type(self.id)=="number")
    assert(darkroom.type.isType(self.type))
  elseif self.kind=="tapLUT" then
    assert(type(self.id)=="number")
    assert(type(self.count)=="number")
    assert(darkroom.type.isType(self.type))
  elseif self.kind=="tapLUTLookup" then
    assert(type(self.id)=="number")
    assert(type(self.count)=="number")
    assert(darkroom.type.isType(self.type))
  elseif self.kind=="lua" then
    assert(type(self.expr)=="function")
  elseif self.kind=="reduce" then
    assert(self.op=="sum" or self.op=="min" or self.op=="max")
    
    assert(self.expr2~=nil) -- better at least have 2 things we're reducing

    local i = 1
    while self["expr"..i] do
      assert(getmetatable(self["expr"..i])==getmetatable(self))
      i=i+1
    end
  elseif self.kind=="crop" then
    assert(type(self.shiftY)=="number")
    assert(getmetatable(self.expr)==getmetatable(self))
  elseif self.kind=="let" then
    local cnt = self:arraySize("expr")
    self:map("expr", function(n)    assert(getmetatable(n)==getmetatable(self))  end)
    self:map("exprname", function(n) assert(type(n)=="string") end)
    assert(getmetatable(self.res)==getmetatable(self))

  elseif self.kind=="index" then
    assert(getmetatable(self.expr)==getmetatable(self))
    -- orion arrays are 0 indexed
    assert(getmetatable(self.index)==getmetatable(self))
  elseif self.kind=="multiout" then
    self:map("expr",function(n) 
               if getmetatable(n)~=getmetatable(self) then
                 print("RR")
                 n:printpretty()
               end
               assert(getmetatable(n)==getmetatable(self)) end)
  elseif self.kind=="switch" then
    assert(getmetatable(self)==getmetatable(self.controlExpr))
    assert(getmetatable(self)==getmetatable(self.default))

    self:map("expr",function(n,idx) 
               assert(getmetatable(n)==getmetatable(self))
               assert(getmetatable(self["val"..idx])==getmetatable(self)) end)
  elseif self.kind=="gather" then
    assert(getmetatable(self)==getmetatable(self.input))
    assert(getmetatable(self)==getmetatable(self.x))
    assert(getmetatable(self)==getmetatable(self.y))
    assert(getmetatable(self)==getmetatable(self.hackBL))
    assert(getmetatable(self)==getmetatable(self.hackTR))
    assert(type(self.maxX)=="number")
    assert(type(self.maxY)=="number")
    assert(type(self.clamp)=="boolean")
  else
    print(self.kind)
    assert(false)
  end

end

function darkroom.ast.check(node,options)
  return astFunctions.check(node,options)
end

function astPrintPrettys(root)
  if type(root)=="number" then return tostring(root) end

  local assignments = {}

  local res = root:visitEach(
    function( self, inputs)

      local out

  if self.kind=="func" then
    local i=1
    out=""
    while self["identifier"..i] do
      out = out..self["identifier"..i]
      if self["identifier"..(i+1)] then out=out.."." end
      i=i+1
    end

    if self.arg1~=nil then
      out = out.."("
      local i=1
      while self["arg"..i] do
        out = out..inputs["arg"..i]
        if self["arg"..(i+1)] then out=out.."," end
        i=i+1
      end
      out = out..")"
    end

  elseif self.kind=="binop" then
    out="("..inputs.lhs..")"..self.op.."("..inputs.rhs..")"
  elseif self.kind=="unary" then
    out=self.op.."("..inputs.expr..")"
  elseif self.kind=="value" then
    out=tostring(self.value)
  elseif self.kind=="load" then
    out="_load_"..self.from.."("..inputs.relX..","..inputs.relY..")"
  elseif self.kind=="iterate" then
    out="iterate "..self.iteratorName.."="..inputs.iterationSpaceLow..","..inputs.iterationSpaceHigh.." reduce("..self.reduceop..") "..inputs.expr.." end"
  elseif self.kind=="mapreduce" then
    local vars,i = "",1
    while self["varname"..i] do
      local varnode = self["varnode"..i]
      vars = vars.."_mr_"..self["varname"..i].."="..astPrintPrettys(varnode.low)..","..astPrintPrettys(varnode.high).." "
      i=i+1
    end
    out="map "..vars.." reduce("..self.reduceop..") "..inputs.expr.." end"
  elseif self.kind=="mapreducevar" then
    out="_mr_"..self.varname
  elseif self.kind=="iterationvar" then
    out="_itervar_"..self.varname
  elseif self.kind=="iterateload" then
    out="_iterload_"..self.varname
  elseif self.kind=="letvar" then
    out="_letvar_"..self.variable
  elseif self.kind=="reduce" then
    out = "reduce()"
  elseif self.kind=="position" then
    out="_pos"..self.coord
  elseif self.kind=="tap" then
    out="_tap_"..self.id
  elseif self.kind=="tapLUT" then
    out="_tapLUT_"..self.id
  elseif self.kind=="tapLUTLookup" then
    out="_tapLUT_"..self.id.."["..inputs.index.."]"
  elseif self.kind=="transform" then
    out= inputs.expr
    if self.arg1~=nil then
      out = out.."("
      local i=1
      while self["arg"..i] do
        out = out..inputs["arg"..i]..","
        i=i+1
      end
      out = out..")"
    end

  elseif self.kind=="select" or self.kind=="vectorSelect" then
    out="if "..inputs.cond.." then "..inputs.a.." else "..inputs.b.." end"
  elseif self.kind=="lua" then
    out = "luaexpr"
  elseif self.kind=="crop" then
    out = "crop("..inputs.expr..", shiftY=" .. self.shiftY .. ")"
  elseif self.kind=="cast" then
    out = "cast("..inputs.expr..","..self.type:str()..")"
  elseif self.kind=="type" then
    out = self.type:str()
  elseif self.kind=="let" then
    out = "let \n"
    
    local cnt = 1
    while self["expr"..cnt] do
      out = out .. self["exprname"..cnt] .. " = " .. inputs["expr"..cnt] .. "\n"
      cnt = cnt + 1
    end

    out = out .. "in " .. inputs.res
  elseif self.kind=="array" then
    out = "{"
    local cnt = 1
    while self["expr"..cnt] do
      out = out .. inputs["expr"..cnt] .. ","
      cnt = cnt + 1
    end
    out = out .. "}"
  elseif self.kind=="assert" then
    out = "assert("..inputs.expr..","..inputs.printval..","..inputs.cond..")"
  elseif self.kind=="outputs" then
    out = "outputs("

    local cnt = 1
    while self["expr"..cnt] do
      out = out .. inputs["expr"..cnt] .. ","
      cnt = cnt + 1
    end

    out = out .. ")"
  elseif self.kind=="switch" then
    out = "switch "..inputs.controlExpr.."\n"
    self:map("expr",function(n,idx)
               out = out .. inputs["val"..idx] .. " => ".. inputs["expr"..idx].."\n"
                    end)
    out = out.."default => "..inputs.default.."\n"
    out = out.."end"
  elseif self.kind=="gather" then
    out = "gather(\n"..inputs._input..",\n"
    out = out..inputs.x..",\n"
    out = out..inputs.y..",\n"
    out = out.."maxX = "..tostring(self.maxX)..",minX = "..tostring(self.minX)..", maxY = "..tostring(self.maxY)..", minY = "..tostring(self.minY)..", clamp = "..tostring(self.clamp)..")"
  elseif self.kind=="gatherColumn" then
    out = "gatherColumn("..inputs._input..","..inputs.x..")"
  elseif self.kind=="index" then
    out = inputs.expr.."["..inputs.index.."]"
  elseif self.kind=="var" then
--    out = self.name
    out = "VAR"..self.name
  elseif self.kind=="filter" then
    out = "filter( "..inputs.cond..", "..inputs.expr.." )"
  else
    print(self.kind)
    assert(false)
  end

  local displayInVar = (self:parentCount(root)>1)

  if displayInVar then
    assignments[self:name()] = out
    return self:name()
  end

  return out
    end)

  local fres = ""
  for k,v in pairs(assignments) do fres = fres..k.." = "..v.."\n" end
  return fres..res
end

function typedASTFunctions:expectedKeycount()
  local baseSize = 2

  if self.kind=="mapreduce" or 
    self.kind=="mapreducevar" or 
    self.kind=="transform" or
    self.kind=="crop" then
    assert(false) -- should have been eliminated
  elseif self.kind=="transformBaked" then
    return baseSize+1+self:arraySize("translate")*2
  elseif self.kind=="cropBaked" then
    return baseSize+2
  elseif self.kind=="cast" then
    return baseSize+1
  elseif self.kind=="toAOS" then
    local cnt = self:arraySize("expr")
    return baseSize+cnt
  elseif self.kind=="multibinop" then
    local lhscnt = self:arraySize("lhs")
    local rhscnt = self:arraySize("rhs")
    return baseSize+1+lhscnt+rhscnt
  elseif self.kind=="multiunary" then
    local exprcnt = self:arraySize("expr")
    return baseSize+1+exprcnt
  elseif self.kind=="toSOA" then
    return 4 -- kind, special, index, type
  elseif self.kind=="tap" then
    return 4
  elseif self.kind=="tapLUTLookup" then
    return 6 -- kind, type, index, count, id, tapname
  end

  return astFunctions.expectedKeycount(self)+1 -- type
end

function typedASTFunctions:checkfn()

  assert(darkroom.type.isType(self.type))

  if self.kind=="mapreduce" or 
    self.kind=="mapreducevar" or 
    self.kind=="transform" or
    self.kind=="crop" then
    assert(false) -- should have been eliminated
  elseif self.kind=="transformBaked" then
    
    local i=1
    while self["translate"..i] or i<3 do -- we at least need coords for x,y
      assert(type(self["translate"..i])=="number")
      assert(type(self["scale"..i])=="number")
      i=i+1
    end

    assert(getmetatable(self.expr)==getmetatable(self))
  elseif self.kind=="toSOA" then
    assert(type(self.special)=="number")
    assert(type(self.index)=="number")
  elseif self.kind=="cropBaked" then
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(darkroom.cropIR.isCropIR(self.crop))
    self.crop:check()
  elseif self.kind=="cast" then
    assert(darkroom.type.isType(self.type))
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(self:childrenCount()==1)
  elseif self.kind=="index" then
    assert(getmetatable(self.expr)==getmetatable(self))
    assert(type(self.index)=="number")
  elseif self.kind=="toAOS" then
    -- converts N inputs to array of structs form
    local cnt = self:arraySize("expr")
    self:map("expr",function(n) assert(getmetatable(n)==getmetatable(self)) end)
  elseif self.kind=="multibinop" then
    -- a binop that takes multiple inputs for the lhs, rhs
    -- ex: dot product. These are vector operations that mix channels
    -- that have been devectorized

    local lhscnt = self:arraySize("lhs")
    local rhscnt = self:arraySize("rhs")
    self:map("lhs",function(n) assert(getmetatable(n)==getmetatable(self)) end)
    self:map("rhs",function(n) assert(getmetatable(n)==getmetatable(self)) end)
    assert(type(self.op)=="string")
  elseif self.kind=="multiunary" then
    -- a unary that takes multiple inputs for the expr
    -- ex: arrayAnd. These are vector operations that mix channels
    -- that have been devectorized

    local exprcnt = self:arraySize("expr")
    self:map("expr",function(n) assert(getmetatable(n)==getmetatable(self)) end)
    assert(type(self.op)=="string")
  else
    astFunctions.checkfn(self)
  end

end

function darkroom.typedAST.check(node,options)
  return typedASTFunctions.check(node,options)
end

-- assignments is used to store variables we've assigned to
-- assignments: varname -> string
function typedASTPrintPrettys(root)
  if type(root)=="number" then return tostring(root) end

  local assignments = {}
  local res = root:visitEach(
    function( self, inputs )

  local out = "["..darkroom.type.typeToString(self.type).."]"

  if self.kind=="func" then
    local i=1
    while self["identifier"..i] do
      out = out..self["identifier"..i]
      if self["identifier"..(i+1)] then out=out.."." end
      i=i+1
    end

  elseif self.kind=="binop" then
    out = out.."("..inputs.lhs..")"
    out = out..self.op.."("..inputs.rhs..")"
  elseif self.kind=="multibinop" then
    out = out.."("
    self:map("lhs",
             function(n,i) 
               out = out..n:printprettys(root,self,"lhs"..i,assignments)..","
             end)
    out = out..")"

    out = out..self.op.."("
    self:map("rhs",
             function(n,i) 
               out = out..n:printprettys(root,self,"rhs"..i,assignments)..","
             end)
    out = out..")"
  elseif self.kind=="multiunary" then
    out = out..self.op.."("
    self:map("expr",
             function(n,i) 
               out = out..n:printprettys(root,self,"expr"..i,assignments)..","
             end)
    out = out..")"

  elseif self.kind=="unary" then
    out=out..self.op.."("..inputs.expr..")"
  elseif self.kind=="value" then
    out=out..tostring(self.value)
  elseif self.kind=="input" then
    out=out.."_input_"..self.id
  elseif self.kind=="position" then
    out=out..self.coord
  elseif self.kind=="cast" then
    out = out..inputs.expr
  elseif self.kind=="tap" then
    out=out.."_tap_"..self.id
  elseif self.kind=="tapLUTLookup" then
    out=out.."_tapLUT_"..self.id.."["..inputs.index.."]"
  elseif self.kind=="transformBaked" then
    out = out..inputs.expr.."("

    local i=1
    while self["translate"..i] do
      -- translate is either a number or an AST
      out = out..darkroom.dimToCoord[i].."*("..(self["scaleD"..i]*self.expr["scaleN"..i]).."/"..(self["scaleN"..i]*self.expr["scaleD"..i])..")+"..inputs["translate"..i]
      if self["translate"..(i+1)] then out = out.."," end
      i=i+1
    end
    out = out..")"

  elseif self.kind=="reduce" then
    out = out .. self.op .. "("

    local i=1
    while self["expr"..i] do
      out = out..inputs["expr"..i]
      if self["expr"..(i+1)] then out = out..",\n" end
      i=i+1
    end
    
    out = out  .. ")"
  elseif self.kind=="select" then
    out=out.."if "..inputs.cond.." then "..inputs.a.." else "..inputs.b.." end"
  elseif self.kind=="vectorSelect" then
    out=out.."vectorSelect("..inputs.cond..","..inputs.a..","..inputs.b..")"
  elseif self.kind=="crop" then
    out = out.."crop("..inputs.expr..", shiftY=" .. self.shiftY .. ")"
  elseif self.kind=="array" or
    self.kind=="toAOS" then

    out = out..self.kind.."("

    self:map("expr", 
             function(n,index)
               
               out = out .. inputs["expr"..index]..", "
             end)

    out = out..")"
  elseif self.kind=="assert" then
    out = out.."assert("..self.expr:printprettys(root,self,"expr",assignments)..","..self.printval:printprettys(root,self,"printval",assignments)
    out = out..","..self.cond:printprettys(root,self,"cond",assignments)..")"
  elseif self.kind=="outputs" then
    out = out.."outputs("

    self:map("expr", 
             function(n,index)
               out = out..inputs["expr"..index]..", "
             end)

    out = out..")"
  elseif self.kind=="index" then
    out = out.."("..inputs.expr..")["..inputs.index.."]"
  elseif self.kind=="gather" then
    out = "gather(\ninput = "..inputs._input..",\n"
    out = out.."x = "..inputs.x..",\n"
    out = out.."y = "..inputs.y..",\n"
    out = out.."maxX = "..tostring(self.maxX)..",minX = "..tostring(self.minX)..", maxY = "..tostring(self.maxY)..", minY = "..tostring(self.minY)..", clamp = "..tostring(self.clamp)..")"
  elseif self.kind=="load" then
    local n = self.from
    if type(self.from)=="table" then n=self.from:name() end
    out = "load_from_"..n.."("..inputs.relX..","..inputs.relY..")"
  elseif self.kind=="mapreduce" then
    local vars,i = "",1
    while self["varname"..i] do
      vars = vars.."_mr_"..self["varname"..i].."="..typedASTPrintPrettys(self["varnode"..i].low)..","..typedASTPrintPrettys(self["varnode"..i].high).." "
      i=i+1
    end

    for k,v in pairs(self) do 
      if k:sub(1,6)=="lifted" then
        vars = vars..k.." = "..inputs[k].." "
      end
    end

    out = "map "..vars.." reduce("..self.reduceop..") "..inputs.expr.." end"
  elseif self.kind=="mapreducevar" then
    out = "_mr_"..self.varname
  elseif self.kind=="iterationvar" then
    out = "_itervar_"..self.varname
  elseif self.kind=="gatherColumn" then
    out = "gatherColumn("..inputs._input..","..inputs.x..")"
  elseif self.kind=="iterateload" then
    out="_iterload_"..self.varname
  elseif self.kind=="iterate" then
    out="iterate "..self.iteratorName.."="..self.iterationSpaceLow..","..self.iterationSpaceHigh.." reduce("..self.reduceop..") "..inputs.expr.." end"
  elseif self.kind=="filter" then
    out = "filter( "..inputs.cond..", "..inputs.expr.." )"
  elseif self.kind=="lifted" then
    out = "lifted"..self.id
  else
    print(self.kind)  
    assert(false)
  end

  -- decide if we should display this stored in a variable
  local displayInVar = false
  if true then
    -- CSE mode, only store stuff that has multiple parents
    displayInVar = (self:parentCount(root)>1)
  else

  end

  if displayInVar then
    assignments[self:name()] = out
    return self:name()
  end

  return out
  end)

  local fres = ""
  for k,v in pairs(assignments) do fres = fres..k.." = "..v.."\n" end
  return fres..res
end

function typedASTPrintPretty(root)
  print(typedASTPrintPrettys(root))
end


function IRFunctions:check()
  if darkroom.debug==false then return end
--  return
  --print(debug.traceback())

  --local q = self:S("*")
  --print("check",q:count())

  self:visitEach(
    function(node)
      darkroom.IR.check(node)

      if node:keyCount()~=node:expectedKeycount() then
        print("keycount mismatch","kind:",node.kind,"has:",node:keyCount(),"expected:",node:expectedKeycount())
        for k,v in pairs(node) do print(k) end
        
        assert(false)
      end

      node:checkfn()
    end)


end

function kernelGraphPrintPretty(root)
  print("KGPP")
  assert(darkroom.kernelGraph.isKernelGraph(root))
  root:visitEach(function(node)
                   print(node:name().." -------------")
                   if node.kernel==nil then
                     print("(OUTPUT NODE)")
                     node:map("child",function(n) print(n:name()) end)
                   else
                     print("scale: ",node.kernel.scaleN1.."/"..node.kernel.scaleD1, node.kernel.scaleN2.."/"..node.kernel.scaleD2)
                     typedASTPrintPretty(node.kernel)
                   end
                 end)
end

-- install debug hooks
local origCompile = darkroom.compile
function darkroom.compile(inputImageFunctions, outputImageFunctions, tapInputs, inputWidth, inputHeight, options)
  if options==nil then options={} end
  print("debug darkroom.compile")
  options.callbackAST = function(node) print(astPrintPrettys(node)) end
  options.callbackTypedAST = function(node) typedASTPrintPretty(node) end
  local ocallbackKernelGraph = options.callbackKernelGraph
  options.callbackKernelGraph = function(node) kernelGraphPrintPretty(node); if ocallbackKernelGraph~=nil then ocallbackKernelGraph(node) end end
  options.callbackScheduledKernelGraph = function(node) kernelGraphPrintPretty(node) end
  options.debug = true
  local res =  origCompile(inputImageFunctions, outputImageFunctions, tapInputs, inputWidth, inputHeight, options)

  -- reset the stuff we changed in options
  options.callbackKernelGraph = ocallbackKernelGraph

  return res
end