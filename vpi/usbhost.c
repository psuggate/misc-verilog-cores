/**
 * Simulates a USB host controller, by handling USB transactions.
 * NOTE:
 *  - not cycle-accurate, as it works at the packet-level of abstraction;
 *  - to generate SOF's and EOF's, needs additional structure;
 */
#include "usbhost.h"
#include <vpi_user.h>


#define RESET_TICKS 60000
#define SOF_N_TICKS 7500


/**
 * Take ownership of the bus, terminating any existing transaction, and then
 * driving an RX CMD to the device.
 */
static int take_bus(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != 0 || in->nxt != 0) {
	out->dir = 1;
	out->nxt = 0;
	out->data.a = 0xff; // Todo: RX CMD
	out->data.b = 0xff; // Todo: RX CMD
    } else if (in->data.a == 0 && in->data.b == 0) {
	out->dir = 1;
	out->nxt = 1;
	out->data.a = 0x00; // High-impedance
	out->data.b = 0xff; // High-impedance
	host->step = 1;
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
    case 2:
	result = take_bus(host, in, out);
	break;

    case 3:
	// PID byte, for the SOF
	host->step++;
	break;

    case 4:
	// First data byte of SOF
	host->step++;
	break;

    case 5:
	// Last byte of SOF
	host->step++;
	break;

    case 6:
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


void usbh_init(usb_host_t* host)
{
    // Todo ...
    if (host == NULL) {
	return;
    }

    host->cycle = 0ul;
    host->op = HostReset;
    host->step = 0u;
    host->sof = 0u;
    host->turnaround = 0;
    host->addr = 0;
    host->speed = 0;
    host->error_count = 0;
}

/**
 * Given the current USB host-state, and bus values, compute the next state and
 * bus values.
 */
int usbh_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    if (host->cycle % SOF_N_TICKS == 0ul) {
	if (host->op > HostIdle) {
	    vpi_printf("Transaction cancelled for SOF @%lu\n", host->cycle);
	} else if (host->op < HostIdle) {
	    // Ignore SOF
	} else {
	    vpi_printf("SOF @%lu\n", host->cycle);
	    host->op = HostSOF;
	    host->step = 0u;
	}
    }

    switch (host->op) {

    case HostError:
	host->step++;
	break;

    case HostReset:
	if (++host->step >= RESET_TICKS) {
	    host->op = HostIdle;
	    host->step = 0u;
	}
	result = 0;
	break;

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
	// DATAx
	// STATUS
	host->step++;
	vpi_printf("ERROR\n");
	break;

    case HostBulkIN:
	host->step++;
	vpi_printf("ERROR\n");
	break;

    default:
	host->step++;
	vpi_printf("ERROR\n");
	break;
    }

    host->cycle++;
    return result; 
}

int usbh_busy(usb_host_t* host)
{
    return host->op != HostIdle;
}

int usbh_send(usb_host_t* host, usb_xact_t* xact)
{
    return -1;
}


/**
 * Queue-up a device reset, to be issued.
 */
int usbh_reset_device(usb_host_t* host, uint8_t addr)
{
    return -1;
}

/**
 * Request the indicated descriptor, from a device.
 */
int usbh_get_descriptor(usb_host_t* host, uint8_t num, uint8_t* buf, uint16_t* len)
{
    return -1;
}

/**
 * Configure a USB device to use the given 'addr'.
 */
int usbh_set_address(usb_host_t* host, uint8_t addr)
{
    return -1;
}

/**
 * Set the device to use the indicated configuration.
 */
int usbh_set_config(usb_host_t* host, uint8_t num)
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
