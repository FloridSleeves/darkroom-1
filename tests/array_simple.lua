package.path = package.path .. ";../src/?.lua;../src/?.t"

terralib.require("test")
import "orion"

im a(x,y) {1,2,3} end
im b(x,y) {2,4,6} end

test(im(x,y) : uint8[3], crop(0,0,100,100) (a(x,y)+b(x,y))*10 end)

-- should print {30,60,90}