#include "descriptor.h"
#include <stdio.h>


/**
 * Receive and assemble a USB descriptor, byte-by-byte.
 */
int desc_recv(transfer_t* xfer, const ulpi_bus_t* in)
{
    if (xfer->type < UpDATA0 || in->dir != SIG0 || in->nxt > SIG1 || in->stp > SIG1) {
	printf("ERROR: Bus not in recieve-mode\n");
	return -1;
    } else if (in->nxt != SIG1) {
	// Wait-state ignore
	printf(".");
	return 0;
    }

    switch ((xfer_stage_t)xfer->stage) {
    case DATAxPID:
	if (!check_pid(in) || !check_seq(xfer, in->data.a & 0x0f, 0)) {
	    printf("Invalid PID value\n");
	    return -1;
	}
	xfer->stage = DATAxBody;
	xfer->rx_ptr = 0;
	break;

    case DATAxBody:
    case DATAxCRC1:
    case DATAxCRC2:
	if (in->nxt == SIG1) {
	    xfer->rx[xfer->rx_ptr++] = in->data.a;
	}
	if (in->stp == SIG1) {
	    xfer->stage = DATAxStop;
	    xfer->rx_len = xfer->rx_ptr - 2;
	    return 1;
	}
	break;

    case DATAxStop:
	if (in->nxt != SIG0) {
	    printf("Unexpected assertion of STP\n");
	    return -1;
	}
	xfer->stage = EndRXCMD;
	return 1;

    case EndRXCMD:
    case EOP:
	printf("WARN: transfer has already finished\n");
	return 1;

    default:
	printf("Unexpected command-stage: %u\n", xfer->stage);
	return -1;
    }

    return 0;
}


void test_desc_recv(void)
{
    transfer_t xfer = {0};
    ulpi_bus_t bus = {0};
    int result = 0;
    uint16_t index = 0;
    uint16_t length = 20;
    uint8_t packet[68] = {
	0x12, 0x01, 0x00, 0x02, 0xFF, 0x00, 0x00, 0x40,
	0xCE, 0xF4, 0x03, 0x00, 0x00, 0x00, 0x01, 0x02,
	0x03, 0x01, 0x21, 0xDD,
    };

    // receive a DATA0 packet, upto 64 bytes in size
    bus.clock = SIG1;
    bus.rst_n = SIG1;
    bus.nxt = SIG1;
    bus.data.a = (~USBPID_DATA0 << 4) | USBPID_DATA0;
    xfer.type = UpDATA0;
    xfer.stage = DATAxPID;
    xfer.rx_len = 64;
    printf("DIR = %u, STP = %u, DATA.B = %u\n", bus.dir, bus.stp, bus.data.b);

    printf("Testing 'GET DESCRIPTOR'");
    do {
	result = desc_recv(&xfer, &bus);

	if (xfer.stage == DATAxBody) {
	    printf(".");
	    bus.data.a = packet[index++];
	    if (index >= length) {
		bus.stp = SIG1;
	    }
	} else {
	    bus.stp = SIG0;
	}
    } while (result == 0);

    if (result < 0) {
	printf("\t\tERROR\n");
    } else if (result > 0) {
	printf("\t\tSUCCESS\n");
    } else {
	printf("\t\tHAIL SEITAN\n");
    }
}
