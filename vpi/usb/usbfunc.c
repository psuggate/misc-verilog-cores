#include "usbfunc.h"
#include <stdio.h>
#include <string.h>


static int fn_token_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_datax_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_datax_send_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_packet_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);


/**
 * Issue a device reset.
 */
void usbf_init(usb_func_t* func)
{
    func->cycle = 0ul;
    func->op = HostReset;
    func->step = 0u;
    func->turnaround = 0;
    func->addr = 0;
}


static int fn_token_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG1) {
	printf("Unexpected early termination of packet-receive\n");
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case AssertDir:
	// If 'NXT' is asserted, then we are receiving a packet, else invalid
	// ULPI bus signals
	if (in->nxt == SIG1) {
	    func->xfer.stage = InitRXCMD;
	    return 0;
	}
	break;

    case InitRXCMD:
	if (in->nxt == SIG1 && check_pid(in)) {
	    switch (in->data.a & 0x0f) {
	    case USBPID_OUT:
	    case USBPID_IN:
	    case USBPID_SETUP:
	    case USBPID_SOF:
		func->xfer.stage = TokenPID;
		return 0;
	    default:
		printf("Token PID expected\n");
		break;
	    }
	}
	break;

    case TokenPID:
	if (in->nxt == SIG1 && in->data.b == 0x00) {
	    func->xfer.tok1 = in->data.a;
	    func->xfer.stage = Token1;
	    return 0;
	} else if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
	    // Wait-state
	    return 0;
	}
	break;

    case Token1:
	if (in->nxt == SIG1 && in->data.b == 0x00) {
	    func->xfer.tok2 = in->data.a;
	    func->xfer.stage = Token2;
	    return 0;
	} else if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
	    // Wait-state
	    return 0;
	}
	break;

    case Token2:
	if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) != RX_ACTIVE_BITS) {
	    // EOP
	    func->xfer.stage = EndRXCMD;
	    return 0;
	}
	break;

    case EndRXCMD:
    case EOP:
	if (in->nxt == SIG0) {
	    return 0;
	}
	break;

    default:
	break;
    }

    return -1;
}

static int fn_datax_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG1) {
	printf("Unexpected early termination of packet-receive\n");
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case AssertDir:
	// If 'NXT' is asserted, then we are receiving a packet, else invalid
	// ULPI bus signals
	if (in->nxt == SIG1) {
	    func->xfer.stage = InitRXCMD;
	    return 0;
	}
	break;

    case InitRXCMD:
	if (in->nxt == SIG1 && check_pid(in)) {
	    if (check_seq(&func->xfer, in->data.a & 0x0f)) {
		func->xfer.stage = DATAxPID;
		func->xfer.rx_ptr = 0;
		func->xfer.rx_len = 0;
		return 0;
	    }
	}
	printf("DATAx PID expected\n");
	break;

    case DATAxPID:
    case DATAxBody:
	if (in->nxt == SIG1) {
	    func->xfer.rx[func->xfer.rx_ptr++] = in->data.a;
	    return 0;
	} else if (in->nxt == SIG0) {
	    // If 'NXT' deasserts, could be a wait-state, or end-of-packet
	    if (in->data.a & RX_EVENT_MASK != RX_ACTIVE_BITS) {
		// Todo: End-of-Packet, so check CRC16
		func->xfer.stage = EndRXCMD;
		func->xfer.rx_len = func->xfer.rx_ptr - 2;
	    }
	    return 0;
	}
	printf("Receiving DATAx packet failed\n");
	break;

    case EndRXCMD:
    case EOP:
	func->xfer.type = UpACK;
	return 0;

    default:
	printf("Unexpected DATAx receive-step\n");
	break;
    }

    return -1;
}

static int fn_datax_send_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG0) {
	printf("Packet transmission interrupted\n");
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case NoXfer: {
	// Drive ULPI 'Transmit' onto bus
	uint8_t pid = func->xfer.ep_seq[func->xfer.endpoint] == 0 ? ULPITX_DATA0 : ULPITX_DATA1;
	out->data.a = pid;
	out->data.b = 0x00;
	out->stp = SIG0;
	func->xfer.stage = DATAxPID;
	return 0;
    }

    case DATAxPID:
	if (in->nxt == SIG1) {
	    if (func->xfer.tx_len > 0) {
		out->data.a = func->xfer.tx[func->xfer.tx_ptr++];
		out->data.b = 0x00;
		out->stp = SIG0;
		func->xfer.stage = DATAxBody;
	    } else {
		// Send a ZDP:
		out->data.a = func->xfer.crc1;
		out->data.b = 0x00;
		out->stp = SIG0;
		func->xfer.stage = DATAxCRC1;
	    }
	}
	return 0;

    case DATAxBody:
	if (in->nxt == SIG1) {
	    if (func->xfer.tx_ptr < func->xfer.tx_len) {
		out->data.a = func->xfer.tx[func->xfer.tx_ptr++];
		out->data.b = 0x00;
		out->stp = SIG0;
	    } else {
		out->data.a = func->xfer.crc1;
		out->data.b = 0x00;
		out->stp = SIG0;
		func->xfer.stage = DATAxCRC1;
	    }
	}
	return 0;

    case DATAxCRC1:
	if (in->nxt == SIG1) {
	    out->data.a = func->xfer.crc2;
	    out->data.b = 0x00;
	    out->stp = SIG1;
	    func->xfer.stage = DATAxCRC2;
	}
	return 0;

    case DATAxCRC2:
	// After 2nd CRC byte has been transferred, set the ULPI bus to idle
	if (in->nxt == SIG1) {
	    out->data.a = 0x00;
	    out->data.b = 0x00;
	    out->stp = SIG0;
	    func->xfer.stage = EOP;
	}
	return 0;

    case EOP:
	out->data.a = 0x00;
	out->data.b = 0x00;
	out->stp = SIG0;
	return 0;

    default:
	break;
    }

    return -1;
}

