# ULPI USB 2.0 High-Speed Core

Bulk IN and OUT endpoints.

## TODO

Fixes:

+ different endpoints for Bulk IN and OUT;
+ telemetry-parser;
+ return FSM to idle states, after timeout?
+ NAKs when not ready?
+ correctly handle all configuration events (Sec. 9.1.1.5)
+ generate STALL responses, when the USB host:
  - uses functions before setting configuration;
  - accesses invalid endpoints;
+ the *'Halt'* feature (Sec. 9.4.5) is required for all interrupt and bulk endpoints;
+ cover all *'Request Error'* cases;

Features:

+ PING
+ serial command protocol

## Core Start-Up

Power-on and resets are handled by the '`ulpi_reset`' module, and with a manual reset button ('`S1`', on the Sipeed Tang Primer 20k). The '`line_state`' module handles the High-Speed negotiation. The IOB outputs (which are registered) are fed to the '`ulpi_decoder`'.

## Protocol Layer

