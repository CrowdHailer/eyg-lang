# Trifle

> tis just a trifle

Generate using compiler

`lsusb`

`ls -l /dev/serial `
gets the tty
from page
https://tinygo.org/docs/reference/microcontrollers/arduino-mega2560/
`tinygo flash -target arduino-mega2560 /path/to/code`

The tiny program blinks
```
(cd mulch; tinygo flash -target=arduino-mega2560 -size=full -port=/dev/ttyACM0 ./cmd/tiny)
```

see sizes
```
(cd trifle; tinygo build -target=arduino-mega2560 -size=full ./device)
(cd trifle; tinygo flash -target=arduino-mega2560 -size=full -port=/dev/ttyACM0 ./device)
(cd trifle; tinygo monitor -baudrate=9600)
```


**fmt** package makes programs too big
tinygo test doesn't work with target