#include "tc_bulkin.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


#define BULK_IN_EP 1
// #define BULK_IN_EP 2


typedef enum __bulkin_state {
    BulkIN0,
    BulkIN1,
    BulkIN2,
    BINDone,
} bulkin_state_t;

static const char tc_bulkin_name[] = "BULK IN";
static const char bulkin_strings[4][16] = {
    {"BulkIN0"},
    {"BulkIN1"},
    {"BulkIN2"},
    {"BINDone"},
};

static void tc_bulkin_xfer(usb_host_t* host, const uint8_t ep)
{
    transfer_t* xfer = &host->xfer;
    host->op = HostBulkIN;

    xfer->type = IN;
    xfer->stage = NoXfer;
    xfer->address = host->addr;
    xfer->endpoint = ep;

    const uint16_t tok =
        crc5_calc(((uint16_t)host->addr & 0x7F) | ((uint16_t)(ep & 0x0F) << 7));
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;

    // xfer->rx_len = 16384;
    xfer->rx_ptr = 0;
}

static int tc_bulkin_init(usb_host_t* host, void* data)
{
    bulkin_state_t* st = (bulkin_state_t*)data;
    vpi_printf("\n[%s:%d] %s INIT (cycle = %lu)\n\n", __FILE__, __LINE__,
               tc_bulkin_name, host->cycle);

    *st = BulkIN0;
    tc_bulkin_xfer(host, BULK_IN_EP);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK IN transaction has
 * been sent/received.
 */
static int tc_bulkin_step(usb_host_t* host, void* data)
{
    bulkin_state_t* st = (bulkin_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = bulkin_strings[*st];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (*st) {
    case BulkIN0:
        // BulkIN0 completed, so move to BulkIN1
	// assert(xfer->ep_seq[BULK_IN_EP] == SIG1);
        // transfer_ack(xfer);
        tc_bulkin_xfer(host, BULK_IN_EP);
        *st = BulkIN1;
        return 0;

    case BulkIN1:
        // BulkIN1 completed, so move to BulkIN2
	// assert(xfer->ep_seq[BULK_IN_EP] == SIG0);
        // transfer_ack(xfer);
        tc_bulkin_xfer(host, BULK_IN_EP);
        *st = BulkIN2;
        return 0;

    case BulkIN2:
        // BulkIN2 completed, so move to BINDone
	// assert(xfer->ep_seq[BULK_IN_EP] == SIG1);
        // transfer_ack(xfer);
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
        *st = BINDone;
        return 1;

    case BINDone:
        // Bulk OUT transaction tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid BULK IN state: 0x%x\n",
                   __FILE__, __LINE__, *st);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_bulkin(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    bulkin_state_t* st = malloc(sizeof(bulkin_state_t));
    *st = BulkIN0;

    tc->name = tc_bulkin_name;
    tc->data = (void*)st;
    tc->init = tc_bulkin_init;
    tc->step = tc_bulkin_step;

    return tc;
}
