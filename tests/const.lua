terralib.require("test")
import "darkroom"

-- we made this guy have a large size to test strip behavior too
local const = darkroomSimple.constant(orion.type.float(32), 4096, 4096, 75)

test(im(x,y)  [uint8]( const(x,y)) end)
