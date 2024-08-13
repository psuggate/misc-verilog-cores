#include "tc_getdesc.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __getdesc_state {
    SendSETUP,
    SendDATA0,
    RecvACK0,
    SendIN,
    RecvDATA0,
    SendACK,
    SendOUT,
    SendZDP,
    RecvACK1,
} getdesc_state_t;

static const char tc_getdesc_name[] = "GET CONFIG DESCRIPTOR";


static int tc_getdesc_init(usb_host_t* host, void* data)
{
    getdesc_state_t* st = (getdesc_state_t*)data;
    transfer_t* xfer = &host->xfer;
    *st = SendSETUP;
    int result = usbh_get_descriptor(host, 0x0100);
    vpi_printf("HOST\t#%8lu cyc =>\t%s INIT result = %d\n",
               host->cycle, tc_getdesc_name, result);
    if (result < 0) {
        vpi_printf("GET DESCRIPTOR initialisation failed\n");
        vpi_control(vpiFinish, 2);
        return -1;
    }
    // assert(usbh_get_descriptor(host, 0x0100) == 0);
    vpi_printf("GET DESCRIPTOR initialised\n");
    return 0;
}

static int tc_getdesc_step(usb_host_t* host, void* data)
{
    getdesc_state_t* st = (getdesc_state_t*)data;
    transfer_t* xfer = &host->xfer;

    switch (*st) {
    case SendSETUP:
        // SendSETUP completed, so now send DATA0
        vpi_printf("Potatoe, tomatoe\n");
        vpi_control(vpiFinish, 2);
        // if (host->op == HostIdle && xfer->type == XferIdle) {
        // }
        return -1;

    case RecvACK1:
        show_desc(xfer->rx, xfer->rx_len);
        return 1;

    default:
        vpi_printf("Invalid GET DESCRIPTOR state: 0x%x\n", *st);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_getdesc(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    getdesc_state_t* st = malloc(sizeof(getdesc_state_t));
    *st = SendSETUP;

    tc->name = tc_getdesc_name;
    tc->data = (void*)st;
    tc->init = tc_getdesc_init;
    tc->step = tc_getdesc_step;

    return tc;
}
