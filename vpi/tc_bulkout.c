#include "tc_bulkout.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


#define BULK_OUT_EP 2


typedef enum __bulkout_state {
    BulkOUT0,
    BulkOUT1,
    BulkOUT2,
    BulkDone,
} bulkout_state_t;

static const char tc_bulkout_name[] = "BULK OUT";
static const char bulkout_strings[4][16] = {
    {"BulkOUT0"},
    {"BulkOUT1"},
    {"BulkOUT2"},
    {"BulkDone"},
};

static void tc_bulkout_xfer(usb_host_t* host, int n, uint8_t ep)
{
    transfer_t* xfer = &host->xfer;
    host->op = HostBulkOUT;

    xfer->type = OUT;
    xfer->stage = NoXfer;
    xfer->address = host->addr;
    xfer->endpoint = ep;

    const uint16_t tok =
        crc5_calc(((uint16_t)host->addr & 0x7F) | ((uint16_t)(ep & 0x0F) << 7));
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;

    xfer->tx_len = n;
    xfer->tx_ptr = 0;

    for (int i=n; i--;) {
        xfer->tx[i] = rand();
    }

    uint16_t crc = crc16_calc(xfer->tx, n);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
}

static int tc_bulkout_init(usb_host_t* host, void* data)
{
    bulkout_state_t* st = (bulkout_state_t*)data;
    *st = BulkOUT0;

    tc_bulkout_xfer(host, 16, BULK_OUT_EP);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK OUT transaction has
 * been sent/received.
 */
static int tc_bulkout_step(usb_host_t* host, void* data)
{
    bulkout_state_t* st = (bulkout_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = bulkout_strings[*st];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (*st) {
    case BulkOUT0:
        // BulkOUT0 completed, so move to BulkOUT1
        transfer_ack(xfer);
        tc_bulkout_xfer(host, 37, BULK_OUT_EP);
        *st = BulkOUT1;
        return 0;

    case BulkOUT1:
        // BulkOUT1 completed, so move to BulkOUT2
        transfer_ack(xfer);
        tc_bulkout_xfer(host, 0, BULK_OUT_EP);
        *st = BulkOUT2;
        return 0;

    case BulkOUT2:
        // BulkOUT2 completed, so move to BulkDone
        transfer_ack(xfer);
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
        *st = BulkDone;
        return 1;

    case BulkDone:
        // Bulk OUT transaction tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n",
                   __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid BULK OUT state: 0x%x\n",
                   __FILE__, __LINE__, *st);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_bulkout(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    bulkout_state_t* st = malloc(sizeof(bulkout_state_t));
    *st = BulkOUT0;

    tc->name = tc_bulkout_name;
    tc->data = (void*)st;
    tc->init = tc_bulkout_init;
    tc->step = tc_bulkout_step;

    return tc;
}
