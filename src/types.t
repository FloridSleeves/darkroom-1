
darkroom.type={}
TypeFunctions = {}
TypeMT = {__index=TypeFunctions}

darkroom.type._bool=setmetatable({type="bool"}, TypeMT)

function darkroom.type.bool() return darkroom.type._bool end

darkroom.type._uint={}
function darkroom.type.uint(prec)
  darkroom.type._uint[prec] = darkroom.type._uint[prec] or setmetatable({type="uint",precision=prec},TypeMT)
  return darkroom.type._uint[prec]
end


darkroom.type._int={}
function darkroom.type.int(prec)
  darkroom.type._int[prec] = darkroom.type._int[prec] or setmetatable({type="int",precision=prec},TypeMT)
  return darkroom.type._int[prec]
end

darkroom.type._float={}
function darkroom.type.float(prec)
  darkroom.type._float[prec] = darkroom.type._float[prec] or setmetatable({type="float",precision=prec},TypeMT)
  return darkroom.type._float[prec]
end

darkroom.type._array={}
function darkroom.type.array(_type,size)
  assert(type(size)=="number")
  assert(getmetatable(_type)==TypeMT)
  assert(darkroom.type.isArray(_type)==false)

  darkroom.type._array[_type] = darkroom.type._array[_type] or {}
  darkroom.type._array[_type][size] = darkroom.type._array[_type][size] or setmetatable({type="array", over=_type, size=size},TypeMT)
  return darkroom.type._array[_type][size]
end

function darkroom.type.fromTerraType(ty)
  if darkroom.type.isType(ty) then return ty end

  assert(terralib.types.istype(ty))

  if ty==int32 then
    return darkroom.type.int(32)
  elseif ty==int16 then
    return darkroom.type.int(16)
  elseif ty==uint8 then
    return darkroom.type.uint(8)
  elseif ty==uint32 then
    return darkroom.type.uint(32)
  elseif ty==int8 then
    return darkroom.type.int(8)
  elseif ty==uint16 then
    return darkroom.type.uint(16)
  elseif ty==float then
    return darkroom.type.float(32)
  elseif ty==double then
    return darkroom.type.float(64)
  elseif ty==bool then
    return darkroom.type.bool()
  elseif ty:isarray() then
    return darkroom.type.array(darkroom.type.fromTerraType(ty.type),ty.N)
  end

  print("error, unsupported terra type",ty)
  assert(false)
end

