(terralib.loadfile("test.t"))()
import "darkroom"

test(im(x,y) 
      (iterate i=-1,1 A=darkroom.gatherColumn(testinput,i,1,-1,1,-1,1) reduce(sum)
         A[0]
      end)+testinput
end)
