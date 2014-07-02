typedASTFunctions={}
setmetatable(typedASTFunctions,{__index=IRFunctions})
typedASTMT={__index=typedASTFunctions,
  __newindex = function(table, key, value)
                    orion.error("Attempt to modify typed AST node")
                  end}

orion.typedAST = {}



function orion.typedAST.checkOffsetExpr(expr, coord)
  assert(type(coord)=="string")

  -- no x+x allowed
  if expr:S("position"):count() ~= 1 then
return false
  end

  expr:S("*"):traverse( 
    function(n)
      if expr.kind=="binop" then
        if expr.op~="+" and expr.op~="-" then
          orion.error("binop '"..expr.op.."' is not supported in an offset expr")
        end
      elseif expr.kind=="value" then
        if type(expr.value)~="number" then
          orion.error("type "..type(expr.value).." is not supported in offset expr")
        end
      elseif expr.kind=="position" then
        if expr.coord~=coord then
          orion.error("you can't use coord "..expr.coord.." in expression for coord "..coord)
        end
      elseif expr.kind=="cast" then
      elseif expr.kind=="mapreducevar" then
      else
        orion.error(expr.kind.." is not supported in offset expr")    
      end
    end)

  return true
end

-- take the ast input that's an offset expr for coord 'coord'
-- and convert it into a translate,scale. returns nil if there was an error.
function orion.typedAST.synthOffset(ast,coord)
  -- note that we don't typecheck these expressions! we keep them as ASTs,
  -- because they aren't really part of the language
  assert(orion.ast.isAST(ast))

  -- first check that there isn't anything in the expression that's definitely not allowed...
  if orion.typedAST.checkOffsetExpr(ast,coord)==false then
return nil
  end

  -- now distribute the multiplies until they can't be distributed any more. ((x+i)+j) * 2 => (x*2 + i*2)+j*2
  
  -- now, the path up the tree from the position to the root should only have 1 multiply and >=0 adds
  -- note that this thing must be a tree!
  local pos
  local mulCount = 0
  local addCount = 0
  ast:S("position"):traverse(function(n) pos = n end)
  while pos:parentCount(ast) > 0 do
    for k,_ in pos:parents(ast) do pos = k end
    if pos.kind=="binop" and (pos.op=="+" or pos.op=="-") then addCount = addCount+1
    elseif pos.kind=="binop" and (pos.op=="*" or pos.op=="/") then mulCount = mulCount+1
    else print(pos.kind,pos.op);assert(false) end
  end
  assert(mulCount==0)

  -- cheap hack, since the path from the position to the root is just a bunch of adds,
  -- we can get the translation by setting the position to 0
  local translate = ast:S("position"):process(
    function(n) 
      if n.kind=="position" then
        return orion.ast.new({kind="value",value=0}):copyMetadataFrom(n)
      end
    end)
  assert(translate:S("position"):count()==0)
  return translate:optimize(), 1
end


