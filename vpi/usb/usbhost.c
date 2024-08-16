/**
 * Simulates a USB host controller, by handling USB transactions.
 * NOTE:
 *  - not cycle-accurate, as it works at the packet-level of abstraction;
 *  - to generate SOF's and EOF's, needs additional structure;
 */
#include "usbhost.h"
#include "stdreq.h"
#include "usbcrc.h"

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>


// #define __short_timers
#ifdef  __short_timers

#define RESET_TICKS        60
#define SOF_N_TICKS        75

#else   /* !__short_timers */
#ifdef  __long_timers

#define RESET_TICKS     60000
#define SOF_N_TICKS      7500

#else   /* !__long_timers */

#define RESET_TICKS        60
#define SOF_N_TICKS       750

#endif  /* !__long_timers */
#endif  /* !__short_timers */


#define HOST_BUF_LEN    16384u


static const char host_op_strings[9][16] = {
    {"HostError"},
    {"HostReset"},
    {"HostSuspend"},
    {"HostResume"},
    {"HostIdle"},
    {"HostSOF"},
    {"HostSETUP"},
    {"HostBulkOUT"},
    {"HostBulkIN"}
};


// Is the ULPI bus idle, and ready for the PHY to take control of?
static int is_ulpi_phy_idle(const ulpi_bus_t* in)
{
    return in->dir == SIG0 && in->nxt == SIG0 && in->data.a == 0x00;
}

// Is the PHY in bus-turnaround (link -> PHY)?
static int is_ulpi_phy_turn(const ulpi_bus_t* in)
{
    return in->dir == SIG1 && in->nxt == SIG1 && in->data.a == 0x00 && in->data.b == 0xff;
}

/**
 * Take ownership of the bus, terminating any existing transaction, and then
 * driving an RX CMD to the device.
 */
static int start_host_to_func(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (host->xfer.stage > AssertDir) {
        printf("\nHOST\t#%8lu cyc =>\tERROR, stage = %d\n", host->cycle, host->xfer.stage);
        return -1;
    } else if (host->xfer.stage == NoXfer && is_ulpi_phy_idle(in)) {
        // Happy path, Step I:
        out->dir = SIG1;
        out->nxt = SIG1;
        out->data.a = 0x00; // High-impedance
        out->data.b = 0xFF; // High-impedance
        host->xfer.stage = AssertDir;
    } else if (host->xfer.stage == AssertDir && is_ulpi_phy_turn(in)) {
        // Happy path, Step II:
        out->nxt = SIG0;
        out->data.a = 0x5D;
        out->data.b = 0x00;
        host->xfer.stage = InitRXCMD;
    } else {
        printf("\nHOST\t#%8lu cyc =>\tERROR, dir = %d, nxt = %d\n", host->cycle, in->dir, in->nxt);
        out->dir = SIGX;
        out->nxt = SIGX;
        out->data.a = 0xFF; // Todo: RX CMD
        out->data.b = 0xFF; // Todo: RX CMD
        return -1;
    }

    return 0;
}


/**
 * Perform a single-step of a USB Bulk OUT transaction.
 * A 'Bulk OUT' transaction consists of:
 *  - 'OUT' token, with addr & EP;
 *  - 'DATA0/1' packet (link -> device); and
 *  - 'ACK/NAK' handshake (device -> link).
 */
static int bulk_out_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    transfer_t* xfer = &host->xfer;
    int result;

    switch (xfer->type) {

    case OUT:
        result = token_send_step(xfer, in, out);
        if (result < 0) {
            return result;
        } else if (result > 0) {
            xfer->type = xfer->ep_seq[xfer->endpoint] == SIG0 ? DnDATA0 : DnDATA1;
            xfer->stage = NoXfer;
        }
        break;

    case DnDATA0:
    case DnDATA1:
        result = datax_send_step(xfer, in, out);
        if (result < 0) {
            return result;
        } else if (result > 0) {
            xfer->type = UpACK;
            xfer->stage = NoXfer;
        }
        break;

    case UpACK:
        result = ack_recv_step(xfer, in, out);
        if (result > 0) {
            transfer_ack(xfer);
            xfer->type = XferIdle;
            xfer->stage = NoXfer;
        }
        return result;

    default:
        printf("[%s:%d] Unexpected 'Bulk OUT' transfer-type: %u (%s)\n",
               __FILE__, __LINE__, xfer->type, transfer_type_string(xfer));
        ulpi_bus_show(in);
        return -1;
    }

    return 0;
}

/**
 * Issue a device reset (therefore, does not reset the global cycle-counter,
 * nor the SOF-counter).
 */
static void usbh_reset(usb_host_t* host)
{
    host->op = HostReset;
    host->step = 0u;
    host->turnaround = 0;
    host->addr = 0;
    host->error_count = 0;
    memset(&host->xfer, 0, sizeof(transfer_t));
}

/**
 * Global hard reset.
 */
void usbh_init(usb_host_t* host)
{
    // Todo ...
    if (host == NULL) {
        return;
    }
    usbh_reset(host);
    host->cycle = 0ul;
    host->sof = 0u;
    host->buf = (uint8_t*)malloc(HOST_BUF_LEN);
    host->len = HOST_BUF_LEN;
}

