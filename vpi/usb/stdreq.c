#include "ulpi.h"
#include "stdreq.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


// Global, default configuration-request step-functions
stdreq_steps_t stdreqs;


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
    req->bRequest = STDREQ_GET_DESCRIPTOR;
    req->wValue = type;
    req->wIndex = lang;
    req->wLength = len;
    req->data = (uint8_t*)desc;

    return 1;
}


// -- Testbench -- //

/**
 * Evaluates a step-function, until it completes.
 * Note: doesn't handle receiving packets.
 */
#if 0
static int ulpi_step_with(step_fn_t step_fn, transfer_t* xfer, ulpi_bus_t* bus)
{
    ulpi_bus_t out = {0};
    int result = 0;

    xfer->stage = 0;
    ulpi_bus_idle(bus);

    while (result == 0) {
        result = step_fn(xfer, bus, &out);
        memcpy(bus, &out, sizeof(ulpi_bus_t));
        printf(".");
    }

    return result;
}
#endif /* 0 */

/**
 * USB function being simulated.
 */
static int user_func_step(const ulpi_bus_t* in, ulpi_bus_t* out, void* user_data)
{
    return -1;
}

/**
 * Request a descriptor, stepping through and checking all stages.
 */
void test_stdreq_get_desc(uint16_t num)
{
    usb_stdreq_t req = {0};
    usb_desc_t desc = {0};
    transfer_t xfer = {0};
    ulpi_bus_t bus = {0};
    int result;

    printf("Issuing 'GET DESCRIPTOR'");

    // -- Stage 1: SETUP -- //

    // Phase I: send the 'SETUP' token
    // Phase II: send the 'DATA0' packet with the configuration request params
    // Phase III: wait for the 'ACK' (if successful)
    xfer.type = SETUP;
    get_descriptor(&req, num, 0x00, MAX_CONFIG_SIZE, &desc);
    assert(ulpi_step_with(token_send_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.type = DnDATA0;
    assert(ulpi_step_with(datax_send_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.ep_seq[0] = SIG1; // 'ACK'


    // -- Stage 2: DATA0/1 IN -- //

    // Phase IV: send the 'IN' token
    // Phase V: wait for the 'DATA1'
    // Phase VI: send 'ACK' handshake if receive was successful
    transfer_in(&xfer, 0, 0);
    assert(ulpi_step_with(token_send_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.type = UpDATA1;
    assert(ulpi_step_with(datax_recv_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.ep_seq[0] = SIG0; // 'ACK'


    // -- Stage 3: STATUS OUT -- //

    // Phase VII: send 'OUT' token
    // Phase VIII: send 'DATA1' (ZDP)
    // Phase IX: wait for 'ACK' handshake (if successful)
    transfer_out(&xfer, 0, 0);
    xfer.ep_seq[0] = SIG1; // Required by USB standard
    assert(ulpi_step_with(token_send_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.type = DnDATA1;
    xfer.tx_len = 0;
    assert(ulpi_step_with(datax_send_step, &xfer, &bus, user_func_step, NULL) == 1);
    xfer.ep_seq[0] = SIG0; // 'ACK'

    printf("\t\tSUCCESS\n");
}
