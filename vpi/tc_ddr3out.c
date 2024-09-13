#include "tc_ddr3out.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


#define NUM_ITER        (7)

typedef enum __ddr3out_step {
    DDR3Out,
    DDR3Res,
    DDR3End,
} ddr3out_step_t;

typedef struct {
    uint32_t addr;
    uint8_t step;
    uint8_t iter;
    uint8_t beat;
    uint8_t out;
    uint8_t in;
    uint8_t id;
} ddr3out_state_t;

static const char tc_ddr3out_name[] = "BULK DDR3 OUT";
static const char ddr3out_strings[3][16] = {
    {"DDR3Out"},
    {"DDR3Res"},
    {"DDR3End"},
};
static const int ddr3out_lengths[8] = { 4, 4, 8, 16, 20, 12, 24, 0 };


/**
 * DDR3 OUT transaction-initialisation routine.
 */
static void tc_ddr3out_cmd(usb_host_t* host, int n, const ddr3out_state_t* st)
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

    size_t len = n*st->beat + 6;
    uint32_t* dst = (uint32_t*)&xfer->tx[6];

    xfer->tx_len = len;
    xfer->tx_ptr = 0;

    xfer->tx[0] = 0x01; // STORE
    xfer->tx[1] = (uint8_t)(n - 1) | 0x03u; // Length - 1 (AXI4)
    xfer->tx[2] = st->addr & 0xFF;
    xfer->tx[3] = (st->addr >> 8) & 0xFF;
    xfer->tx[4] = (st->addr >> 16) & 0xFF;
    xfer->tx[5] = ((st->addr >> 24) & 0x0F) | ((st->id & 0x0F) << 4);

    for (int i=n; i--;) {
        dst[i] = rand();
    }

    uint16_t crc = crc16_calc(xfer->tx, len);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
}

static void tc_ddr3out_res(usb_host_t* host, const ddr3out_state_t* st)
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

static int tc_ddr3out_init(usb_host_t* host, void* data)
{
    ddr3out_state_t* st = (ddr3out_state_t*)data;
    st->step = DDR3Out;
    st->beat = 4;
    st->out  = DDR3_OUT_EP;
    st->in   = DDR3_IN_EP;
    st->id   = rand() & 0x0F;

    tc_ddr3out_cmd(host, ddr3out_lengths[st->iter], st);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a DDR3 OUT transaction has
 * been sent/received.
 */
static int tc_ddr3out_step(usb_host_t* host, void* data)
{
    ddr3out_state_t* st = (ddr3out_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = ddr3out_strings[st->step];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case DDR3Out:
        // DDR3Out completed, so move on to the next DDR3 'STORE' command
	if (st->iter++ < NUM_ITER) {
	    tc_ddr3out_cmd(host, ddr3out_lengths[st->iter], st);
	    st->step = DDR3Out;
	    return 0;
	}
        tc_ddr3out_res(host, st);
	st->iter = 0;
        st->step = DDR3Res;
        return 0;

    case DDR3Res:
        // Fetch each of the DDR3 'STORE' responses
	if (st->iter++ < NUM_ITER) {
	    tc_ddr3out_res(host, st);
	    st->step = DDR3Res;
	    return 0;
	}
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
        st->step = DDR3End;
        return 1;

    case DDR3End:
        // DDR3 OUT transaction tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n",
                   __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid DDR3 OUT state: 0x%x\n",
                   __FILE__, __LINE__, st->step);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_ddr3out(const uint32_t addr)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    ddr3out_state_t* st = malloc(sizeof(ddr3out_state_t));
    st->step = DDR3Out;
    st->iter = 0;
    st->addr = addr; // 16-byte-aligned address
    st->beat = 4; // Bytes per beat
    st->out  = DDR3_OUT_EP;
    st->in   = DDR3_IN_EP;
    st->id   = 0x01; // Transaction ID

    tc->name = tc_ddr3out_name;
    tc->data = (void*)st;
    tc->init = tc_ddr3out_init;
    tc->step = tc_ddr3out_step;

    return tc;
}
