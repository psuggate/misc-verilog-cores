# USB Logic Core for MMIO to AXI and APB

Connects the AXI and APB buses of a SoC to a USB MMIO interface, for data transfer to/from the SoC, and also to support development and monitoring of the SoC. It may be desirable to include this core alongside JTAG, as the data bandwidth is orders of magnitude greater, and does not require that the SoC be paused -- if available AXI (USB, DDRx, APB, ...) bandwidth is sufficient so that these transfers do not disrupt normal operation of the SoC.

Uses a protocol inspired by the Bulk-Only Transport (BOT) USB Mass Storage Class (MSC), so that a high degree of robustness is achieved, while only requiring two USB endpoints, Bulk-Out and Bulk-In.

## Commands

FETCH and STORE streams of data from/to the AXI bus of the SoC.

GET and SET 16-bit values from/to the APB bus of the SoC.

QUERY the endpoints for status, etc.

READY to see if the USB MMIO core is able to process commmands.

## Responses

SUCCESS

FAILURE

CANCELED

INVALID

## Formats

Commands are 11B USB frames, with the frame containing only the command, and must have size of 11 bytes, only.

Either one or more BULK OUT, or BULK IN, data transfers (for USB to AXI transactions).

Responses are 7B USB frames, with the USB frame containing just the response, and must have size of seven bytes, only.

## Design

Constraints:

+ The host issues a command (either APB or AXI).
+ Responses are issued immediately for APB requests.
+ AXI requests consist of one or more data transfers, which are either Bulk Out, or Bulk In, followed by the peripheral's response frame.

AXI-only constraints:

+ After receiving an AXI command, data transfers occur until the requested number of bytes have been transferred.
+ AXI requires large transfers to be split at 4kB ("page") boundaries (and this framing is handled by the core). So one MMIO command may generate many AXI burst-transfers.
+ All USB data-frames have to be max-size, except for the final data-frame, which is _NOT_ max-size.
+ The final data-frame is either a ZDP or contain the number of remaining bytes.
+ A command completes with a response frame from the peripheral.
+ When an unexpected ZDP is received by the peripheral, the transaction is canceled, and the response frame contains `CANCELED`.
+ The peripheral issues a `ZDP` to cancel a transaction, with the response frame containing the reason-code.
+ If the transaction times-out, then the host should issue a `QUERY`, and if this fails as well (or returns a USB `STALL` response), then the peripheral must be reset. (TODO??)
