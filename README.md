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