-- returns the stencil with (0,0,0) at the origin
-- if input isn't null, only calculate stencil for this input (a kernelGraph node)
function typedASTFunctions:stencil(input)

  -- the translate operator can take a few different arguments as translations
  -- it can contain binary + ops, and mapreduce vars. This evaluates all possible
  -- index values to find the correct stencil for those situations
  local function translateArea(t1,t2)
    if type(t1)=="number" then t1=orion.ast.new({kind="value",value=t1}) end
    if type(t2)=="number" then t2=orion.ast.new({kind="value",value=t2}) end
    return t1:eval(1):product(t2:eval(2))
  end

  if self.kind=="binop" then
    return self.lhs:stencil(input):unionWith(self.rhs:stencil(input))
  elseif self.kind=="multibinop" then
    local res = Stencil.new()

    for i=1,self:arraySize("lhs") do
      res = res:unionWith(self["lhs"..i]:stencil(input))
    end

    for i=1,self:arraySize("rhs") do
      res = res:unionWith(self["rhs"..i]:stencil(input))
    end

    return res
  elseif self.kind=="multiunary" then
    local res = Stencil.new()

    for i=1,self:arraySize("expr") do
      res = res:unionWith(self["expr"..i]:stencil(input))
    end

    return res
  elseif self.kind=="unary" then
    return self.expr:stencil(input)
  elseif self.kind=="assert" then
    return self.cond:stencil(input):unionWith(self.expr:stencil(input))
  elseif self.kind=="cast" then
    return self.expr:stencil(input)
  elseif self.kind=="select" or self.kind=="vectorSelect" then
    return self.cond:stencil(input)
    :unionWith(self.a:stencil(input)
               :unionWith(self.b:stencil(input)
                          ))
  elseif self.kind=="position" or self.kind=="tap" or self.kind=="value" then
    return Stencil.new()
  elseif self.kind=="tapLUTLookup" then
    return self.index:stencil(input)
  elseif self.kind=="load" then
    local s = Stencil.new()
    if input==nil or input==self.from then s = translateArea(self.relX,self.relY) end
    return s
  elseif self.kind=="gather" then
    --if input~=nil then assert(false) end
    assert(self.input.kind=="load")

    if input~=nil and self.input.from~=input then
      return Stencil.new() -- not the input we're interested in
    else
      -- note the kind of nasty hack we're doing here: gathers read from loads, and loads can be shifted.
      -- so we need to shift this the same as the load
      return translateArea(self.input.relX, self.input.relY):product( Stencil.new():add(-self.maxX,-self.maxY,0):add(self.maxX,self.maxY,0))
    end
  elseif self.kind=="array" then
    local exprsize = self:arraySize("expr")
    local s = Stencil.new()
    for i=1,exprsize do
      s = s:unionWith(self["expr"..i]:stencil(input))
    end

    return s
  elseif self.kind=="reduce" then
    local s = Stencil.new()
    local i=1
    while self["expr"..i] do
      s = s:unionWith(self["expr"..i]:stencil(input))
      i=i+1
    end
    return s
  elseif self.kind=="index" then
    return self.expr:stencil(input)
  elseif self.kind=="crop" then
    return self.expr:stencil(input)
  elseif self.kind=="transformBaked" then
    return self.expr:stencil(input):product(translateArea(self.translate1,self.translate2))
  elseif self.kind=="mapreduce" then
    return self.expr:stencil(input)
  elseif self.kind=="mapreducevar" then
    return Stencil.new()
  end

  print(self.kind)
  assert(false)
end

function typedASTFunctions:irType()
  return "typedAST"
end

-- get this node's value at compile time.
-- if can't be determined, return nil
function typedASTFunctions:eval()
  if self.kind=="value" then
    return self.value
  elseif self.kind=="unary" then
    if self.op=="-" then return -(self.expr:eval()) else
      assert(false)
    end
  else
    print("could not convert to a constant"..self.kind)
    assert(false)
  end

  return nil
end