static int fn_packet_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG0) {
	printf("Handshake transmission interrupted\n");
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case NoXfer:
	// Drive ULPI 'Transmit' onto bus, with 'ACK' PID
	out->data.a = ULPITX_ACK;
	out->data.b = 0x00;
	out->stp = SIG0;
	func->xfer.stage = HskPID;
	return 0;

    case HskPID:
	// Once the PID has been accepted, assert 'STP'
	if (in->nxt == SIG1) {
	    out->data.a = 0x00;
	    out->data.b = 0x00;
	    out->stp = SIG1;
	    func->xfer.stage = HskStop;
	}
	return 0;

    case HskStop:
	// Return ULPI bus to idle
	out->data.a = 0x00;
	out->data.b = 0x00;
	out->stp = SIG0;
	func->xfer.stage = EOP;
	return 0;

    case EOP:
	// Done
	out->data.a = 0x00;
	out->data.b = 0x00;
	out->stp = SIG0;
	return 0;

    default:
	break;
    }
	
    return -1;
}

static int stdreq_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    return -1;
}

static int func_xfer_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (func->op) {
    case HostBulkOUT:
	
	break;
    case HostBulkIN:
	break;
    case HostSETUP:
	break;
    case HostSOF:
	break;
    default:
	return -1;
    }

    switch (func->xfer.type) {
    case XferIdle:
	// If 'DIR' asserts then we are waiting for a token.
	if (func->xfer.stage == NoXfer && ulpi_bus_is_idle(in)) {
	    return 0;
	} else if (in->dir == SIG1) {
	    if (in->nxt == SIG1) {
		func->xfer.stage = AssertDir;
	    } else if (in->nxt == SIG0) {
		func->state = FuncRXCMD;
	    } else {
		break;
	    }
	    func->step = 0u;
	    return 0;
	}
	break;

    case AssertDir:
	// We are expecting an RX CMD followed by a USB token
	if (in->dir == SIG1 && in->nxt == SIG0 && in->data.b == 0x00 &&
	    (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
	    func->state = FuncRxPID;
	    return 0;
	}
	break;

    case IN:
	break;

    case OUT:
	break;

    case SETUP:
	break;

    case SOF:
	break;

    default:
	break;
    }

    return -1;
}

int usbf_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (func->state) {
    case FuncIdle:
	// If 'DIR' asserts then we are waiting for a token.
	if (ulpi_bus_is_idle(in)) {
	    return 0;
	} else if (in->dir == SIG1) {
	    if (in->nxt == SIG1) {
		func->state = FuncRecv;
	    } else if (in->nxt == SIG0) {
		func->state = FuncRXCMD;
	    } else {
		break;
	    }
	    func->step = 0u;
	    return 0;
	}
	break;

    case FuncRecv:
	// We are expecting an RX CMD followed by a USB token
	if (in->dir == SIG1 && in->nxt == SIG0 && in->data.b == 0x00 &&
	    (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
	    func->state = FuncRxPID;
	    return 0;
	}
	break;

    case FuncRXCMD:
	if (in->dir == SIG1) {
	    if (in->nxt == SIG0) {
		// Stay in 'FuncRXCMD' until 'DIR' deasserts
		return 0;
	    }
	} else if (in->dir == SIG0) {
	    func->state = FuncIdle;
	    return 0;
	}
	break;

    case FuncRxPID:
	// When 'NXT' asserts, we have received a USB PID for the packet
	if (in->dir == SIG1) {
	    if (in->nxt == SIG1 && check_pid(in)) {
		func->state = FuncBusy;
		func->xfer.stage = Token1;
		func->xfer.tx_len = 0;
		func->xfer.tx_ptr = 0;
		func->xfer.rx_len = 0;
		func->xfer.rx_ptr = 0;

		switch (in->data.a & 0x0f) {
		case USBPID_OUT:
		    func->op = HostBulkOUT;
		    func->xfer.type = OUT;
		    break;

		case USBPID_IN:
		    func->op = HostBulkIN;
		    func->xfer.type = IN;
		    break;

		case USBPID_SETUP:
		    func->op = HostSETUP;
		    func->xfer.type = SETUP;
		    break;

		case USBPID_SOF:
		    func->op = HostSOF;
		    func->xfer.type = SOF;
		    break;

		default:
		    printf("Expecting token\n");
		    return -1;
		}

		return 0;
	    } else if (in->nxt == SIG0) {
		// Just another RX CMD
		// Todo: check if 'RxActive == 1'
		return 0;
	    }
	}
	break;

    case FuncBusy:
	return func_xfer_step(func, in, out);

    case FuncEOT:
	// Todo: stuff
	return 1;

    default:
	break;
    }

    return -1;
}
