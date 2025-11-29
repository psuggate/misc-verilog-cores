# README for the USB Driver

Example code for using the USB core from user-space.

Running tests:
```sh
$ cd driver
$ cargo run --help
```

# Appendix: Setting Up and Querying USB Hardware

## Setup

To see if the USB device enumerated:
```sh
$ sudo sysctl kernel.dmesg_restrict=0
$ dmesg
```

Setup `udev` rules (as superuser):
```sh
$ echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="f4ce", ATTRS{idProduct}=="0003", MODE="0666"' >> /etc/udev/rules.d/69-tart-usb.rules
```

## Querying

Find the USB bus identifiers:
```sh
lsusb
```
with example output:
```
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 001 Device 002: ID 046d:c548 Logitech, Inc. Logi Bolt Receiver
...
Bus 003 Device 029: ID f4ce:0003 University of Otago TART USB
...
Bus 010 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
```
Then, we can see `Bus 003`, and `Device 029`, allowing us to query:
```sh
lsusb -D /dev/bus/usb/003/029
```
and see the number of endpoints.
