(terralib.loadfile("test.t"))()
import "darkroom"

darkroomSimple.setImageSize(128,64)

im out(x,y) [uint8[3]]( if x>50 then {255,0,0} else {0,255,255} end) end

test(out)