#include "tc_setconf.h"
#include "usb/stdreq.h"
#include "usb/descriptor.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __setconf_stage {
    SendSETUP,
    SendDATA0,
    RecvACK0,
    SendIN,
    RecvDATA1,
    SendACK,
    SetDone,
} set_stage_t;

typedef struct __setconf_state {
    uint8_t stage;
    uint8_t conf;
} setconf_t;

static const char tc_setconf_name[] = "SET CONFIGURATION";
static const char setconf_strings[7][16] = {
    {"SendSETUP"},
    {"SendDATA0"},
    {"RecvACK0"},
    {"SendIN"},
    {"RecvDATA0"},
    {"SendACK"},
    {"SetDone"},
};


static int tc_setconf_init(usb_host_t* host, void* data)
{
    setconf_t* st = (setconf_t*)data;
    transfer_t* xfer = &host->xfer;
    st->stage = SendSETUP;
    int result = stdreq_set_config(host, st->conf);

    vpi_printf("HOST\t#%8lu cyc =>\t%s INIT result = %d\n",
               host->cycle, tc_setconf_name, result);

    if (result < 0) {
        vpi_printf("[%s:%d] SET CONFIGURATION initialisation failed\n",
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
static int tc_setconf_step(usb_host_t* host, void* data)
{
    setconf_t* st = (setconf_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = setconf_strings[st->stage];
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
        st->stage = SetDone;
        return 1;

    // Finished
    case SetDone:
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid SET CONFIGURATION state: 0x%x\n",
                   __FILE__, __LINE__, st->stage);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_setconf(const uint8_t conf)
{
    if (conf != 0x01) { // Todo ??!
        return NULL;
    }

    testcase_t* tc = malloc(sizeof(testcase_t));
    setconf_t* st = malloc(sizeof(setconf_t));
    st->stage = SendSETUP;
    st->conf = conf;

    tc->name = tc_setconf_name;
    tc->data = (void*)st;
    tc->init = tc_setconf_init;
    tc->step = tc_setconf_step;

    return tc;
}
