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
+ Correct responses for illegal and unsupported command blocks.

Control pipe:

+ Bulk-Only Mass Storage Reset (BOMSR).
+ Get max. LUN.
+ USB descriptors.
+ Clear Feature HALT (for Bulk-In, and Bulk-Out, pp.16, `usbmassbulk_10.pdf`).

## Notes

Each LUN must be a contiguous set of blocks, with zero as the first block of the sequence.

\clearpage

# Appendix: Mass Storage Class

```
Bus 003 Device 020: ID 13fe:3600 Phison Electronics Corp. flash drive (4GB, EMTEC)
Couldn't open device, some information will be missing
Negotiated speed: High Speed (480Mbps)
Device Descriptor:
  bLength                18
  bDescriptorType         1
  bcdUSB               2.00
  bDeviceClass            0 [unknown]
  bDeviceSubClass         0 [unknown]
  bDeviceProtocol         0 
  bMaxPacketSize0        64
  idVendor           0x13fe Phison Electronics Corp.
  idProduct          0x3600 flash drive (4GB, EMTEC)
  bcdDevice            1.00
  iManufacturer           1
  iProduct                2 USB DISK 2.0
  iSerial                 3 07B40808943D76C5
  bNumConfigurations      1
  Configuration Descriptor:
    bLength                 9
    bDescriptorType         2
    wTotalLength       0x0020
    bNumInterfaces          1
    bConfigurationValue     1
    iConfiguration          0 
    bmAttributes         0x80
      (Bus Powered)
    MaxPower              200mA
    Interface Descriptor:
      bLength                 9
      bDescriptorType         4
      bInterfaceNumber        0
      bAlternateSetting       0
      bNumEndpoints           2
      bInterfaceClass         8 Mass Storage
      bInterfaceSubClass      6 SCSI
      bInterfaceProtocol     80 Bulk-Only
      iInterface              0 
      Endpoint Descriptor:
        bLength                 7
        bDescriptorType         5
        bEndpointAddress     0x81  EP 1 IN
        bmAttributes            2
          Transfer Type            Bulk
          Synch Type               None
          Usage Type               Data
        wMaxPacketSize     0x0200  1x 512 bytes
        bInterval               0
      Endpoint Descriptor:
        bLength                 7
        bDescriptorType         5
        bEndpointAddress     0x02  EP 2 OUT
        bmAttributes            2
          Transfer Type            Bulk
          Synch Type               None
          Usage Type               Data
        wMaxPacketSize     0x0200  1x 512 bytes
        bInterval               0
```
