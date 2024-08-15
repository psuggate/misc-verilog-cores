#include "ulpi.h"

#include <assert.h>
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


static const char type_strings[18][16] = {
    {"XferIdle"},
    {"NOPID"},
    {"RegWrite"},
    {"RegRead"},
    {"SETUP"},
    {"OUT"},
    {"IN"},
    {"SOF"},
    {"PING"},
    {"DnDATA0"},
    {"DnDATA1"},
    {"DnACK"},
    {"UpACK"},
    {"UpNYET"},
    {"UpNAK"},
    {"UpSTALL"},
    {"UpDATA0"},
    {"UpDATA1"}
};

static const char stage_strings[19][16] = {
    {"NoXfer"},
    {"AssertDir"},
    {"InitRXCMD"},
    {"TokenPID"},
    {"Token1"},
    {"Token2"},
    {"HskPID"},
    {"HskStop"},
    {"DATAxPID"},
    {"DATAxBody"},
    {"DATAxCRC1"},
    {"DATAxCRC2"},
    {"DATAxStop"},
    {"EndRXCMD"},
    {"EOP"},
    {"REGW"},
    {"REGR"},
    {"REGD"},
    {"LineIdle"},
};


static int drive_eop(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out);


//
//  Helper Routines
///

char* transfer_string(const transfer_t* xfer)
{
    static char str[256];
    const uint16_t tok = ((uint16_t)xfer->tok2 << 8) | xfer->tok1;
    const uint16_t crc = ((uint16_t)xfer->crc2 << 8) | xfer->crc1;
    uint16_t seq_val = 0;
    char seq_str[7] = {0};

    for (int i=0; i<16; i++) {
        if (xfer->ep_seq[i] == 0) {
            continue;
        } else if (xfer->ep_seq[i] > 1) {
            printf("\n[%s:%d] YUCKY seq[%d] = 0x%x\n\n", __FILE__, __LINE__, i, xfer->ep_seq[i]);
            seq_str[0] = '0';
            seq_str[1] = 'x';
            seq_str[2] = 'X';
            seq_str[3] = 'X';
            seq_str[4] = 'X';
            seq_str[5] = 'X';
            break;
        }
        seq_val |= (1 << i);
    }
    if (seq_str[0] == '\0') {
        sprintf(seq_str, "0x%04x", seq_val);
    }

    sprintf(str, "addr: %u, ep: %u, type: %d (%s), stage: %d (%s), ep_seq: %s, "
            "cycle: %u, tx: <%p>, tx_len: %d, tx_ptr: %d, rx: <%p>, rx_len: %d, "
            "rx_ptr: %d, tok: 0x%04x, crc: 0x%04x",
            xfer->address, xfer->endpoint, xfer->type, type_strings[xfer->type],
            xfer->stage, stage_strings[xfer->stage], seq_str, xfer->cycle,
            xfer->tx, xfer->tx_len, xfer->tx_ptr, xfer->rx, xfer->rx_len,
            xfer->rx_ptr, tok, crc
        );

    return str;
}

void transfer_show(const transfer_t* xfer)
{
    printf("Transfer = {\n  %s\n};\n", transfer_string(xfer));
}

char* ulpi_bus_string(const ulpi_bus_t* bus)
{
    static char str[256];
    unsigned int dat = bus->data.b << 8 | bus->data.a;
    sprintf(str, "clock: %u, rst#: %u, dir: %u, nxt: %u, stp: %u, data: 0x%x",
            bus->clock, bus->rst_n, bus->dir, bus->nxt, bus->stp, dat);
    return str;
}

void ulpi_bus_show(const ulpi_bus_t* bus)
{
    printf("%s\n", ulpi_bus_string(bus));
    // unsigned int dat = bus->data.b << 8 | bus->data.a;
    // printf("clock: %u, rst#: %u, dir: %u, nxt: %u, stp: %u, data: 0x%x\n",
    //        bus->clock, bus->rst_n, bus->dir, bus->nxt, bus->stp, dat);
}

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
//  Transaction Step-Functions
///

/**
 * Evaluates step-functions for both a USB host, and a USB "function" (device),
 * until completion.
 */
int ulpi_step_with(step_fn_t host_fn, transfer_t* xfer, ulpi_bus_t* bus,
                   user_fn_t user_fn, void* user_data)
{
    ulpi_bus_t out = {0};
    int result = 0;

    xfer->stage = 0;
    ulpi_bus_idle(bus);

    while (result == 0) {
        result = host_fn(xfer, bus, &out);
        memcpy(bus, &out, sizeof(ulpi_bus_t));
        if (result < 0) {
        // if (result != 0) {
            break;
        }

        result |= user_fn(user_data, bus, &out);
        // result = user_fn(user_data, bus, &out);
        memcpy(bus, &out, sizeof(ulpi_bus_t));

        // printf(".");
    }

    return result;
}

uint8_t transfer_type_to_pid(transfer_t* xfer)
{
    uint8_t pid;
    switch (xfer->type) {
    case SETUP:
        pid = USBPID_SETUP;
        break;
    case OUT:
        pid = USBPID_OUT;
        break;
    case IN:
        pid = USBPID_IN;
        break;
    case SOF:
        pid = USBPID_SOF;
        break;
    case PING:
        pid = USBPID_PING;
        break;
    case DnACK:
    case UpACK:
        pid = USBPID_ACK;
        break;
    case UpNAK:
        pid = USBPID_NAK;
        break;
    case UpNYET:
        pid = USBPID_NYET;
        break;
    case UpSTALL:
        pid = USBPID_STALL;
        break;
    case DnDATA0:
    case UpDATA0:
        pid = USBPID_DATA0;
        break;
    case DnDATA1:
    case UpDATA1:
        pid = USBPID_DATA1;
        break;
    default:
        printf("[%s:%d] Invalid transfer type\n", __FILE__, __LINE__);
        return 255;
    }
    if (xfer->type < UpACK) {
        // Host to device encoding
        pid |= (pid << 4) ^ 0xF0;
    } else {
        // ULPI PHY transmit-encoding
        pid |= 0x10;
    }
    return pid;
}

