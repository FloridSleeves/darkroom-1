sudo kextunload -v -bundle com.apple.driver.AppleUSBFTDI  #mavs
papillio-prog -f out/$1.bit
sudo kextload -v -bundle com.apple.driver.AppleUSBFTDI
terra $1.lua test frame_128.bmp out/$1.metadata.lua
