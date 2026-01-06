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
