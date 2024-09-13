#include "tc_ddr3in.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __ddr3in_step {
    DDR3Cmd,
    DDR3Dat,
    DDR3End,
} ddr3in_step_t;

typedef struct {
    uint32_t addr;
    uint8_t step;
    uint8_t iter;
    uint8_t out;
    uint8_t in;
    uint8_t id;
} ddr3in_state_t;

static const char tc_ddr3in_name[] = "BULK DDR3 IN";
static const char ddr3in_strings[3][16] = {
    {"DDR3Cmd"},
    {"DDR3Dat"},
    {"DDR3End"},
};


/**
 * DDR3 IN transaction-initialisation routine, that first sends a FETCH command,
 * followed by a USB Bulk IN request.
 */
static void tc_ddr3in_cmd(usb_host_t* host, const ddr3in_state_t* st)
{
    transfer_t* xfer = &host->xfer;
    host->op = HostBulkOUT;

    xfer->type = OUT;
    xfer->stage = NoXfer;
    xfer->address = host->addr;
    xfer->endpoint = st->out;

    const uint16_t tok =
        crc5_calc(((uint16_t)host->addr & 0x7F) | ((uint16_t)(st->out & 0x0F) << 7));
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;

    xfer->tx_len = 6;
    xfer->tx_ptr = 0;

    xfer->tx[0] = 0x80; // FETCH
    xfer->tx[1] = 0x03u; // Length := BYTES / 4 - 1
    xfer->tx[2] = st->addr & 0xFF;
    xfer->tx[3] = (st->addr >> 8) & 0xFF;
    xfer->tx[4] = (st->addr >> 16) & 0xFF;
    xfer->tx[5] = ((st->addr >> 24) & 0x0F) | ((st->id & 0x0F) << 4);

    uint16_t crc = crc16_calc(xfer->tx, xfer->tx_len);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;

    xfer->rx_ptr = 0;
}

static void tc_ddr3in_dat(usb_host_t* host, const ddr3in_state_t* st)
{
    transfer_t* xfer = &host->xfer;
    host->op = HostBulkIN;

    xfer->type = IN;
    xfer->stage = NoXfer;
    xfer->address = host->addr;
    xfer->endpoint = st->in;

    const uint16_t tok =
        crc5_calc(((uint16_t)host->addr & 0x7F) | ((uint16_t)(st->in & 0x0F) << 7));
    xfer->tok1 = tok & 0xFF;
    xfer->tok2 = (tok >> 8) & 0xFF;

    xfer->rx_ptr = 0;
}

static int tc_ddr3in_init(usb_host_t* host, void* data)
{
    ddr3in_state_t* st = (ddr3in_state_t*)data;
    vpi_printf("\n[%s:%d] %s INIT (cycle = %lu)\n\n", __FILE__, __LINE__,
               tc_ddr3in_name, host->cycle);

    st->step = DDR3Cmd;
    st->iter = 0;
    tc_ddr3in_cmd(host, st);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK IN transaction has
 * been sent/received.
 */
static int tc_ddr3in_step(usb_host_t* host, void* data)
{
    ddr3in_state_t* st = (ddr3in_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = ddr3in_strings[st->step];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case DDR3Cmd:
        // DDR3Cmd completed, so move to DDR3Dat
        tc_ddr3in_dat(host, st);
        st->step = DDR3Dat;
        return 0;

    case DDR3Dat:
        // DDR3Dat completed, so move to DDR3End
        xfer->stage = NoXfer;
	if (++st->iter >= 3) {
	    xfer->type = XferIdle;
	    host->op = HostIdle;
	    st->step = DDR3End;
	    return 1;
	} else {
	    tc_ddr3in_cmd(host, st);
	    st->step = DDR3Cmd;
	}
	return 0;

    case DDR3End:
        // DDR Bulk IN transaction tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid BULK IN state: 0x%x\n",
                   __FILE__, __LINE__, st->step);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_ddr3in(const uint32_t addr)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    ddr3in_state_t* st = malloc(sizeof(ddr3in_state_t));
    st->step = DDR3Cmd;
    st->iter = 0;
    st->out  = DDR3_OUT_EP;
    st->in   = DDR3_IN_EP;
    st->id   = rand() & 0x0F;
    st->addr = addr;

    tc->name = tc_ddr3in_name;
    tc->data = (void*)st;
    tc->init = tc_ddr3in_init;
    tc->step = tc_ddr3in_step;

    return tc;
}
