#include "usbhost.h"
#include "stdreq.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static int stdreq_setup_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (host->step) {
    default:
	host->step++;
	printf("H@%8lu => ERROR\n", host->cycle);
	exit(1);
    }

    return result;
}


void stdreq_init(stdreq_steps_t* steps)
{
    steps->setup = stdreq_setup_step;
    steps->data0 = NULL;
    steps->data1 = NULL;
    steps->status = NULL;
}

/**
 * Request the indicated descriptor, from a device.
 */
int usbh_get_descriptor(usb_host_t* host, uint16_t num, uint8_t* buf, uint16_t* len)
{
    if (host->op != HostIdle) {
	return -1;
    }
    transfer_t* xfer = &(host->xfer);
    usb_stdreq_t req;

    xfer->address = host->addr;
    xfer->endpoint = 0;
    xfer->type = SETUP;
    xfer->stage = AssertDir;

    // SETUP DATA0 (OUT) packet info, for the std. req.
    xfer->tx_len = sizeof(usb_stdreq_t);
    xfer->tx_ptr = 0;
    req.bmRequestType = 0x80;
    req.bRequest = 0x06;
    req.wValue = num;
    req.wIndex = 0;
    req.wLength = *len;
    memcpy(&xfer->tx, &req, sizeof(usb_stdreq_t));

    // IN DATA1 packet
    xfer->rx_len = *len;
    xfer->rx_ptr = 0;

    host->buf = buf;
    host->len = len;
    host->op = HostSETUP;
    host->step = 0;

    return 1;
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


int set_configuration(uint16_t wValue)
{
    return -1;
}
