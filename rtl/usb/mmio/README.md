# USB Logic Core for MMIO to AXI and APB

Connects the AXI and APB buses of a SoC to a USB MMIO interface, for data transfer to/from the SoC, and also to support development and monitoring of the SoC. It may be desirable to include this core alongside JTAG, as the data bandwidth is orders of magnitude greater, and does not require that the SoC be paused -- if available AXI (USB, DDRx, APB, ...) bandwidth is sufficient so that these transfers do not disrupt normal operation of the SoC.

Uses a protocol inspired by the Bulk-Only Transport (BOT) USB Mass Storage Class (MSC), so that a high degree of robustness is achieved, while only requiring two USB endpoints, Bulk-Out and Bulk-In.

## Commands

FETCH and STORE streams of data from/to the AXI bus of the SoC.

GET and SET 16-bit values from/to the APB bus of the SoC.

QUERY the endpoints for status, etc.

READY to see if the USB MMIO core is able to process commmands.
