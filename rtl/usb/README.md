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

## DMA Design

The DMA design (outlined below) allows "frames" larger than USB '`MAX_LENGTH`' to be chunked, transmitted, and then re-assembled. This is useful for TART, as the visibilities data is several kB, and if a received frame is of the correct size then we know that the operation was successful -- without requiring additional framing and CRC overhead.

### Bulk IN DMA

Features for Bulk IN:

 1. Prefetch by default (so assert '`s_tready`' when there exists space for a max-size packet).
 2. Break into '`MAX_LENGTH`' (512 byte) packets.
 3. Generate a Zero-Data Packet (ZDP) if the total length is a multiple of '`MAX_LENGTH`'?
 2. Use the '`next_i`' signal to advance to the next packet only after the USB host sends an 'ACK' handshake packet.
 9. Support '`redo_i`' if previous 'IN' transaction timed-out.
 7. Reset the packet FIFO on "configuration events."
 4. Calculate packet-length on TX, so that 'tkeep' does not need to be stored?

Scenarios:

 #. Prefetch packets < 512B, and successully sent: '`parameter SAVE_ON_LAST = 1`{.v}', and keep '`ready_o`' asserted as long as space >= 512B? And as each 'ACK' is received, advance to the '`next_i`' packet? If a TX times-out, then issue a '`redo_i`' packet?
 5. Prefetch frames > 512B, and assert '`valid_o`' when > 512B is stored within the packet FIFO -- deasserting when '`level_o`' drops below 512B, and advancing in 512B chunks, as each 'ACK' is received? If a TX times-out, then issue a '`redo_i`' packet?

Invariants:

1. There is always at least '`MAX_LENGTH - level_o`' space; i.e., that available space is always exact, or pessimistic -- never optimistic?
2. If frame-length is a multiple of '`MAX_LENGTH`', then a ZDP is always queued afterwards?
3. For '`MAX_LENGTH`' chunk, '`m_tvalid`' deasserts on reaching 512B, and only reasserts once an 'ACK' is received?

### Bulk OUT DMA

Features for Bulk OUT:

 8. Accept large frames as multiple '`MAX_LENGTH`' packets, followed by a (potentially zero-sized) residual < '`MAX_LENGTH`'.
 4. Only assert '`ready_o`' when there is space for a '`MAX_LENGTH`' packet.
 6. We '`save_i`' a packet (chunk) if the CRC16 succeeds, or else we '`drop_i`' it.
 7. Reset the packet FIFO on "configuration events."
 0. If available space drops below '`MAX_LENGTH`', we assert 'NYET'^[TODO: Are 'NYET' responses only sent for transaction preceeded by 'PING' queries?].
 1. For packets less than '`MAX_LENGTH`', '`m_tlast`' is asserted at the end of the packet (whether it corresponds to an entire frame, or the residual of a large frame), and ZDPs generate an "empty tlast" response?
 2. Until we '`save_i`' a packet (chunk), '`m_tvalid`' remains deasserted (if no other packet in FIFO).

Scenarios:

#. A DATAx packet is received during an 'OUT' transaction, and the length < MAX_LENGTH, so if the CRC16 succeeds, we '`save_i`' the packet, and the read-back stream terminates with a 'tlast' assertion.
#. 'NAK's are issued if available space drops below 512B, with a 'NYET' being issued for the handshake of the transaction that reduced the space below 512B.
#. Received data can be accessed before the entire frame has been received, as long as each 512B chunk passes CRC16.
0. If the 'ACK' was corrupted (sent to the host), so the host resends the same packet (with the same PID), the data must be ignored, but an 'ACK' must be generated -- the USB controller just needs to keep the '`selected_i`' signal de-asserted, of the 'ep_bulk_out' module?

Invariants:

1. There is always at least '`MAX_LENGTH - level_o`' space; i.e., that available space is always exact, or pessimistic -- never optimistic?

### Bulk IN and OUT Testbench

Features:

0. Reset, then 'SET CONFIGURATION'.
1. Generate frames of random size, and send to EP IN.
2. EP IN chunks-up the frame (if required) and sends the stream of packets to EP OUT.
3. EP OUT re-assembles the packets into a frame, and emits it.
4. Testbench controller verifies that the frame is correct.
