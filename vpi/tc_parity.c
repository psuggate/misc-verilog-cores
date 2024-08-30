#include "tc_parity.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __parity_step {
    BulkIN0,
    BulkIN1,
    BulkOUT0,
    BulkOUT1,
    DonePar,
} parity_step_t;

typedef struct {
    void (*adjust)(transfer_t* xfer);
    uint8_t step;
    uint8_t stage;
} parity_state_t;

static const char tc_parity_name[] = "BULK IN/OUT PARITY";
static const char parity_strings[5][16] = {
    {"BulkIN0"},
    {"BulkIN1"},
    {"BulkOUT0"},
    {"BulkOUT1"},
    {"DonePar"},
};


static void adjust_seq(transfer_t* xfer)
{
    transfer_ack(xfer);
}

static void adjust_crc(transfer_t* xfer)
{
    if (xfer->endpoint == BULK_IN_EP) {
	// Corrupted token, so the request must be ignored
	xfer->tok2 ^= 0x80;
    } else {
	// Corrupted data, so the request must be repeated
	xfer->crc1 ^= 0xFF;
    }
}

static void adjust_ept(transfer_t* xfer)
{
    xfer->endpoint ^= 0xF;
    transfer_tok(xfer);
}

/**
 * Construct a Bulk IN transfer, with correct or inverted parity-bit.
 */
static void tc_parity_xfer(usb_host_t* host, const uint8_t ep)
{
    transfer_t* xfer = &host->xfer;

    if (ep == BULK_IN_EP) {
        host->op = HostBulkIN;
        xfer->type = IN;
        xfer->rx_len = 0;
        xfer->rx_ptr = 0;
    } else {
        int n = ((rand() | 0x01) << 1) & 0x07;

        host->op = HostBulkOUT;
        xfer->type = OUT;

        xfer->tx_len = n;
        xfer->tx_ptr = 0;

        for (int i=n; i--;) {
            xfer->tx[i] = rand();
        }

        uint16_t crc = crc16_calc(xfer->tx, n);
        xfer->crc1 = crc & 0xFF;
        xfer->crc2 = (crc >> 8) & 0xFF;
    }

    xfer->stage = NoXfer;
    xfer->address = host->addr;
    xfer->endpoint = ep;

    const uint16_t tok =
        crc5_calc(((uint16_t)host->addr & 0x7F) | ((uint16_t)(ep & 0x0F) << 7));
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;
}

static int tc_parity_init(usb_host_t* host, void* data)
{
    parity_state_t* st = (parity_state_t*)data;

    switch (st->stage) {
    case 0:
        // host->step = 0;
	st->adjust = adjust_seq;
        break;
    case 1:
	st->adjust = adjust_crc;
        break;
    case 2:
	st->adjust = adjust_ept;
        break;
    case 3:
        return 1;
    }

    tc_parity_xfer(host, BULK_IN_EP);
    st->step = BulkIN0;
    st->adjust(&host->xfer);

    vpi_printf("[%s:%d] %s INIT (cycle = %lu, stage = %u, step = %u, EP = %u)\n",
               __FILE__, __LINE__, tc_parity_name, host->cycle, st->stage,
	       st->step, host->xfer.endpoint);

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK IN transaction has
 * been sent/received.
 */
static int tc_parity_step(usb_host_t* host, void* data)
{
    parity_state_t* st = (parity_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = parity_strings[st->step];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case BulkIN0:
        // BulkIN0 should have failed parity-checking, so move to BulkIN1
        st->adjust(&host->xfer);
        tc_parity_xfer(host, BULK_IN_EP);
        st->step = BulkIN1;
        return 0;

    case BulkIN1:
        // BulkIN1 completed, so move to BulkIN2
        tc_parity_xfer(host, BULK_OUT_EP);
        st->adjust(&host->xfer);
        st->step = BulkOUT0;
        return 0;

    case BulkOUT0:
        // BulkOUT0 should have failed parity-checking, so move to BulkOUT1
        st->adjust(&host->xfer);
        tc_parity_xfer(host, BULK_OUT_EP);
        st->step = BulkOUT1;
        return 0;

    case BulkOUT1:
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
	if (++st->stage < 3) {
	    tc_parity_init(host, data);
	    return 0;
	} else {
	    st->step = DonePar;
	    return 1;
	}

    case DonePar:
        // Bulk IN/OUT parity tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid BULK IN/OUT parity state: { 0x%02x, 0x%02x }\n",
                   __FILE__, __LINE__, st->step, st->stage);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_parity(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    parity_state_t* st = malloc(sizeof(parity_state_t));

    st->stage = 0;
    st->step = BulkIN0;
    st->adjust = adjust_seq;

    tc->name = tc_parity_name;
    tc->data = (void*)st;
    tc->init = tc_parity_init;
    tc->step = tc_parity_step;

    return tc;
}