-- given a lua variable, figure out the correct type and
-- least precision that can represent it
function darkroom.type.valueToType(v)

  if v==nil then return nil end
  
  if type(v)=="boolean" then
    return darkroom.type.bool()
  elseif type(v)=="number" then
    local vi, vf = math.modf(v) -- returns the integral bit, then the fractional bit
    
    -- you might be tempted to take things from 0...255 to a uint8 etc, but this is bad!
    -- then if the user write -(5+4) they get a positive number b/c it's a uint8!
    -- similarly, if you take -128...127 to a int8, you also get problems. Then, you
    -- try to meet this int8 with a uint8, and get a int16! (bc this is the only sensible thing)
    -- when really what you wanted is a uint8.
    -- much better to just make the default int32 and have users cast it to what they want
    
    if vf~=0 then
      return darkroom.type.float(32)
    else
      return darkroom.type.int(32)
    end
  elseif type(v)=="table" then
    if keycount(v)~=#v then return nil end
    local tys = {}
    for k,vv in ipairs(v) do
      tys[k] = darkroom.type.valueToType(vv)
      if tys[k]==nil then return nil end
    end
    return darkroom.type.array(darkroom.type.reduce("",tys),#v)
  end
  
  return nil -- fail
end

-- returns resultType, lhsType, rhsType
-- ast is used for error reporting
function darkroom.type.meet( a, b, op, ast)
  assert(darkroom.type.isType(a))
  assert(darkroom.type.isType(b))
  assert(type(op)=="string")
  assert(darkroom.IR.isIR(ast))
  
  assert(getmetatable(a)==TypeMT)
  assert(getmetatable(b)==TypeMT)

  local treatedAsBinops = {["select"]=1, ["vectorSelect"]=1,["array"]=1, ["mapreducevar"]=1, ["dot"]=1, ["min"]=1, ["max"]=1}

    if darkroom.type.isArray(a) and darkroom.type.isArray(b) then
      if darkroom.type.arrayLength(a)~=darkroom.type.arrayLength(b) then
        print("Type error, array length mismatch")
        return nil
      end
      
      if op=="dot" then
        local rettype,at,bt = darkroom.type.meet(a.over,b.over,op,ast)
        local convtypea = darkroom.type.array(at,darkroom.type.arrayLength(a))
        local convtypeb = darkroom.type.array(bt,darkroom.type.arrayLength(a))
        return rettype, convtypea, convtypeb
      elseif darkroom.cmpops[op] then
        -- cmp ops are elementwise
        local rettype,at,bt = darkroom.type.meet(a.over,b.over,op,ast)
        local convtypea = darkroom.type.array(at,darkroom.type.arrayLength(a))
        local convtypeb = darkroom.type.array(bt,darkroom.type.arrayLength(a))

        local thistype = darkroom.type.array(darkroom.type.bool(), darkroom.type.arrayLength(a))
        return thistype, convtypea, convtypeb
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        -- do it pointwise
        local thistype = darkroom.type.array(darkroom.type.meet(a.over,b.over,op,ast),darkroom.type.arrayLength(a))
        return thistype, thistype, thistype
      elseif op=="pow" then
        local thistype = darkroom.type.array(darkroom.type.float(32),darkroom.type.arrayLength(a))
        return thistype, thistype, thistype
      else
        print("OP",op)
        assert(false)
      end
      
    elseif a.type=="int" and b.type=="int" then
      local prec = math.max(a.precision,b.precision)
      local thistype = darkroom.type.int(prec)

      if darkroom.cmpops[op] then
        return darkroom.type.bool(), thistype, thistype
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        local thistype = darkroom.type.float(32)
        return thistype, thistype, thistype
      else
        print("OP",op)
        assert(false)
      end
    elseif a.type=="uint" and b.type=="uint" then
      local prec = math.max(a.precision,b.precision)
      local thistype = darkroom.type.uint(prec)

      if darkroom.cmpops[op] then
        return darkroom.type.bool(), thistype, thistype
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        local thistype = darkroom.type.float(32)
        return thistype, thistype, thistype
      else
        print("OP2",op)
        assert(false)
      end
    elseif (a.type=="uint" and b.type=="int") or (a.type=="int" and b.type=="uint") then

      local ut = a
      local t = b
      if a.type=="int" then ut,t = t,ut end
      
      local prec
      if ut.precision==t.precision and t.precision < 64 then
        prec = t.precision * 2
      elseif ut.precision<t.precision then
        prec = math.max(a.precision,b.precision)
      else
        darkroom.error("Can't meet a "..ut:str().." and a "..t:str(),ast:linenumber(),ast:offset(),ast:filename())
      end
      
      local thistype = darkroom.type.int(prec)
      
      if darkroom.cmpops[op] then
        return darkroom.type.bool(), thistype, thistype
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        return thistype, thistype, thistype
      else
        print( "operation " .. op .. " is not implemented for aType:" .. a.type .. " bType:" .. b.type .. " " )
        assert(false)
      end
      
    elseif (a.type=="float" and (b.type=="uint" or b.type=="int")) or 
      ((a.type=="uint" or a.type=="int") and b.type=="float") then

      local thistype
      local ftype = a
      local itype = b
      if b.type=="float" then ftype,itype=itype,ftype end
      
      if ftype.precision==32 and itype.precision<32 then
        thistype = darkroom.type.float(32)
      elseif ftype.precision==32 and itype.precision==32 then
        thistype = darkroom.type.float(32)
      elseif ftype.precision==64 and itype.precision<64 then
        thistype = darkroom.type.float(64)
      else
        assert(false) -- NYI
      end

      if darkroom.cmpops[op] then
        return darkroom.type.bool(), thistype, thistype
      elseif darkroom.intbinops[op] then
        darkroom.error("Passing a float to an integer binary op "..op,ast:linenumber(),ast:offset())
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        local thistype = darkroom.type.float(32)
        return thistype, thistype, thistype
      else
        print("OP4",op)
        assert(false)
      end

    elseif a.type=="float" and b.type=="float" then

      local prec = math.max(a.precision,b.precision)
      local thistype = darkroom.type.float(prec)

      if darkroom.cmpops[op] then
        return darkroom.type.bool(), thistype, thistype
      elseif darkroom.intbinops[op] then
        darkroom.error("Passing a float to an integer binary op "..op,ast:linenumber(),ast:offset())
      elseif darkroom.binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        local thistype = darkroom.type.float(32)
        return thistype, thistype, thistype
      else
        print("OP3",op)
        assert(false)
      end

    elseif a.type=="bool" and b.type=="bool" then
      -- you can combine two bools into an array of bools
      if darkroom.boolops[op]==nil and op~="array" then
        print("Internal error, attempting to meet two booleans on a non-boolean op: "..op,ast:linenumber(),ast:offset())
        return nil
      end
      
      local thistype = darkroom.type.bool()
      return thistype, thistype, thistype
    elseif darkroom.type.isArray(a) and darkroom.type.isArray(b)==false then
      -- we take scalar constants and duplicate them out to meet the other arguments array length
      local thistype, lhstype, rhstype = darkroom.type.meet(a,darkroom.type.array(b,darkroom.type.arrayLength(a)),op,ast)
      return thistype, lhstype, rhstype
    elseif darkroom.type.isArray(a)==false and darkroom.type.isArray(b) then
      local thistype, lhstype, rhstype = darkroom.type.meet(darkroom.type.array(a,darkroom.type.arrayLength(b)),b,op,ast)
      return thistype, lhstype, rhstype
    else
      print("Type error, meet not implemented for "..darkroom.type.typeToString(a).." and "..darkroom.type.typeToString(b),"line",ast:linenumber(),ast:filename())
      print(ast.op)
      assert(false)
      --os.exit()
    end
    
    assert(false)
  return nil
end

-- convert a string describing a type like 'int8' to its actual type
function darkroom.type.stringToType(s)
  if s=="rgb8" then
    local res = darkroom.type.array(darkroom.type.uint(8),3)
    assert(darkroom.type.isType(res))
    return res
  elseif s=="rgbw8" then
    return darkroom.type.array(darkroom.type.uint(8),4)
  elseif s:sub(1,4) == "uint" then
    if s=="uint" then
      darkroom.error("'uint' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(5))==nil then return nil end
    return darkroom.type.uint(tonumber(s:sub(5)))
  elseif s:sub(1,3) == "int" then
    if s=="int" then
      darkroom.error("'int' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(4))==nil then return nil end
    return darkroom.type.int(tonumber(s:sub(4)))
  elseif s:sub(1,5) == "float" then
    if s=="float" then
      darkroom.error("'float' is not a valid type, you must specify a precision")
      return nil
    end
    if tonumber(s:sub(6))==nil then return nil end
    return darkroom.type.float(tonumber(s:sub(6)))
  elseif s=="bool" then
    return darkroom.type.bool()
  else

  end
 
  --print("Error, unknown type "..s)
  return nil
end

-- check if type 'from' can be converted to 'to' (explicitly)
function darkroom.type.checkExplicitCast(from, to, ast)
  assert(from~=nil)
  assert(to~=nil)
  assert(darkroom.ast.isAST(ast))

  if from==to then
    -- obvously can return true...
    return true
  elseif darkroom.type.isArray(from) and darkroom.type.isArray(to) then
    if darkroom.type.arrayLength(from)~=darkroom.type.arrayLength(to) then
      darkroom.error("Can't change array length when casting "..from:str().." to "..to:str(),ast:linenumber(),ast:offset(),ast:filename())
    end

    return darkroom.type.checkExplicitCast(from.over, to.over,ast)

  elseif darkroom.type.isArray(from)==false and darkroom.type.isArray(to)  then
    return darkroom.type.checkExplicitCast(from, to.over,ast)

  elseif darkroom.type.isArray(from) and darkroom.type.isArray(to)==false then
    darkroom.error("Can't cast an array type to a non-array type. "..from:str().." to "..to:str(),ast:linenumber(),ast:offset(),ast:filename())
    return false
  elseif from.type=="uint" and to.type=="uint" then
    return true
  elseif from.type=="int" and to.type=="int" then
    return true
  elseif from.type=="uint" and to.type=="int" then
    return true
  elseif from.type=="float" and to.type=="uint" then
    return true
  elseif from.type=="uint" and to.type=="float" then
    return true
  elseif from.type=="int" and to.type=="float" then
    return true
  elseif from.type=="int" and to.type=="uint" then
    return true
  elseif from.type=="int" and to.type=="bool" then
    darkroom.error("converting an int to a bool will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.type=="bool" and (to.type=="int" or to.type=="uint") then
    darkroom.error("converting a bool to an int will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.type=="float" and to.type=="int" then
    return true
  elseif from.type=="float" and to.type=="float" then
    return true
  else
    from:print()
    to:print()
    assert(false) -- NYI
  end

  return false
end

-- compare this to meet - this is where we can't change the type of 'to',
-- so we just have to see if 'from' can be converted to 'to'
function darkroom.type.checkImplicitCast(from, to, ast)
  assert(from~=nil)
  assert(to~=nil)
  assert(darkroom.ast.isAST(ast))

  if from.type=="uint" and to.type=="uint" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.type=="uint" and to.type=="int" then
    if to.precision > from.precision then
      return true
    end
  elseif from.type=="int" and to.type=="int" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.type=="uint" and to.type=="float" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.type=="int" and to.type=="float" then
    if to.precision >= from.precision then
      return true
    end
  elseif from.type=="float" and to.type=="float" then
    if to.precision >= from.precision then
      return true
    end
  end


  return false
end

---------------------------------------------------------------------
-- 'externally exposed' functions

-- this will only work on a typed ast
function darkroom.getType(ast)
  assert(type(ast)=="table")
  assert(ast.type~=nil)
  return ast.type
end

function darkroom.type.isFloat(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="float"
end

function darkroom.type.astIsFloat(ast)
  return darkroom.type.isFloat(darkroom.getType(ast))	 
end

function darkroom.type.isUint(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="uint"
end

function darkroom.type.astIsUint(ast)
  return darkroom.type.isUint(darkroom.getType(ast))
end


function darkroom.type.isInt(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="int"
end

function darkroom.type.astIsInt(ast)
  return darkroom.type.isInt(darkroom.getType(ast))
end

function darkroom.type.isNumber(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="float" or ty.type=="uint" or ty.type=="int"
end

function darkroom.type.astIsNumber(ast)
  return darkroom.type.isNumber(darkroom.getType(ast))	 
end

function darkroom.type.isBool(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="bool"
end

function darkroom.type.astIsBool(ast)
  return darkroom.type.isBool(darkroom.getType(ast))
end

function darkroom.type.isArray(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.type=="array"
end

function darkroom.type.astIsArray(ast)
  assert(darkroom.ast.isAST(ast))
  return darkroom.type.isArray(darkroom.getType(ast))
end
-- returns 0 if not an array
function darkroom.type.arrayLength(ty)
  assert(getmetatable(ty)==TypeMT)
  if ty.type~="array" then return 0 end
  return ty.size  
end

-- returns 0 if ast is not an array
function darkroom.type.astArrayLength(ast)
  return darkroom.type.arrayLength(darkroom.getType(ast))
end


function darkroom.type.arrayOver(ty)
  assert(getmetatable(ty)==TypeMT)
  return ty.over
end

function darkroom.type.astArrayOver(ast)
  local ty = darkroom.getType(ast)
  assert(darkroom.type.isArray(ty))
  return darkroom.type.arrayOver(ty)
end

function darkroom.type.isType(ty)
  return getmetatable(ty)==TypeMT
end

function darkroom.type.isCropMode(cropMode)
  return cropMode == darkroom.cropSame or 
    cropMode == darkroom.cropGrow or 
    cropMode == darkroom.cropShrink or
    cropMode == darkroom.cropExplicit

end

-- return precision of this type
function darkroom.type.precision(ty)
  if darkroom.type.isUint(ty) then
    return ty.precision
  else
    assert(false)
  end
end

-- convert this uint type to an int type with same precision
function darkroom.type.uintToInt(ty)
  assert(darkroom.type.isUint(ty))
  return darkroom.type.int(darkroom.type.precision(ty))
end

function darkroom.type.typeToString(ty)
  assert(darkroom.type.isType(ty))

  if ty.type=="bool" then
    return "bool"
  elseif ty.type=="int" then
    return "int"..ty.precision
  elseif ty.type=="uint" then
    return "uint"..ty.precision
  elseif ty.type=="float" then
    return "float"..ty.precision
  elseif ty.type=="array" then
    return darkroom.type.typeToString(ty.over).."["..ty.size.."]"
  end

  print("Error, typeToString input doesn't appear to be a type")
  os.exit()
end

function darkroom.type.astTypeToString(ast)
  return darkroom.type.typeToString(darkroom.getType(ast))
end

-- returns size in bytes
function darkroom.type.sizeof(ty)
  if ty.type=="float" and ty.precision==32 then
    return 4
  elseif ty.type=="uint" and ty.precision==8 then
    return 1
  end

  print(darkroom.type.typeToString(ty))

  assert(false)
  return nil
end

function TypeFunctions:toC()
  if self.type=="float" and self.precision==32 then
    return "float"
  elseif self.type=="uint" and self.precision==8 then
    return "unsigned char"
  else
    assert(false)
  end
end

function TypeFunctions:print()
  print(darkroom.type.typeToString(self))
end

function TypeFunctions:str()
 return darkroom.type.typeToString(self)
end

function TypeFunctions:isArray()
  return self.type=="array"
end

function TypeFunctions:toTerraType()
  return darkroom.type.toTerraType(self)
end

function TypeFunctions:sizeof()
  return terralib.sizeof(self:toTerraType())
end

function TypeFunctions:isFloat()
  return darkroom.type.isFloat(self)
end

function TypeFunctions:isBool()
  return darkroom.type.isBool(self)
end

function TypeFunctions:isInt()
  return darkroom.type.isInt(self)
end

function TypeFunctions:isUint()
  return darkroom.type.isUint(self)
end

function TypeFunctions:isNumber()
  return darkroom.type.isNumber(self)
end

function TypeFunctions:channels()
  if self.type~="array" then return 1 end
  return self.size
end

function TypeFunctions:baseType()
  if self.type~="array" then return self end
  return self.over
end

-- this calculates the precision of the result of a reduction tree.
-- op is the reduction op
-- typeTable is a list of the types we're reducing over
function darkroom.type.reduce(op,typeTable)
  assert(type(typeTable)=="table")
  assert(#typeTable>=1)
  for k,v in pairs(typeTable) do assert(darkroom.type.isType(v)) end

  return typeTable[1]
end


-- _type = the orion type
-- if pointer is true, generate a pointer instead of a value
-- vectorN = width of the vector [optional]
function darkroom.type.toTerraType(_type,pointer,vectorN)
  assert(darkroom.type.isType(_type))

  local ttype

  if _type==darkroom.type.float(32) then
    ttype = float
  elseif _type==darkroom.type.float(64) then
    ttype = double
  elseif _type==darkroom.type.uint(8) then
    ttype = uint8
  elseif _type==darkroom.type.int(8) then
    ttype = int8
  elseif _type==darkroom.type.bool() then
    ttype = bool
  elseif _type==darkroom.type.int(32) then
    ttype = int32
  elseif _type==darkroom.type.int(64) then
    ttype = int64
  elseif _type==darkroom.type.uint(32) then
    ttype = uint32
  elseif _type==darkroom.type.uint(16) then
    ttype = uint16
  elseif _type==darkroom.type.int(16) then
    ttype = int16
  elseif darkroom.type.isArray(_type) then
    local baseType = darkroom.type.arrayOver(_type)
    local al = darkroom.type.arrayLength(_type)
    ttype = darkroom.type.toTerraType( baseType, pointer, vectorN )[al]
  else
    print(darkroom.type.typeToString(_type))
    print(debug.traceback())
    assert(false)
  end

  if vectorN then
    if pointer then return &vector(ttype,vectorN) end
    return vector(ttype,vectorN)
  else
    if pointer then return &ttype end
    return ttype
  end

  print(darkroom.type.typeToString(_type))
  assert(false)

  return nil
end

