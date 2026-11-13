# USB Port priority

Y90 and Y700 gen 2 have same usb priority system (Y70 is exclude since it only have one usb port, and that one need separate readme page for most obscure, piece of shit type c driver i ever seen)

- if you plug monitor to usb C1, usb C2 will allow you to charge, using with usb flash drive or usb dac, but **not** usb c inside the hub (note, only usb flash drive, you can plug mouse and keyboard)
- if you plug usb hub inside C1, C2 will only allow to charge only due to usb priority on C1
- if you plug usb dac on C1, C2 will only allow to charge battery

so whatever the fuck you do, plan your usb plugging

also, on lenovo lgsi source code, it specifically note that you aren't allow to use 2 usb data at same time

and i didn't made it up, here's actual commit of [lenovo usb c changes](https://github.com/lolipuru/kernel_lenovo_sm8475/commit/316f0cac84c2cadc8ab439413a06055c6007d086)