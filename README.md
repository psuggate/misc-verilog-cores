# misc-verilog-cores

A library of useful logic cores (Verilog, and optimised for FPGAs). Many of the modules are incomplete, though. Ideally, support for Xilinx and Lattice FPGAs, with the latter set up to work with the open-source toolchains.

## USB Core

Status:

- not robust;

- writes followed immediately be reads can fail, if the time between these is too short;

- lots of combinational delays for signals that should be registered, within the core;

Tasks to complete:

1. Timers to return FSM's to idle; e.g., when a transaction response does not arrive

2. Status registers for device statistics

3. Support for multiple Bulk- and Control- endpoints

4. PING protocol

5. Needs the driver code from 'axis_usbd' merged in to this repository

6. Endpoint select signals (that are registered)

### Playing with the USB Core

After building the project (`synth/sipeed-tang-primer-20k/usbcore.gprj`), write the bit-file to the FPGA:
```bash
> openFPGALoader --board tangprimer20k --write-sram impl/pnr/usbcore.fs
```
and see if it has successfully enumerated:
```bash
# Run this once, after startup, so that 'sudo' is not required for 'dmesg'
> sudo sysctl kernel.dmesg_restrict=0
# After writing the bit-file:
> dmesg
```
You will typically need to `RESET` the Tang Primer after writing the bit-file to the FPGA, and this is the (momentary switch) button '`S1`'.

### USB Core Telemetry

Additionally, the state-transitions are recorded, and can be read back via UART, or USB -- USB core telemetry read-back via UART:
```bash
> stty -F /dev/ttyUSB1 230400 cs8 -cstopb -parenb cread -echo clocal && cat /dev/ttyUSB1
```
or using the driver (subdirectory `driver/`):
```bash
> cd ../../driver
> cargo build
> ./target/debug/driver --log-level=debug --verbose --writeless --no-read --telemetry
```
and the output can be processed with a utility within `util/telemetry`:
```bash
> cd ../util/telemetry
> stack build
# And after saving the telemetry-dump to a text file:
> stack run -- <cap.txt>
```

### USB Core Packet Capture

WireShark for USB packet-capture:
```bash
# Setup a driver that allows the transfers to be PCAPed:
> sudo modprobe usbmon
> sudo setfacl -m u:$USER:r /dev/usbmon*
# Select 'usbmon0' (typically), once Wireshark starts:
> wireshark &
```
