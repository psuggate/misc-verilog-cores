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

+ serial command protocol