int token_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (xfer->stage > NoXfer && xfer->stage < LineIdle && in->dir != SIG1) {
        printf(
            "[%s:%d] Invalid ULPI bus signal levels for token-transmission\n",
            __FILE__, __LINE__);
        return -1;
    }

    switch (xfer->type) {

    case SETUP:
    case OUT:
    case IN:
    case SOF:
        memcpy(out, in, sizeof(ulpi_bus_t));
        switch (xfer->stage) {

        case NoXfer:
            out->dir = SIG1;
            out->nxt = SIG1;
            out->data.a = 0x00;
            out->data.b = 0xFF;
            xfer->stage = AssertDir;
            break;

        case AssertDir:
            out->nxt = SIG0;
            out->data.a = 0x5D;
            out->data.b = 0x00;
            xfer->stage = InitRXCMD;
            break;

        case InitRXCMD:
            // Now output the PID byte, for the SOF
            out->dir = SIG1;
            out->nxt = SIG1;
            out->data.a = transfer_type_to_pid(xfer);
            xfer->stage = TokenPID;
            break;

        case TokenPID:
            out->nxt = SIG1;
            out->data.a = xfer->tok1;
            out->data.b = 0x00;
            xfer->stage = Token1;
            break;

        case Token1:
            assert(out->dir == SIG1 && out->nxt == SIG1 && out->data.b == 0x00);
            out->data.a = xfer->tok2;
            xfer->stage = Token2;
            break;

	default:
	    return drive_eop(xfer, in, out);
        }
        break;

    default:
        printf("[%s:%d] Not a TOKEN: %u\n", __FILE__, __LINE__, xfer->type);
        return -1;
    }

    return 0;
}

int datax_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    uint8_t pid = xfer->type == DnDATA0 ? 0xC3 : 0x4B;

    if (!check_seq(xfer, pid & 0x0f)) {
        printf("[%s:%d] Invalid send DATAx operation: %u\n", __FILE__, __LINE__, pid);
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
                printf(
                    "[%s:%d] ULPI bus not idle (data = %x, stp = %u) cannot send DATAx\n",
                    __FILE__, __LINE__,
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
                out->data.a = xfer->crc1;
                xfer->stage = DATAxCRC1;
            }
            break;

        case DATAxCRC1:
            out->nxt = SIG1;
            out->data.a = xfer->crc2;
            out->data.b = 0x00;
            xfer->stage = DATAxCRC2;
            break;

	default:
	    return drive_eop(xfer, in, out);
        }
        break;
    default:
        printf("[%s:%d] Not a DATAx packet: %u\n", __FILE__, __LINE__, xfer->type);
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
                printf("[%s:%d] Invalid PID value\n", __FILE__, __LINE__);
                return -1;
            }
            xfer->stage = DATAxBody;
            xfer->rx_ptr = 0;
            break;

        case DATAxBody:
	    assert(in->dir == SIG0);
            if (in->nxt == SIG1) {
		// Todo: check CRC
                xfer->rx[xfer->rx_ptr++] = in->data.a;
            }
            if (in->stp == SIG1) {
		// Turn around the ULPI bus, so that we can send an RX CMD
		out->dir = SIG1;
                out->nxt = SIG0;
		out->data.a = 0x00;
		out->data.b = 0xFF;
                xfer->stage = DATAxStop;
                xfer->rx_len = xfer->rx_ptr - 2;
            }
            break;

	default:
	    return drive_eop(xfer, in, out);
        }
        break;
    default:
        printf("[%s:%d] Not a DATAx packet: %u\n", __FILE__, __LINE__, xfer->type);
        return -1;
    }

    return 0;
}

static int drive_eop(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (xfer->stage) {

    case Token2:
    case DATAxCRC2:
	assert(in->dir == SIG1 && in->nxt == SIG1 && in->data.b == 0x00);
	out->nxt = SIG0;
	out->data.a = 0x5D; // RX CMD: RxActive = 1
	xfer->stage = DATAxStop;
	break;

    case DATAxStop:
	assert(in->dir == SIG1 && in->nxt == SIG0);
	out->data.a = 0x4C;
	out->data.b = 0x00;
	xfer->stage = EndRXCMD;
	break;

    case EndRXCMD:
	assert(out->dir == SIG1 && out->nxt == SIG0 && out->data.b == 0x00);
	out->data.a = 0x4D;
	xfer->stage = EOP;
	break;

    case EOP:
	assert(out->dir == SIG1 && out->nxt == SIG0 && out->data.b == 0x00);
	out->dir = SIG0;
	out->data.a = 0x00;
	out->data.b = 0xFF;
	xfer->stage = LineIdle;
	break;

    case LineIdle:
	assert(in->dir == SIG0 && in->nxt == SIG0 && in->data.a == 0x00);
	xfer->type = XferIdle;
	xfer->stage = NoXfer;
	return 1;

    default:
	printf("[%s:%d] Not a valid EOP stage: %u (%s)\n", __FILE__, __LINE__,
	       xfer->stage, stage_strings[xfer->stage]);
	return -1;
    }

    return 0;
}

int ack_recv_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    return -1;
}

int ack_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    return -1;
}
