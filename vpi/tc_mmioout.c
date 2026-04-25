#include "tc_mmioout.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>

// #define MMIO_OUT_EP DDR3_OUT_EP
// #define MMIO_IN_EP  DDR3_IN_EP
#define MMIO_OUT_EP 2
#define MMIO_IN_EP  1

#define NUM_ITER        (7)

typedef enum __mmioout_step {
    MMIOCmd,
    MMIOOut,
    MMIORes,
    MMIOEnd,
} mmioout_step_t;

typedef struct {
    uint32_t addr;
    uint8_t step;
    uint8_t iter;
    uint8_t beat;
    uint8_t out;
    uint8_t in;
    uint8_t id;
} mmioout_state_t;

static const char tc_mmioout_name[] = "BULK MMIO OUT";
static const char mmioout_strings[4][16] = {
    {"MMIOCmd"},
    {"MMIOOut"},
    {"MMIORes"},
    {"MMIOEnd"},
};
static const int mmioout_lengths[8] = { 4, 4, 8, 16, 20, 12, 24, 0 };


/**
 * MMIO OUT transaction-initialisation routine.
 */
static void tc_mmioout_cmd(usb_host_t* host, int n, const mmioout_state_t* st)
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

    size_t len = 11;
    uint32_t* dst = (uint32_t*)&xfer->tx[4];
    xfer->tx_len = len;
    xfer->tx_ptr = 0;

    xfer->tx[0] = 'T'; xfer->tx[1] = 'A'; xfer->tx[2] = 'R'; xfer->tx[3] = 'T';
    xfer->tx[4] = st->addr & 0xFF;
    xfer->tx[5] = (st->addr >> 8) & 0xFF;
    xfer->tx[6] = (st->addr >> 16) & 0xFF;
    xfer->tx[7] = ((st->addr >> 24) & 0x0F) | ((st->id & 0x0F) << 4);
    xfer->tx[8] = (uint8_t)((n - 1) & 0xFF); // Length - 1 (AXI4)
    xfer->tx[9] = (uint8_t)(((n - 1) >> 8) & 0xFF);
    xfer->tx[10] = 0xC0;

    uint16_t crc = crc16_calc(xfer->tx, len);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
}

/**
 * MMIO OUT transaction-initialisation routine.
 */
static void tc_mmioout_dat(usb_host_t* host, int n, const mmioout_state_t* st)
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

    size_t len = n*st->beat;
    xfer->tx_len = len;
    xfer->tx_ptr = 0;

    for (int i=len; i--;) {
        xfer->tx[i] = rand();
    }

    uint16_t crc = crc16_calc(xfer->tx, len);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
}

static void tc_mmioout_res(usb_host_t* host, const mmioout_state_t* st)
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

static int tc_mmioout_init(usb_host_t* host, void* data)
{
    mmioout_state_t* st = (mmioout_state_t*)data;
    st->step = MMIOOut;
    st->beat = 4;
    st->out  = MMIO_OUT_EP;
    st->in   = MMIO_IN_EP;
    st->id   = rand() & 0x0F;

    tc_mmioout_cmd(host, mmioout_lengths[st->iter], st);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a MMIO OUT transaction has
 * been sent/received.
 */
static int tc_mmioout_step(usb_host_t* host, void* data)
{
    mmioout_state_t* st = (mmioout_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = mmioout_strings[st->step];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case MMIOCmd:
        // MMIOOut completed, so move on to the next MMIO 'STORE' command
	if (++st->iter < NUM_ITER) {
	    tc_mmioout_cmd(host, mmioout_lengths[st->iter], st);
	    st->step = MMIOOut;
	    return 0;
	}
	st->iter = 0;
        st->step = MMIOOut;
        tc_mmioout_dat(host, mmioout_lengths[st->iter], st);
        return 0;

    case MMIOOut:
        // MMIOOut completed, so move on to the next MMIO 'STORE' command
	if (++st->iter < NUM_ITER) {
	    tc_mmioout_dat(host, mmioout_lengths[st->iter], st);
	    st->step = MMIORes;
	    return 0;
	}
	st->iter = 0;
        st->step = MMIORes;
        tc_mmioout_res(host, st);
        return 0;

    case MMIORes:
        // Fetch each of the MMIO 'STORE' responses
	if (++st->iter < NUM_ITER) {
	    tc_mmioout_res(host, st);
	    st->step = MMIOCmd;
	    return 0;
	}
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
        st->step = MMIOEnd;
        return 1;

    case MMIOEnd:
        // MMIO OUT transaction tests completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n",
                   __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid MMIO OUT state: 0x%x\n",
                   __FILE__, __LINE__, st->step);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_mmioout(const uint32_t addr)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    mmioout_state_t* st = malloc(sizeof(mmioout_state_t));
    st->step = MMIOCmd;
    st->iter = 0;
    st->addr = addr; // 16-byte-aligned address
    st->beat = 4; // Bytes per beat
    st->out  = MMIO_OUT_EP;
    st->in   = MMIO_IN_EP;
    st->id   = 0x01; // Transaction ID

    tc->name = tc_mmioout_name;
    tc->data = (void*)st;
    tc->init = tc_mmioout_init;
    tc->step = tc_mmioout_step;

    return tc;
}
