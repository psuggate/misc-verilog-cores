#include "ulpi.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

//
// Todo:
//  - HS negotiation (pp.39, ULPI_v1_1.pdf)
//  - Reset handling
//  - Suspend and Resume
//


#define ZDP_CRC16_BYTE1 0x00u
#define ZDP_CRC16_BYTE2 0x00u


// Initialisation/reset/default values for the ULPI PHY registers.
static const uint8_t ULPI_REG_DEFAULTS[10] = {
    0x24, 0x04, 0x06, 0x00, 0x41, 0x41, 0x41, 0x00, 0x00, 0x00
};


// Todo ...
ulpi_phy_t* phy_init(void)
{
    ulpi_phy_t* phy = (ulpi_phy_t*)malloc(sizeof(ulpi_phy_t));

    memcpy(phy->state.regs, ULPI_REG_DEFAULTS, sizeof(ULPI_REG_DEFAULTS));

    phy->state.rx_cmd = 0x0C;
    phy->state.status = PowerOn;

    phy->bus.clock = SIGX;
    phy->bus.rst_n = SIGX;
    phy->bus.dir = SIGZ;
    phy->bus.nxt = SIGZ;
    phy->bus.stp = SIGX;
    phy->bus.data.a = 0x00;
    phy->bus.data.b = 0xff;

    return phy;
}

void phy_free(ulpi_phy_t* phy)
{
    free(phy);
}


//
//  Helper Routines
///

void ulpi_bus_idle(ulpi_bus_t* bus)
{
    bus->clock = SIG1;
    bus->rst_n = SIG1;
    bus->dir = SIG0;
    bus->nxt = SIG0;
    bus->stp = SIG0;
    bus->data.a = 0x00;
    bus->data.b = 0x00;
}

void transfer_out(transfer_t* xfer, uint8_t addr, uint8_t ep)
{
    xfer->address = addr;
    xfer->endpoint = ep;
    xfer->type = OUT;
    xfer->stage = 0;
    xfer->tx_len = 0;
    xfer->tx_ptr = 0;
}

void transfer_in(transfer_t* xfer, uint8_t addr, uint8_t ep)
{
    xfer->address = addr;
    xfer->endpoint = ep;
    xfer->type = IN;
    xfer->stage = 0;
    xfer->rx_len = 0;
    xfer->rx_ptr = 0;
}

/**
 * Sets up for the start of a new (micro-)frame, canceling any ongoing
 * transactions.
 */
void sof_frame(transfer_t* xfer, uint16_t frame)
{
    xfer->address = 0;
    xfer->endpoint = 0;
    xfer->type = SOF;
    xfer->stage = 0;
    xfer->cycle = 0;
    xfer->rx_len = 0;
    xfer->rx_ptr = 0;
    xfer->tx_len = 0;
    xfer->tx_ptr = 0;
}


//
//  Higher-Level Routines
///

/**
 * Todo:
 *  - on pp.22, USB3317C datasheet, register values for each mode;
 */
int phy_set_reg(uint8_t reg, uint8_t val)
{
    return -1;
}

int phy_get_reg(uint8_t reg, uint8_t* val)
{
    return -1;
}


//
//  Transaction Step-Functions
///

int token_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (xfer->type) {
    case SETUP:
    case OUT:
    case IN:
    case SOF:
	switch (xfer->stage) {
	case NoXfer: break;
	case AssertDir: break;
	case TokenPID: break;
	case Token1: break;
	case Token2: break;
	case EndRXCMD: return 1;
	case EOP: return 1;
	default:
	    printf("Not a valid TOKEN stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a TOKEN: %u\n", xfer->type);
	return -1;
    }

    xfer->stage++;
    return 0;
}

