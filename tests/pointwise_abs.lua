package.path = package.path .. ";../src/?.lua;../src/?.t"

terralib.require "test"
import "orion"

im in1(x,y) : float32  testinput(x,y) end
im in1(x,y) -in1(x,y) end
im out(x,y) orion.abs(in1(x,y)) end


test(out)