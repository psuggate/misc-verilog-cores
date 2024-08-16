#include "tc_setaddr.h"
#include "usb/stdreq.h"
#include "usb/descriptor.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __setaddr_stage {
    SendSETUP,
    SendDATA0,
    RecvACK0,
    SendIN,
    RecvDATA1,
    SendACK,
    AddrDone,
} setaddr_stage_t;

typedef struct __setaddr_state {
    uint8_t stage;
    uint8_t addr;
} setaddr_state_t;

static const char tc_setaddr_name[] = "SET ADDRESS";
static const char setaddr_strings[7][16] = {
    {"SendSETUP"},
    {"SendDATA0"},
    {"RecvACK0"},
    {"SendIN"},
    {"RecvDATA0"},
    {"SendACK"},
    {"AddrDone"},
};


static int tc_setaddr_init(usb_host_t* host, void* data)
{
    setaddr_state_t* st = (setaddr_state_t*)data;
    transfer_t* xfer = &host->xfer;
    st->stage = SendSETUP;
    int result = stdreq_set_address(host, st->addr);

    vpi_printf("HOST\t#%8lu cyc =>\t%s INIT result = %d\n",
               host->cycle, tc_setaddr_name, result);

    if (result < 0) {
        vpi_printf("[%s:%d] SET ADDRESS initialisation failed\n",
                   __FILE__, __LINE__);
        show_host(host);
        vpi_control(vpiFinish, 2);
        return -1;
    }
    return 0;
}

/**
 * Step-function that is invoked as each packet of a SETUP transaction has been
 * sent/received.
 */
static int tc_setaddr_step(usb_host_t* host, void* data)
{
    setaddr_state_t* st = (setaddr_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = setaddr_strings[st->stage];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (st->stage) {

    // SETUP stage
    case SendSETUP:
        host->xfer.ep_seq[0] = SIG0;
        host->step++;
        st->stage = SendDATA0;
        return 0;

    case SendDATA0:
        host->step++;
        st->stage = RecvACK0;
        return 0;

    case RecvACK0:
        host->addr = st->addr;
        host->xfer.address = st->addr;
        host->step++;
        st->stage = SendIN;
        return 0;

    // STATUS stage
    case SendIN:
        host->xfer.ep_seq[0] = SIG1;
        host->step++;
        st->stage = RecvDATA1;
        return 0;

    case RecvDATA1:
        host->step++;
        st->stage = SendACK;
        return 0;

    case SendACK:
        host->step++;
        host->op = HostIdle;
        st->stage = AddrDone;
        return 1;

    // Finished
    case AddrDone:
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid SET ADDRESS state: 0x%x\n",
                   __FILE__, __LINE__, st->stage);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_setaddr(const uint8_t addr)
{
    if ((addr & 0x7F) != addr) {
        return NULL;
    }

    testcase_t* tc = malloc(sizeof(testcase_t));
    setaddr_state_t* st = malloc(sizeof(setaddr_state_t));
    st->stage = SendSETUP;
    st->addr = addr;

    tc->name = tc_setaddr_name;
    tc->data = (void*)st;
    tc->init = tc_setaddr_init;
    tc->step = tc_setaddr_step;

    return tc;
}
