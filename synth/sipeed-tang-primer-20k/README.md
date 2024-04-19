# USB Demo for the Sipeed Tang Primer 20k

Load the FPGA bit-file into SRAM:
```bash
$ make
```

To see if the USB device enumerated:
```bash
$ sudo sysctl kernel.dmesg_restrict=0
$ dmesg
```

Setup `udev` rules (as superuser):
```bash
$ echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="f4ce", ATTRS{idProduct}=="0003", MODE="0666"' >> /etc/udev/rules.d/69-tart-usb.rules
```

Running tests:
```bash
$ cd driver
$ cargo run --help
```

To access telemetry:
```bash
$ stty -F /dev/ttyUSB1 230400 cs8 -cstopb -parenb cread -echo clocal && cat /dev/ttyUSB1
```
