terralib.require "test"
import "darkroom"

im out1(x,y)  testinput(x,y)/orion.uint8(2) end
im out2(x,y) testinput(x,y)/orion.uint8(2) end
im out(x,y)  out1(x,y) + out2(x,y) + orion.uint8(100) end

test(out)