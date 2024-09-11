#include "tc_bulkout.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __bulkout_state {
    BulkOUT0,
    BulkOUT1,
    BulkOUT2,
    BulkOUT3,
    BulkOUT4,
    BulkOUT5,
    BulkOUT6,
    BulkDone,
} bulkout_state_t;

static const char tc_bulkout_name[] = "BULK OUT";
static const char bulkout_strings[8][16] = {
    {"BulkOUT0"},
    {"BulkOUT1"},
    {"BulkOUT2"},
    {"BulkOUT3"},
    {"BulkOUT4"},
    {"BulkOUT5"},
    {"BulkOUT6"},
    {"BulkDone"},
};


/**
 * Bulk OUT transaction-initialisation routine.
 */
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
        tc_bulkout_xfer(host, 37, BULK_OUT_EP);
        *st = BulkOUT1;
        return 0;

    case BulkOUT1:
        // BulkOUT1 completed, so move to BulkOUT2
        tc_bulkout_xfer(host, 0, BULK_OUT_EP);
        *st = BulkOUT2;
        return 0;

    case BulkOUT2:
        // BulkOUT2 completed, so move to BulkOUT3
	// Note: Bulk OUT transfer of size=1, because Bulk IN of this size used
	//   to break the ULPI encoder.
        tc_bulkout_xfer(host, 1, BULK_OUT_EP);
        *st = BulkOUT3;
        return 0;

    case BulkOUT3:
        // BulkOUT3 completed, so move to BulkOUT4
        tc_bulkout_xfer(host, 2, BULK_OUT_EP);
        *st = BulkOUT4;
        return 0;

    case BulkOUT4:
        // BulkOUT4 completed, so move to BulkOUT5
        tc_bulkout_xfer(host, 3, BULK_OUT_EP);
        *st = BulkOUT5;
        return 0;

    case BulkOUT5:
        // BulkOUT5 completed, so move to BulkOUT6
        tc_bulkout_xfer(host, 4, BULK_OUT_EP);
        *st = BulkOUT6;
        return 0;

    case BulkOUT6:
        // BulkOUT6 completed, so move to BulkDone
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