int host_string(usb_host_t* host, char* str, const int indent)
{
    static char sp[64] = {0};
    int idx = 0;
    assert(indent < 60);

    for (int i=0; i<indent; i++) {
        sp[i] = ' ';
    }

    idx += sprintf(&str[idx], "%scycle: %lu,\n", sp, host->cycle);
    idx += sprintf(&str[idx], "%sop: %d (%s),\n", sp, host->op, host_op_strings[host->op+1]);
    idx += sprintf(&str[idx], "%sstep: %u,\n", sp, host->step);
    idx += sprintf(&str[idx], "%sprev: {\n%s  %s\n%s},\n", sp, sp, ulpi_bus_string(&host->prev), sp);
    idx += sprintf(&str[idx], "%sxfer: {\n%s  %s\n%s},\n", sp, sp, transfer_string(&host->xfer), sp);
    idx += sprintf(&str[idx], "%ssof: 0x%x (%u),\n", sp, host->sof, host->sof);
    idx += sprintf(&str[idx], "%stimer: %d,\n", sp, host->turnaround);
    idx += sprintf(&str[idx], "%saddr: 0x%02x,\n", sp, host->addr);
    idx += sprintf(&str[idx], "%serror_count: %d,\n", sp, host->error_count);
    idx += sprintf(&str[idx], "%sbuf[%u]: <%p>\n", sp, host->len, host->buf);

    return idx;
}

void show_host(usb_host_t* host)
{
    char* str = malloc(4096);
    int len = host_string(host, str, 2);
    assert(len < 4096);
    printf("USB_HOST = {\n%s};\n", str);
    free(str);
}

int usbh_busy(usb_host_t* host)
{
    return host->op != HostIdle;
}

/*
int usbh_send(usb_host_t* host, usb_xact_t* xact)
{
    return -1;
}
*/


/**
 * Queue-up a device reset, to be issued.
 */
int usbh_reset_device(usb_host_t* host, uint8_t addr)
{
    return -1;
}

int usbh_bulk_out(usb_host_t* host, uint8_t* data, uint16_t len)
{
    return -1;
}

int usbh_bulk_in(usb_host_t* host, uint8_t* data, uint16_t* len)
{
    return -1;
}

/**
 * Given the current USB host-state, and bus values, compute the next state and
 * bus values.
 */
int usbh_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;
    uint64_t cycle = host->cycle++;

    memcpy(out, in, sizeof(ulpi_bus_t));

    //
    // Todo:
    //  1. handle
    //
    if (in->rst_n == SIG0) {
        if (host->prev.rst_n != SIG0) {
            printf("\nHOST\t#%8lu cyc =>\tReset issued [%s:%d]\n", cycle, __FILE__, __LINE__);
            usbh_reset(host);
        }
        out->dir = SIG0;
        out->nxt = SIG0;
    } else if ((cycle % SOF_N_TICKS) == 0ul) {
        if (host->op > HostIdle) {
            printf("\nHOST\t#%8lu cyc =>\tTransaction cancelled for SOF [%s:%d]\n",
                   cycle, __FILE__, __LINE__);
        } else if (host->op < HostIdle) {
            // Ignore SOF
        } else {
            const uint16_t sof = (host->sof++) >> 3;
            const uint16_t crc = crc5_calc(sof);
            host->op = HostSOF;
            host->step = 0u;
            host->xfer.type = SOF;
            host->xfer.tok1 = crc & 0xFF;
            host->xfer.tok2 = (crc >> 8) & 0xFF;
            printf("\nHOST\t#%8lu cyc =>\tSOF [%s:%d]\n", cycle, __FILE__, __LINE__);
        }
    }

    switch (host->op) {

    case HostError:
        host->step++;
        break;

    case HostReset: {
        uint32_t step = ++host->step;
        if (step < 2) {
            printf("\nHOST\t#%8lu cyc =>\tRESET START [%s:%d]\n", cycle,
                   __FILE__, __LINE__);
        } else if (step >= RESET_TICKS) {
            host->op = HostIdle;
            host->step = 0u;
            printf("\nHOST\t#%8lu cyc =>\tRESET END [%s:%d]\n", cycle, __FILE__,
                   __LINE__);
        }
        result = 0;
        break;
    }

    case HostSuspend:
    case HostResume:
    case HostIdle:
        // Nothing to do ...
        host->step++;
        result = 0;
        break;

    case HostSOF:
        result = token_send_step(&host->xfer, in, out);
        if (result == 1) {
            host->op = HostIdle;
        }
        break;

    case HostBulkOUT:
        // printf("[%s:%d] potatoe\n", __FILE__, __LINE__);
        return bulk_out_step(host, in, out);

    case HostSETUP:
        result = stdreq_step(host, in, out);
        if (result > 0) {
            printf("\nHOST\t#%8lu cyc =>\tSUCCESS [%s:%d]\n", cycle, __FILE__, __LINE__);
        }
        return result;

    case HostBulkIN:
        host->step++;
        printf("\nHOST\t#%8lu cyc =>\tERROR\n", cycle);
        break;

    default:
        host->step++;
        printf("\nHOST\t#%8lu cyc =>\tERROR\n", cycle);
        break;
    }

    memcpy(&host->prev, in, sizeof(ulpi_bus_t));

    return result; 
}
