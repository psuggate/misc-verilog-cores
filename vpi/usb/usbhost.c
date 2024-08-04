/**
 * Simulates a USB host controller, by handling USB transactions.
 * NOTE:
 *  - not cycle-accurate, as it works at the packet-level of abstraction;
 *  - to generate SOF's and EOF's, needs additional structure;
 */
#include "usbhost.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>


#define RESET_TICKS     60000
#define SOF_N_TICKS      7500
#define HOST_BUF_LEN    16384u

// Global, default configuration-request step-functions
extern stdreq_steps_t stdreqs;


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

static int stdreq_start(usb_host_t* host, usb_stdreq_t* req)
{
    transfer_t* xfer = &(host->xfer);
    xfer->address = host->addr;
    xfer->endpoint = 0;
    xfer->type = SETUP;
    xfer->stage = AssertDir;

    // SETUP DATA0 (OUT) packet info, for the std. req.
    xfer->tx_len = sizeof(usb_stdreq_t);
    xfer->tx_ptr = 0;
    memcpy(&xfer->tx, req, sizeof(usb_stdreq_t));

    // IN DATA1 packet
    xfer->rx_len = host->len;
    xfer->rx_ptr = 0;

    host->op = HostSETUP;
    host->step = 0;

    return 1;
}

/**
 * Step through a USB standard request (to control-pipe #0).
 * Returns:
 *  -1  --  failure/error;
 *   0  --  stepped successfully; OR
 *   1  --  completed.
 */
static int stdreq_step(usb_host_t* host, usb_stdreq_t* req)
{
    return -1;
}

/**
 * Request the indicated descriptor, from a device.
 */
int usbh_get_descriptor(usb_host_t* host, uint16_t num)
{
    if (host->op != HostIdle) {
	return -1;
    }
    usb_stdreq_t req;
    usb_desc_t* desc = malloc(sizeof(usb_desc_t));
    desc->dtype = num; // Todo: string-descriptor type
    desc->value.dat = host->buf;

    if (get_descriptor(&req, num, 0, MAX_CONFIG_SIZE, desc) < 0) {
	return -1;
    }

    return stdreq_start(host, &req);
}

/**
 * Take ownership of the bus, terminating any existing transaction, and then
 * driving an RX CMD to the device.
 */
static int start_host_to_func(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (host->step > 1) {
	printf("H@%8lu => ERROR, step = %d\n", host->cycle, host->step);
	return -1;
    } else if (host->step == 0 && is_ulpi_phy_idle(in)) {
	// Happy path, Step I:
	out->dir = SIG1;
	out->nxt = SIG1;
	out->data.a = 0x00; // High-impedance
	out->data.b = 0xff; // High-impedance
	host->step = 1;
    } else if (host->step == 1 && is_ulpi_phy_turn(in)) {
	// Happy path, Step II:
	out->nxt = SIG0;
	out->data.a = host->phy.state.rx_cmd;
	out->data.b = 0x00;
	host->step = 2;
    } else {
	printf("H@%8lu => ERROR, dir = %d, nxt = %d\n", host->cycle, in->dir, in->nxt);
	out->dir = SIGX;
	out->nxt = SIGX;
	out->data.a = 0xff; // Todo: RX CMD
	out->data.b = 0xff; // Todo: RX CMD
	return -1;
    }

    return 0;
}

/**
 * Drive "End-Of-Packet" onto bus.
 */
static int drive_eop(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
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
    return 0;
}

static int sof_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (host->step) {

    case 0:
    case 1:
	result = start_host_to_func(host, in, out);
	break;

    case 2:
	// PID byte, for the SOF
	host->step++;
	break;

    case 3:
	// First data byte of SOF
	host->step++;
	break;

    case 4:
	// Last byte of SOF
	host->step++;
	break;

    case 5:
	result = drive_eop(host, in, out);
	break;

    default:
	host->op = HostIdle;
	host->step = 0u;
	result = 0;
	break;

    }

    return result;
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
    host->speed = 0;
    host->error_count = 0;
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
    stdreq_init(&stdreqs);
    usbh_reset(host);
    host->cycle = 0ul;
    host->sof = 0u;
    host->buf = (uint8_t*)malloc(HOST_BUF_LEN);
    host->len = HOST_BUF_LEN;
}

/**
 * Given the current USB host-state, and bus values, compute the next state and
 * bus values.
 */
int usbh_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;
    uint64_t cycle = host->cycle;

    if (in->rst_n == SIG0) {
	printf("H@%8lu => Reset issued\n", cycle);
	usbh_reset(host);
	out->rst_n = SIG1;
    } else if (host->cycle % SOF_N_TICKS == 0ul) {
	if (host->op > HostIdle) {
	    printf("H@%8lu => Transaction cancelled for SOF\n", cycle);
	} else if (host->op < HostIdle) {
	    // Ignore SOF
	} else {
	    printf("H@%8lu => SOF\n", cycle);
	    host->op = HostSOF;
	    host->step = 0u;
	}
    }

    switch (host->op) {

    case HostError:
	host->step++;
	break;

    case HostReset: {
	uint32_t step = ++host->step;
	if (step < 2) {
	    printf("H@%8lu => RESET START\n", cycle);
	} else if (step >= RESET_TICKS) {
	    host->op = HostIdle;
	    host->step = 0u;
	    printf("H@%8lu => RESET END\n", cycle);
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
	result = sof_step(host, in, out);
	break;

    case HostBulkOUT:
	result = bulk_out_step(host, in, out);
	break;

    case HostSETUP:
	// SETUP
	result = stdreqs.setup(&host->xfer, in, out);
	// DATAx
	// STATUS
	break;

    case HostBulkIN:
	host->step++;
	printf("H@%8lu => ERROR\n", cycle);
	break;

    default:
	host->step++;
	printf("H@%8lu => ERROR\n", cycle);
	break;
    }

    host->cycle++;
    return result; 
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