function orion.typedAST._toTypedAST(inast)

  local res = inast:visitEach(
    function(origast,inputs)
      assert(orion.ast.isAST(origast))
      local ast = origast:shallowcopy()

      if ast.kind=="value" then
        if ast.type==nil then ast.type=orion.type.valueToType(ast.value) end
        if ast.type==nil then
          orion.error("Internal error, couldn't convert "..tostring(ast.value).." to orion type", origast:linenumber(), origast:offset(), origast:filename() )
        end
      elseif ast.kind=="unary" then
        ast.expr = inputs["expr"][1]
        
        if ast.op=="-" then
          if orion.type.astIsUint(ast.expr) then
            orion.warning("You're negating a uint, this is probably not what you want to do!", origast:linenumber(), origast:offset(), origast:filename())
          end
          
          ast.type = ast.expr.type
        elseif ast.op=="floor" or ast.op=="ceil" then
          ast.type = orion.type.float(32)
        elseif ast.op=="abs" then
          if ast.expr.type==orion.type.float(32) then
            ast.type = orion.type.float(32)
          elseif ast.expr.type==orion.type.float(64) then
            ast.type = orion.type.float(64)
          elseif orion.type.isInt(ast.expr.type) or orion.type.isUint(ast.expr.type) then
            -- obv can't make it any bigger
            ast.type = ast.expr.type
          else
            ast.expr.type:print()
            assert(false)
          end
        elseif ast.op=="not" then
          if orion.type.isBool(ast.expr.type) then
            ast.type = ast.expr.type
          else
            orion.error("not only works on bools",origast:linenumber(), origast:offset())
            assert(false)
          end
        elseif ast.op=="sin" or ast.op=="cos" or ast.op=="exp" then
          if ast.expr.type==orion.type.float(32) then
            ast.type = orion.type.float(32)
          elseif ast.expr.type==orion.type.float(64) then
            ast.type = orion.type.float(64)
          else
            orion.error("sin, cos, and exp only work on floating point types",origast:linenumber(),origast:offset(),origast:filename())
          end
        elseif ast.op=="arrayAnd" then
          if orion.type.isArray(ast.expr.type) and orion.type.isBool(orion.type.arrayOver(ast.expr.type)) then
            ast.type = orion.type.bool()
          else
            orion.error("vectorAnd only works on arrays of bools",origast:linenumber(), origast:offset())
          end
        else
          print(ast.op)
          assert(false)
        end
        
      elseif ast.kind=="binop" then
        
        local lhs = inputs["lhs"][1]
        local rhs = inputs["rhs"][1]
        
        if lhs.type==nil then print("ST"..to_string(lhs)) end
        
        assert(lhs.type~=nil)
        assert(rhs.type~=nil)
        
        local thistype, lhscast, rhscast = orion.type.meet( lhs.type, rhs.type, ast.op, origast )
        
        if thistype==nil then
          orion.error("Type error, inputs to "..ast.op,origast:linenumber(), origast:offset(), origast:filename())
        end
        
        if lhs.type~=lhscast then lhs = orion.typedAST.new({kind="cast",expr=lhs,type=lhscast}):copyMetadataFrom(origast) end
        if rhs.type~=rhscast then rhs = orion.typedAST.new({kind="cast",expr=rhs,type=rhscast}):copyMetadataFrom(origast) end
        
        ast.type = thistype
        ast.lhs = lhs
        ast.rhs = rhs
        
      elseif ast.kind=="position" then
        -- if position is still in the tree at this point, it means it's being used in an expression somewhere
        -- choose a reasonable type...
        ast.type=orion.type.int(32)
      elseif ast.kind=="select" or ast.kind=="vectorSelect" then
        local cond = inputs["cond"][1]
        local a = inputs["a"][1]
        local b = inputs["b"][1]

        if ast.kind=="vectorSelect" then
          if orion.type.arrayOver(cond.type)~=orion.type.bool() then
            orion.error("Error, condition of vectorSelect must be array of booleans. ",origast:linenumber(),origast:offset())
            return nil
          end

          if orion.type.isArray(cond.type)==false or
            orion.type.isArray(a.type)==false or
            orion.type.isArray(b.type)==false or
            orion.type.arrayLength(a.type)~=orion.type.arrayLength(b.type) or
            orion.type.arrayLength(cond.type)~=orion.type.arrayLength(a.type) then
            orion.error("Error, all arguments to vectorSelect must be arrays of the same length",origast:linenumber(),origast:offset())
            return nil            
          end
        else
          if cond.type ~= orion.type.bool() then
            orion.error("Error, condition of select must be scalar boolean. Use vectorSelect",origast:linenumber(),origast:offset(),origast:filename())
            return nil
          end

          if orion.type.isArray(a.type)~=orion.type.isArray(b.type) then
            orion.error("Error, if any results of select are arrays, all results must be arrays",origast:linenumber(),origast:offset())
            return nil
          end
          
          if orion.type.isArray(a.type) and
            orion.type.arrayLength(a.type)~=orion.type.arrayLength(b.type) then
            orion.error("Error, array arguments to select must be the same length",origast:linenumber(),origast:offset())
            return nil
          end
        end

        local thistype, lhscast, rhscast =  orion.type.meet(a.type,b.type, ast.kind, origast)

        if a.type~=lhscast then a = orion.typedAST.new({kind="cast",expr=a,type=lhscast}):copyMetadataFrom(origast) end
        if b.type~=rhscast then b = orion.typedAST.new({kind="cast",expr=b,type=rhscast}):copyMetadataFrom(origast) end
        
        ast.type = thistype
        ast.cond = cond
        ast.a = a
        ast.b = b
        
      elseif ast.kind=="index" then
        local expr = inputs["expr"][1]
        
        if orion.type.isArray(expr.type)==false then
          orion.error("Error, you can only index into an array type!",origast:linenumber(),origast:offset())
          os.exit()
        end
        
        ast.expr = expr

        if inputs["index"][1].kind~="value" then
          orion.error("index must be a value",origast:linenumber(), origast:offset())
        end

        if orion.type.isInt(inputs["index"][1].type)==false and
          orion.type.isUint(inputs["index"][1].type)==false then
          orion.error("index must be a integer",origast:linenumber(), origast:offset())
        end

        ast.index = inputs["index"][1].value
        ast.type = orion.type.astArrayOver(expr)
        
      elseif ast.kind=="transform" then
        ast.expr = inputs["expr"][1]
        
        -- this just gets the value of the thing we're translating
        ast.type = ast.expr.type
        
        local i=1
        while ast["arg"..i] do
          ast["arg"..i] = inputs["arg"..i][1] 
          i=i+1
        end
        
        -- now make the new transformBaked node out of this
        local newtrans = {kind="transformBaked",expr=ast.expr,type=ast.expr.type}
        
        local noTransform = true

        local i=1
        while ast["arg"..i] do
          -- if we got here we can assume it's valid
          local translate,scale=orion.typedAST.synthOffset( origast["arg"..i], orion.dimToCoord[i])
          assert(translate~=nil)
          newtrans["translate"..i]=translate
          newtrans["scale"..i]=scale

          if translate~=0 or scale~=1 then noTransform = false end
          i=i+1
        end
        
        -- at least 2 arguments must be specified. 
        -- the parser was supposed to guarantee this.
        assert(i>2)

        if noTransform then -- eliminate unnecessary transforms early
          ast=ast.expr:shallowcopy()
        else
          ast=newtrans
        end

      elseif ast.kind=="array" then
        
        local cnt = 1
        while ast["expr"..cnt] do
          ast["expr"..cnt] = inputs["expr"..cnt][1]
          cnt = cnt + 1
        end
        
        local mtype = ast.expr1.type
        local atype, btype
        
        if orion.type.isArray(mtype) then
          orion.error("You can't have nested arrays (index 0 of vector)",origast:linenumber(),origast:offset(),origast:filename())
        end
        
        local cnt = 2
        while ast["expr"..cnt] do
          if orion.type.isArray(ast["expr"..cnt].type) then
            orion.error("You can't have nested arrays (index "..(i-1).." of vector)")
          end
          
          mtype, atype, btype = orion.type.meet( mtype, ast["expr"..cnt].type, "array", origast)
          
          if mtype==nil then
            orion.error("meet error")      
          end
          
          -- our type system should have guaranteed this...
          assert(mtype==atype)
          assert(mtype==btype)
          
          cnt = cnt + 1
        end
        
        -- now we've figured out what the type of the array should be
        
        -- may need to insert some casts
        local cnt = 1
        while ast["expr"..cnt] do
          -- meet should have failed if this isn't possible...
          local from = ast["expr"..cnt].type

          if from~=mtype then
            if orion.type.checkImplicitCast(from, mtype,origast)==false then
              orion.error("Error, can't implicitly cast "..from:str().." to "..mtype:str(), origast:linenumber(), origast:offset())
            end
            
            ast["expr"..cnt] = orion.typedAST.new({kind="cast",expr=ast["expr"..cnt], type=mtype}):copyMetadataFrom(ast["expr"..cnt])
          end

          cnt = cnt + 1
        end
        
        local arraySize = cnt - 1
        ast.type = orion.type.array(mtype, arraySize)
        

      elseif ast.kind=="cast" then

        -- note: we don't eliminate these cast nodes, because there's a difference
        -- between calculating a value at a certain precision and then downsampling,
        -- and just calculating the value at the lower precision.
        ast.expr = inputs["expr"][1]
        
        if orion.type.checkExplicitCast(ast.expr.type,ast.type,origast)==false then
          orion.error("Casting from "..ast.expr.type:str().." to "..ast.type:str().." isn't allowed!",origast:linenumber(),origast:offset())
        end
      elseif ast.kind=="assert" then

        ast.cond = inputs["cond"][1]
        ast.expr = inputs["expr"][1]
        ast.printval = inputs["printval"][1]

        if orion.type.astIsBool(ast.cond)==false then
          orion.error("Error, condition of assert must be boolean",ast:linenumber(),ast:offset())
          return nil
        end

        ast.type = ast.expr.type

      elseif ast.kind=="mapreducevar" then
        ast.low = inputs["low"][1]:eval()
        ast.high = inputs["high"][1]:eval()
        ast.type = orion.type.int(32)

--        ast.type = orion.type.meet(ast.low.type,ast.high.type,"mapreducevar", origast)
      elseif ast.kind=="tap" then
        -- taps should be tagged with type already
      elseif ast.kind=="tapLUTLookup" then
        ast.index = inputs["index"][1]
        
        -- tapLUTs should be tagged with type already
        assert(orion.type.isType(ast.type))
        
        if orion.type.isUint(ast.index.type)==false and
          orion.type.isInt(ast.index.type)==false then
          
          orion.error("Error, index into tapLUT must be integer",ast:linenumber(),ast:offset())
          return nil
        end
      elseif ast.kind=="crop" then
        ast.expr = inputs["expr"][1]
        ast.type = ast.expr.type
      elseif ast.kind=="reduce" then
        local i=1
        local typeSet = {}

        while ast["expr"..i] do
          ast["expr"..i] = inputs["expr"..i][1]
          table.insert(typeSet,ast["expr"..i].type)
          
          i=i+1
        end

        ast.type = orion.type.reduce( ast.op, typeSet)
      elseif ast.kind=="outputs" then
        -- doesn't matter, this is always the root and we never need to get its type
        ast.type = inputs.expr1[1].type

        local i=1
        while ast["expr"..i] do
          ast["expr"..i] = inputs["expr"..i][1]
          i=i+1
        end

      elseif ast.kind=="type" then
        -- ast.type is already a type, so don't have to do anything
        -- shouldn't matter, but need to return something
      elseif ast.kind=="gather" then
        ast.type = inputs.input[1].type
        ast.input = inputs.input[1]
        ast.x = inputs.x[1]
        ast.y = inputs.y[1]

        if orion.type.isInt(ast.x.type)==false then
          orion.error("Error, x argument to gather must be int but is "..ast.x.type:str(), origast:linenumber(), origast:offset())
        end

        if orion.type.isInt(ast.y.type)==false then
          orion.error("Error, y argument to gather must be int but is "..ast.y.type:str(), origast:linenumber(), origast:offset())
        end
      elseif ast.kind=="load" then
        -- already has a type
      elseif ast.kind=="mapreduce" then
        if ast.reduceop=="sum" then
          ast.type = inputs.expr[1].type
        elseif ast.reduceop=="argmin" or ast.reduceop=="argmax" then
          ast.type = orion.type.array(orion.type.int(32),origast:arraySize("varname"))
        else
          orion.error("Unknown reduce operator '"..ast.reduceop.."'")
        end

        ast.expr = inputs.expr[1]

        local i = 1
        while ast["varname"..i] do
          ast["varlow"..i] = inputs["varlow"..i][1]:eval()
          ast["varhigh"..i] = inputs["varhigh"..i][1]:eval()
          i = i + 1
        end

      else
        orion.error("Internal error, typechecking for "..ast.kind.." isn't implemented!",ast.line,ast.char)
        return nil
      end
      
      if orion.type.isType(ast.type)==false then print(ast.kind) end
      ast = orion.typedAST.new(ast):copyMetadataFrom(origast)
      assert(orion.type.isType(ast.type))

      return {ast}
    end)

  return res[1], res[2]
