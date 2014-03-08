--a = orion.load("300d.bmp")
--im a(x,y) : float32 a(x,y) end
import "orion"

a = orion.load("color.bmp")
im a(x,y) : float32[3] a(x,y) end

--im blurx(x,y) (a(x-1,y)+a(x,y)+a(x+1,y))/3 end
--im blurx(x,y) : uint8[3] (blurx(x-1,y)+blurx(x,y)+blurx(x+1,y))/3 end
im blurx(x,y) : uint8[3] 
map i=-5,5 reduce(sum) a(x+i,y)/11 end
end

--blurx:save("out/blurx.bmp")


tprog,model = orion.compile({blurx},
{
--schedule="default",
  schedule=arg[1],
debug=false, 
verbose=false,
printruntime=true,
looptimes=50})

terra doit()
  var res = tprog()
  res:save("out/blurx.bmp")
  end

doit()

print("model total",model.total)
for k,v in pairs(model.nodes) do
  print(k,v)
end