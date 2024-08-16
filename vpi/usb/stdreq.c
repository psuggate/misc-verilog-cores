#include "ulpi.h"
#include "stdreq.h"
#include "usbcrc.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/**
 * Queue-up a USB standard request.
 */
static int stdreq_start(usb_host_t* host, const usb_stdreq_t* req)
{
    transfer_t* xfer = &(host->xfer);
    const uint16_t tok = crc5_calc((uint16_t)host->addr & 0x7F);
    const uint16_t crc = crc16_calc((uint8_t*)req, 8);

    xfer->address = host->addr;
    xfer->endpoint = 0;
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;
    xfer->type = SETUP;
    xfer->stage = NoXfer; // AssertDir;

    // SETUP DATA0 (OUT) packet info, for the std. req.
    xfer->tx_len = 8;
    xfer->tx_ptr = 0;
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
    memcpy(&xfer->tx, req, sizeof(usb_stdreq_t));

    // IN DATA1 packet
    xfer->rx_len = host->len;
    xfer->rx_ptr = 0;

    host->op = HostSETUP;
    host->step = 0;

    return 1;
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

/**
 * Request the indicated descriptor, from a device.
 */
int stdreq_get_descriptor(usb_host_t* host, uint16_t num)
{
    if (host->op != HostIdle) {
        return -1;
    }

    usb_stdreq_t req;
    usb_desc_t* desc = malloc(sizeof(usb_desc_t));
    desc->dtype = num; // Todo: string-descriptor type
    desc->value.dat = host->buf;

    if (get_descriptor(&req, num, 0, MAX_CONFIG_SIZE, desc) < 0) {
        printf("HOST\t#%8lu cyc =>\tUSBH GET DESCRIPTOR failed [%s:%d]\n",
               host->cycle, __FILE__, __LINE__);
        return -1;
    }

    return stdreq_start(host, &req);
}

int stdreq_set_address(usb_host_t* host, uint8_t addr)
{
    usb_stdreq_t req;

    req.bmRequestType = 0x00;
    req.bRequest = STDREQ_SET_ADDRESS;
    req.wValue = addr;
    req.wIndex = 0;
    req.wLength = 0;
    req.data = NULL;

    return stdreq_start(host, &req);
}

void stdreq_show(usb_stdreq_t* req)
{
    printf("STD_REQ = {\n");
    printf("  bmRequestType:\t  0x%02x,\n", req->bmRequestType);
    printf("  bRequest:     \t  0x%02x,\n", req->bRequest);
    printf("  wValue:       \t0x%04x,\n", req->wValue);
    printf("  wIndex:       \t0x%04x,\n", req->wIndex);
    printf("  wLength:      \t0x%04x\n};\n", req->wLength);
}

/**
 * Step through a USB standard request (to control-pipe #0).
 * Returns:
 *  -1  --  failure/error;
 *   0  --  stepped successfully; OR
 *   1  --  completed.
 */
int stdreq_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    transfer_t* xfer = &host->xfer;
    int result = -1;

    switch (host->step) {

    case 0:
        // SETUP (SETUP)
        if (xfer->type != SETUP) {
            printf(
                "HOST\t#%8lu cyc =>\tHost transfer not configured for SETUP [%s:%d]\n",
                host->cycle, __FILE__, __LINE__);
            show_host(host);
            return -1;
        }
        result = token_send_step(&host->xfer, in, out);
        break;

    case 1:
        // DATA0 (SETUP)
        if (xfer->type != DnDATA0) {
            xfer->type = DnDATA0;
            xfer->stage = NoXfer;
            assert(xfer->tx_len >= 8);
        }
        result = datax_send_step(&host->xfer, in, out);
        break;

    case 2:
        // ACK (SETUP)
        if (xfer->type != UpACK) {
            xfer->type = UpACK;
            xfer->stage = NoXfer;
        }
        result = ack_recv_step(&host->xfer, in, out);
        break;

    case 3:
        // IN (DATA)
        if (xfer->type != IN) {
            xfer->type = IN;
            xfer->stage = NoXfer;
        }
        result = token_send_step(&host->xfer, in, out);
        break;

    case 4:
        // DATA1 (DATA)
        if (xfer->type != UpDATA1) {
            xfer->type = UpDATA1;
            xfer->stage = NoXfer;
            xfer->rx_len = MAX_PACKET_SIZE;
            xfer->rx_ptr = 0;
        }
        result = datax_recv_step(&host->xfer, in, out);
        break;

    case 5:
        // ACK (DATA)
        if (xfer->type != DnACK) {
            xfer->type = DnACK;
            xfer->stage = NoXfer;
        }
        result = ack_send_step(&host->xfer, in, out);
        break;

    case 6:
        // OUT (STATUS)
        if (xfer->type != OUT) {
            xfer->type = OUT;
            xfer->stage = NoXfer;
        }
        result = token_send_step(&host->xfer, in, out);
        break;

    case 7:
        // ZDP (STATUS)
        if (xfer->type != DnDATA1) {
            xfer->type = DnDATA1;
            xfer->stage = NoXfer;
            xfer->tx_len = 0;
        }
        result = datax_send_step(&host->xfer, in, out);
        break;

    case 8:
        // ACK (STATUS)
        if (xfer->type != UpACK) {
            xfer->type = UpACK;
            xfer->stage = NoXfer;
        }
        result = ack_recv_step(&host->xfer, in, out);
        break;

    default:
        // ERROR
        printf("Invalid SETUP transaction step: %u [%s:%d]\n",
               host->step, __FILE__, __LINE__);
        show_host(host);
        return -1;
    }

    if (result < 0) {
        printf("SETUP transaction failed [%s:%d]\n", __FILE__, __LINE__);
        show_host(host);
        ulpi_bus_show(in);
    } else if (result > 1) {
        host->step++;
        xfer->type = XferIdle;
        return 0;
    }

    return result;
}


// -- Testbench -- //

/**
 * USB function being simulated.
 */
static int user_func_step(void* user_data, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    // Toods
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

    printf("Issuing 'GET DESCRIPTOR' [%s:%d]", __FILE__, __LINE__);

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