end

function orion.typedAST.astToTypedAST(ast, options)
  assert(orion.ast.isAST(ast))
  assert(type(options)=="table")

  -- first we run CSE to clean up the users code
  -- this will save us a lot of time/memory later on
  ast = orion.optimize.CSE(ast,{})

  if options.verbose or options.printstage then 
    print("toTyped") 
    print("nodecount",ast:S("*"):count())
    print("maxDepth",ast:maxDepth())
  end

  if orion.verbose or orion.printstage then 
    print("desugar")
  end

  -- desugar mapreduce expressions etc
  -- we can't do this in _toTypedAST, b/c mapreducevar's aren't
  -- allowed anywhere (so these expressions are technically invalid)
  -- so we do this first as a preprocessing step.
  --
  -- we also don't want to do these desugaring in compileTimeProcess,
  -- b/c that will potentially grow memory usage exponentially
  ast = ast:S(function(n) 
                return n.kind=="let" or 
                  n.kind=="switch" end):process(
    function(node)
      if node.kind=="let" then
        local cnt = 1
        local namemap = {}

        local function removeLet( expr, namemap )
          return expr:S("letvar"):process(
            function(n)
              if namemap[n.variable]~=nil then
                return namemap[n.variable]
              end
              return n
            end)
        end

        while node["expr"..cnt] do
          namemap[node["exprname"..cnt]] = removeLet(node["expr"..cnt],namemap)
          cnt = cnt + 1
        end

        return removeLet(node.res, namemap)
      elseif node.kind=="switch" then
        local cnt = node:arraySize("expr")
        
        local cond = orion.ast.new({kind="binop",op="==",lhs=node.controlExpr,rhs=node["val"..cnt]}):copyMetadataFrom(node)
        local select = orion.ast.new({kind="select",cond=cond,a=node["expr"..cnt],b=node.default}):copyMetadataFrom(node)
        
        cnt = cnt-1
        while cnt > 0 do
          cond = orion.ast.new({kind="binop",op="==",lhs=node.controlExpr,rhs=node["val"..cnt]}):copyMetadataFrom(node)
          select = orion.ast.new({kind="select",cond=cond,a=node["expr"..cnt],b=select}):copyMetadataFrom(node)
          cnt = cnt - 1
        end
        
        return select

      end
    end)

  if options.verbose then
    print("desugar done")
  end

  -- should have been eliminated
  if orion.debug then assert(ast:S(function(n) return n.kind=="letvar" or n.kind=="switch" end):count()==0) end

  if options.printstage then
    print("_toTypedAST",collectgarbage("count"))
  end

  local typedAST = orion.typedAST._toTypedAST(ast)

  if options.verbose or options.printstage then
    print("conversion to typed AST done ------------")
  end

  return typedAST
end


function orion.typedAST.isTypedAST(ast) return getmetatable(ast)==typedASTMT end

-- kind of a hack - so that the IR library can shallowcopy and then
-- modify an ast node without having to know its exact type
function typedASTFunctions:init()
  setmetatable(self,nil)
  orion.typedAST.new(self)
end

function orion.typedAST.new(tab)
  assert(type(tab)=="table")
  orion.IR.new(tab)
  return setmetatable(tab,typedASTMT)
end