int datax_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    uint8_t pid = xfer->type == DnDATA0 ? 0xC3 : 0x4B;

    if (!check_seq(xfer, pid)) {
	printf("Invalid send DATAx operation: %u\n", pid);
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (xfer->type) {
    case DnDATA0:
    case DnDATA1:
	switch (xfer->stage) {
	case NoXfer:
	    // If ULPI bus is idle, grab it by asserting 'DIR'
	    if (in->data.a != 0x00 || in->stp != SIG0) {
		printf("ULPI bus not idle (data = %x, stp = %u) cannot send DATAx\n",
		       (unsigned)in->data.a << 8 | (unsigned)in->data.b, in->stp);
		return -1;
	    }
	    out->dir = SIG1;
	    out->nxt = SIG1;
	    out->data.a = 0x00;
	    out->data.b = 0xff;
	    xfer->stage = AssertDir;
	    break;

	case AssertDir:
	    // We have asserted 'DIR', now we drive an RX CMD
	    out->nxt = SIG0;
	    out->data.a = 0x5D; // RX CMD: RxActive = 1
	    out->data.b = 0x00;
	    xfer->stage = InitRXCMD;
	    break;

	case InitRXCMD:
	    // RX CMD was driven onto ULPI bus, now output PID
	    out->nxt = SIG1;
	    out->data.a = pid;
	    out->data.b = 0x00;
	    xfer->stage = DATAxPID;
	    break;

	case DATAxPID:
	    // PID driven onto ULPI bus, now send the DATA
	    out->nxt = SIG1;
	    out->data.b = 0x00;
	    if (xfer->tx_len > 0) {
		out->data.a = xfer->tx[xfer->tx_ptr++];
		xfer->stage = DATAxBody;
	    } else {
		out->data.a = ZDP_CRC16_BYTE1;
		xfer->stage = DATAxCRC1;
	    }
	    break;

	case DATAxBody:
	    // Keep driving data onto ULPI bus, then send the first CRC-byte
	    out->nxt = SIG1;
	    out->data.b = 0x00;
	    if (xfer->tx_ptr < xfer->tx_len) {
		out->data.a = xfer->tx[xfer->tx_ptr++];
		xfer->stage = DATAxBody;
	    } else {
		out->data.a = ZDP_CRC16_BYTE1; // Todo ...
		xfer->stage = DATAxCRC1;
	    }
	    break;

	case DATAxCRC1:
	    out->nxt = SIG1;
	    out->data.a = ZDP_CRC16_BYTE2; // Todo ...
	    out->data.b = 0x00;
	    xfer->stage = DATAxCRC2;
	    break;
	case DATAxCRC2:
	    out->nxt = SIG0;
	    out->data.a = 0x5C; // RX CMD: RxActive = 1
	    out->data.b = 0x00;
	    xfer->stage = EndRXCMD;
	    break;

	case EndRXCMD:
	    out->data.a = 0x4C; // RX CMD: RxActive = 0, LineState = 0
	    out->data.b = 0x00;
	    xfer->stage = EOP;
	    break;

	case EOP:
	    // End-of-Packet, so stop driving the ULPI bus
	    out->dir = SIG0;
	    out->data.a = 0x00;
	    out->data.b = 0xFF;
	    return 1;

	default:
	    printf("Not a valid DATAx stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a DATAx packet: %u\n", xfer->type);
	return -1;
    }

    return 0;
}

int datax_recv_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (xfer->type) {
    case UpDATA0:
    case UpDATA1:
	switch (xfer->stage) {
	case NoXfer:
	    out->dir = SIG0;
	    if (in->data.a != 0x00) {
		out->nxt = SIG1;
		xfer->stage = DATAxPID;
	    }
	    break;

	case DATAxPID:
	    if (!check_pid(in) || !check_seq(xfer, in->data.a & 0x0f)) {
		printf("Invalid PID value\n");
		return -1;
	    }
	    xfer->stage = DATAxBody;
	    xfer->rx_ptr = 0;
	    break;

	case DATAxBody:
	    if (in->nxt == SIG1) {
		xfer->rx[xfer->rx_ptr++] = in->data.a;
	    }
	    if (in->stp == SIG1) {
		out->nxt = SIG0;
		xfer->stage = DATAxStop;
		xfer->rx_len = xfer->rx_ptr - 2;
	    }
	    break;

	case DATAxStop:
	    // Todo: check CRC
	    xfer->stage = EndRXCMD;
	    break;

	case EndRXCMD:
	case EOP:
	    return 1;

	default:
	    printf("Not a valid DATAx stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a DATAx packet: %u\n", xfer->type);
	return -1;
    }

    return 0;
}
