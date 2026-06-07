#include "tc_mmioin.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>

#define MMIO_OUT_EP DDR3_OUT_EP
#define MMIO_IN_EP  DDR3_IN_EP

#define NUM_ITER        (6)

typedef enum __mmioin_step {
    MMIOCmd,
    MMIODat,
    MMIORes,
    MMIOEnd,
} mmioin_step_t;

typedef struct {
    uint32_t addr;
    uint8_t step;
    uint8_t iter;
    uint8_t out;
    uint8_t in;
    uint8_t id;
} mmioin_state_t;

static const char tc_mmioin_name[] = "BULK MMIO IN";
static const char mmioin_strings[4][16] = {
    {"MMIOCmd"},
    {"MMIODat"},
    {"MMIORes"},
    {"MMIOEnd"},
};
static const int mmioin_lengths[6] = { 4, 8, 16, 20, 12, 24 };


/**
 * MMIO IN transaction-initialisation routine, that first sends a FETCH command,
 * followed by a USB Bulk IN request.
 */
static void tc_mmioin_cmd(usb_host_t* host, int n, const mmioin_state_t* st)
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
    xfer->tx[1] = (uint8_t)(n - 1) | 0x03u; // Length - 1 (AXI4)
    // xfer->tx[1] = 0x03u; // Length := BYTES / 4 - 1
    xfer->tx[2] = st->addr & 0xFF;
    xfer->tx[3] = (st->addr >> 8) & 0xFF;
    xfer->tx[4] = (st->addr >> 16) & 0xFF;
    xfer->tx[5] = ((st->addr >> 24) & 0x0F) | ((st->id & 0x0F) << 4);

    uint16_t crc = crc16_calc(xfer->tx, xfer->tx_len);
    xfer->crc1 = crc & 0xFF;
    xfer->crc2 = (crc >> 8) & 0xFF;
}

static void tc_mmioin_dat(usb_host_t* host, const mmioin_state_t* st)
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

static void tc_mmioin_res(usb_host_t* host, const mmioin_state_t* st)
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

static int tc_mmioin_init(usb_host_t* host, void* data)
{
    mmioin_state_t* st = (mmioin_state_t*)data;
    vpi_printf("\n[%s:%d] %s INIT (cycle = %lu)\n\n", __FILE__, __LINE__,
               tc_mmioin_name, host->cycle);

    st->step = MMIOCmd;
    st->out  = MMIO_OUT_EP;
    st->in   = MMIO_IN_EP;
    tc_mmioin_cmd(host, mmioin_lengths[st->iter], st);
    host->step = 0;

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK IN transaction has
 * been sent/received.
 */
static int tc_mmioin_step(usb_host_t* host, void* data)
{
    mmioin_state_t* st = (mmioin_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = mmioin_strings[st->step];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case MMIOCmd:
        // MMIOCmd completed, so move to MMIODat
        if (++st->iter < NUM_ITER) {
            tc_mmioin_cmd(host, mmioin_lengths[st->iter], st);
            st->step = MMIOCmd;
            return 0;
        }
        tc_mmioin_dat(host, st);
        st->iter = 0;
        st->step = MMIODat;
        return 0;

    case MMIODat:
        // MMIODat completed, so move to MMIOEnd
        xfer->stage = NoXfer;
        if (++st->iter >= NUM_ITER) {
            xfer->type = XferIdle;
            host->op = HostIdle;
            st->step = MMIOEnd;
            return 1;
        }
        tc_mmioin_dat(host, st);
        st->step = MMIODat;
        return 0;

    case MMIORes:
        // Fetch each of the MMIO 'STORE' responses
        if (++st->iter < NUM_ITER) {
            tc_mmioin_res(host, st);
            st->step = MMIORes;
            return 0;
        }
        host->op = HostIdle;
        xfer->type = XferIdle;
        xfer->stage = NoXfer;
        st->step = MMIOEnd;
        return 1;

    case MMIOEnd:
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

testcase_t* test_mmioin(const uint32_t addr)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    mmioin_state_t* st = malloc(sizeof(mmioin_state_t));
    st->step = MMIOCmd;
    st->iter = 0;
    st->out  = MMIO_OUT_EP;
    st->in   = MMIO_IN_EP;
    st->id   = rand() & 0x0F;
    st->addr = addr;

    tc->name = tc_mmioin_name;
    tc->data = (void*)st;
    tc->init = tc_mmioin_init;
    tc->step = tc_mmioin_step;

    return tc;
}
