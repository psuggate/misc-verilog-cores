# README for the MSC Core

This USB Mass Storage Class (MSC) logic core implements Bulk-Only Transport (BOT), presenting this interface via USB standard descriptors.

## TODO

Logical units:

+ LBA to AXI4 mapper.
+ AXI4 transaction-splitter, for transactions that span 4kB boundaries^[Required by the AXI4 protocol.].
+ SCSI Block Command (SBC) parser.
+ SCSI SENSE response assembler/generator.
+ Data-In buffer.
+ Data-Out buffer.

Bulk-Only Transport:

+ Top-level module.
+ Multiplexors for commands, data (-in/-out), and responses.
+ Transaction-tag handling.
+ Residue calculator.

Control pipe:

+ Bulk-Only Mass Storage Reset (BOMSR).
+ Get max. LUN.
+ USB descriptors.

## Notes

Each LUN must be a contiguous set of blocks, with zero as the first block of the sequence.
