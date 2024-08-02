#include "ulpi.h"
#include "stdreq.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static int stdreq_setup_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_data0_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_data1_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_status_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

void stdreq_init(stdreq_steps_t* steps)
{
    steps->setup = stdreq_setup_step;
    steps->data0 = stdreq_data0_step;
    steps->data1 = stdreq_data1_step;
    steps->status = stdreq_status_step;
}

/**
 * Configure a USB device to use the given 'addr'.
 */
int usbh_set_address(transfer_t* xfer, uint8_t addr)
{
    return -1;
}

/**
 * Set the device to use the indicated configuration.
 */
int usbh_set_config(transfer_t* xfer, uint8_t num)
{
    return -1;
}


int set_configuration(usb_stdreq_t* req, uint16_t wValue)
{
    return -1;
}

int get_descriptor(usb_stdreq_t* req, uint16_t type, uint16_t lang, uint16_t len, usb_desc_t* desc)
{
    req->bmRequestType = 0x80;
    req->bRequest = 0x06;
    req->wValue = type;
    req->wIndex = lang;
    req->wLength = len;
    req->data = (uint8_t*)desc;

    return 1;
}
