
-- graph is just required to have some function 
-- :minUse(input) and :maxUse(input) declared on it, that return
-- the smallest and largest use offset that this node accesses.
--
-- It returns a map from node -> shift
function schedule(graph)
  assert(darkroom.kernelGraph.isKernelGraph(graph))

  local shifts = {}
  graph:S("*"):traverse(
    function(node) 
      if node.kernel~=nil then 
        shifts[node] = 0
        for k,v in node:inputs() do
          local s = node:maxUse(v) + shifts[v]
          if s > shifts[node] then shifts[node] = s end
        end
      end 
    end)

  return shifts
end

function synthRel(rel,t)
  if type(t)=="number" and type(rel)=="number" then
    return darkroom.ast.new({kind="value",value=rel+t})
  elseif type(rel)=="number" and darkroom.ast.isAST(t) then
    local v = darkroom.ast.new({kind="value",value=rel}):copyMetadataFrom(t)
    return darkroom.ast.new({kind="binop", lhs=t, rhs=v, op="+"}):copyMetadataFrom(t)
  elseif darkroom.ast.isAST(rel) and type(t)=="number" then
    local v = darkroom.ast.new({kind="value",value=t}):copyMetadataFrom(rel)
    return darkroom.ast.new({kind="binop", lhs=rel, rhs=v, op="+"}):copyMetadataFrom(rel)
  elseif darkroom.ast.isAST(rel) and darkroom.ast.isAST(t) then
    return darkroom.ast.new({kind="binop", lhs=rel, rhs=t, op="+"}):copyMetadataFrom(rel)
  else
    print(type(rel),type(t))
    assert(false)
  end
end

function shift(graph, shifts)
  assert(darkroom.kernelGraph.isKernelGraph(graph))

  local oldToNewRemap = {}
  local newToOldRemap = {}
  local newShifts = {} -- other compile stages use the shifts later

  local newGraph = graph:S("*"):process(
    function(kernelGraphNode, orig)
      if kernelGraphNode.kernel~=nil then
        local newKernelGraphNode = kernelGraphNode:shallowcopy()
        
        -- eliminate transforms
        -- this is wildly inefficient in general. But its only slow in corner cases b/c it is uncommon to have transforms within kernel graph nodes
        newKernelGraphNode.kernel = kernelGraphNode.kernel:S("transformBaked"):process(
          function(n)
            return n.expr:S(function(n) return n.kind=="load" or n.kind=="position" end):process(
              function(nn)
                if nn.kind=="load" then
                  local r = nn:shallowcopy()                  

                  r.relX = synthRel(r.relX, n.translate1):optimize()
                  r.relY = synthRel(r.relY, n.translate2):optimize()

                  if type(nn.from)=="table" then r.from = oldToNewRemap[nn.from]; assert(r.from~=nil) end
                  return darkroom.typedAST.new(r):copyMetadataFrom(nn)
                elseif nn.kind=="position" then

                  local res = {kind="binop", lhs=nn, type = nn.type, op="+"}

                  if nn.coord=="x" then
                    res.rhs = darkroom.typedAST._toTypedAST(n.translate1)
                  elseif nn.coord=="y" then
                    res.rhs = darkroom.typedAST._toTypedAST(n.translate2)
                  else
                    assert(false)
                  end

                  return darkroom.typedAST.new(res):copyMetadataFrom(nn)
                else
                  assert(false)
                end
              end)
          end)

        -- apply shift
        newKernelGraphNode.kernel = newKernelGraphNode.kernel:S(function(n) return n.kind=="load" or n.kind=="crop" or n.kind=="position" end):process(
          function(nn)
            if nn.kind=="load" then
              if type(nn.from)=="table" then
                local r = nn:shallowcopy()
                r.relY = synthRel(r.relY, shifts[newToOldRemap[nn.from]]-shifts[orig]):optimize()
                if type(nn.from)=="table" then r.from = oldToNewRemap[nn.from]; assert(r.from~=nil) end
                return darkroom.typedAST.new(r):copyMetadataFrom(nn)
              end
            elseif nn.kind=="crop" then
              local r = nn:shallowcopy()
              r.shiftY = r.shiftY + shifts[orig]
              return darkroom.typedAST.new(r):copyMetadataFrom(nn)
            elseif nn.kind=="position" then
              if nn.coord=="y" and shifts[orig]~=0 then
                local v = darkroom.typedAST.new({kind="value", value=-shifts[orig], type=nn.type}):copyMetadataFrom(nn)
                return darkroom.typedAST.new({kind="binop", lhs=nn, rhs = v, type = nn.type, op="+"}):copyMetadataFrom(nn)
              end
            else
              print(nn.kind)
              assert(false)
            end
          end)

        local res = darkroom.kernelGraph.new(newKernelGraphNode):copyMetadataFrom(kernelGraphNode)
        oldToNewRemap[orig] = res
        oldToNewRemap[res] = res -- remember, we might touch nodes multiple times
        newToOldRemap[res] = orig
        newToOldRemap[orig] = orig
        newShifts[res] = shifts[orig]
        return res
      end
    end)

  return newGraph, newShifts
end