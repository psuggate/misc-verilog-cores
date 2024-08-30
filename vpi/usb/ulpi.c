#include "ulpi.h"
#include "usbcrc.h"

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


static const char type_strings[19][16] = {
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
    {"UpDATA1"},
    {"TimeOut"}
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


//
//  Helper Routines
///

const char* transfer_type_string(const transfer_t* xfer)
{
    return type_strings[xfer->type];
}

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
 * Acknowledge a DATAx transfer, by toggling its sequence bit.
 */
void transfer_ack(transfer_t* xfer)
{
    uint8_t ep = xfer->endpoint;

    if (xfer->ep_seq[ep] == SIG0) {
        xfer->ep_seq[ep] = SIG1;
    } else {
        xfer->ep_seq[ep] = SIG0;
    }
}

void transfer_tok(transfer_t* xfer)
{
    uint16_t ad = (uint16_t)(xfer->address & 0x7F);
    uint16_t ep = (uint16_t)(xfer->endpoint & 0x0F) << 7;
    uint16_t tok = crc5_calc(ad | ep);
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = tok >> 8;
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

int check_rx_crc16(transfer_t* xfer)
{
    int len = xfer->rx_len;
    if (len > 0) {
        uint16_t crc = crc16_calc(xfer->rx, len);
        uint16_t cod = crc16_calc(xfer->rx, xfer->rx_ptr);
        xfer->crc1 = crc & 0xFF;
        xfer->crc2 = (crc >> 8) & 0xFF;
        printf("[%s:%d] CRC16: 0x%04X (check code: 0x%04X, length: %d)\n",
               __FILE__, __LINE__, crc, cod, len);
        return xfer->crc1 == xfer->rx[len] && xfer->crc2 == xfer->rx[len+1] && cod == 0x4FFE;
    } else {
        return xfer->rx[0] == 0x00 && xfer->rx[1] == 0x00;
    }
}

int drive_eop(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (xfer->stage) {

    case XferIdle:
        return 1;

    case Token2:
    case DATAxCRC2:
    case HskPID:
        assert(in->dir == SIG1 && in->nxt == SIG1 && in->data.b == 0x00);
        out->nxt = SIG0;
        out->data.a = 0x4C; // RX CMD: RxActive = 0
        xfer->stage = EndRXCMD;
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
        printf("[%s:%d] Invalid send DATAx parity: 0x%02x\n", __FILE__, __LINE__, pid);
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
            assert(in->dir == SIG0 && in->nxt == SIG1 && in->data.b == 0x00);
            out->nxt = SIG0;
            xfer->stage = DATAxBody;
            xfer->rx_ptr = 0;
            if (in->data.a != ULPITX_DATA0 && in->data.a != ULPITX_DATA1) {
                printf("[%s:%d] Invalid PID value: 0x%02x\n",
                       __FILE__, __LINE__, in->data.a);
                return -2;
            } else if (!check_seq(xfer, in->data.a & 0x0F)) {
                printf("[%s:%d] Invalid PID DATAx sequence bit: 0x%02x\n",
                       __FILE__, __LINE__, in->data.a);
                return -3;
            }
            break;

        case DATAxBody:
            assert(in->dir == SIG0 && in->data.b == 0x00);
            if (in->stp == SIG1) {
                // Turn around the ULPI bus, so that we can send an RX CMD
                // Todo: check CRC
                out->dir = SIG1;
                out->nxt = SIG0;
                out->data.a = 0x00;
                out->data.b = 0xFF;
                xfer->stage = DATAxStop;
                xfer->rx_len = xfer->rx_ptr - 2;
                if (check_rx_crc16(xfer) < 1) {
                    return -1;
                }
            } else if (in->nxt == SIG1) {
                xfer->rx[xfer->rx_ptr++] = in->data.a;
            } else {
                out->nxt = SIG1;
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

/**
 * From the point-of-view of a ULPI PHY, receive a handshake packet from a link,
 * and then transmit this over the USB.
 */
int ack_recv_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (xfer->type != UpACK) {
        transfer_show(xfer);
        printf("[%s:%d] Not an upstream 'ACK' transfer: %d (%s)\n", __FILE__,
               __LINE__, xfer->type, type_strings[xfer->type]);
        return -1;
    }

    switch (xfer->stage) {

    case NoXfer:
        if (!ulpi_bus_is_idle(in)) {
            switch (in->data.a) {
            case ULPITX_ACK:
                printf("[%s:%d] ACK received\n", __FILE__, __LINE__);
                out->nxt = SIG1;
                xfer->stage = HskPID;
                transfer_ack(xfer);
                break;
            default:
                printf("[%s:%d] Unexpected TX CMD: 0x%02x\n",
                       __FILE__, __LINE__, in->data.a);
                return -1;
            }
        }
        break;

    case HskPID:
        assert(in->dir == SIG0 && in->data.b == 0x00);
        out->nxt = SIG0;
        if (in->stp == SIG1) {
            xfer->stage = HskStop;
        }
        break;

    case HskStop:
        // Todo: RX CMD !?
        assert(in->dir == SIG0 && in->nxt == SIG0 && in->stp == SIG0);
        xfer->stage = XferIdle;
        return 1;

    default:
        printf("[%s:%d] Unexpected ACK receive stage: %u (%s)\n",
               __FILE__, __LINE__, xfer->stage, stage_strings[xfer->stage]);
        return -1;
    }

    return 0;
}

/**
 * From the point-of-view of a ULPI PHY, send a handshake packet to a link, from
 * the USB.
 */
int ack_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (xfer->type != DnACK) {
        transfer_show(xfer);
        printf("[%s:%d] Not a downstream 'ACK' transfer: %d (%s)\n", __FILE__,
               __LINE__, xfer->type, type_strings[xfer->type]);
        return -1;
    }

    switch (xfer->stage) {

    case NoXfer:
        if (!ulpi_bus_is_idle(in)) {
            printf("[%s:%d] ULPI bus is busy, not ready to send 'ACK'\n",
                   __FILE__, __LINE__);
            return -1;
        }
        out->dir = SIG1;
        out->nxt = SIG1;
        out->data.a = 0x00;
        out->data.b = 0xFF;
        xfer->stage = AssertDir;
        break;

    case AssertDir:
        assert(in->dir == SIG1 && in->nxt == SIG1 && in->stp == SIG0);
        out->nxt = SIG0;
        out->data.a = 0x5D; // RX CMD: RxActive = 1
        out->data.b = 0x00;
        xfer->stage = InitRXCMD;
        break;

    case InitRXCMD:
        assert(in->dir == SIG1 && in->nxt == SIG0 && in->stp == SIG0 && in->data.b == 0x00);
        out->nxt = SIG1;
        out->data.a = transfer_type_to_pid(xfer);
        xfer->stage = HskPID;
        break;

    default:
        return drive_eop(xfer, in, out);
    }

    return 0;
}
