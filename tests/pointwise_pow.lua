terralib.require("test")
import "darkroom"

test(im(x,y) [uint8](orion.pow(testinput(x,y)/10,2)) end)
