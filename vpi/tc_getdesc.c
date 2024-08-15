#include "tc_getdesc.h"
#include "usb/descriptor.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __getdesc_state {
    SendSETUP,
    SendDATA0,
    RecvACK0,
    SendIN,
    RecvDATA1,
    SendACK,
    SendOUT,
    SendZDP,
    RecvACK1,
    DescDone,
} getdesc_state_t;

static const char tc_getdesc_name[] = "GET CONFIG DESCRIPTOR";
static const char getdesc_strings[10][16] = {
    {"SendSETUP"},
    {"SendDATA0"},
    {"RecvACK0"},
    {"SendIN"},
    {"RecvDATA0"},
    {"SendACK"},
    {"SendOUT"},
    {"SendZDP"},
    {"RecvACK1"},
    {"DescDone"},
};


static int tc_getdesc_init(usb_host_t* host, void* data)
{
    getdesc_state_t* st = (getdesc_state_t*)data;
    transfer_t* xfer = &host->xfer;
    *st = SendSETUP;
    int result = usbh_get_descriptor(host, 0x0100);
    vpi_printf("HOST\t#%8lu cyc =>\t%s INIT result = %d\n",
               host->cycle, tc_getdesc_name, result);
    if (result < 0) {
        vpi_printf("[%s:%d] GET DESCRIPTOR initialisation failed\n",
		   __FILE__, __LINE__);
	show_host(host);
        vpi_control(vpiFinish, 2);
        return -1;
    }
    // assert(usbh_get_descriptor(host, 0x0100) == 0);
    // vpi_printf("GET DESCRIPTOR initialised\n");
    // show_stdreq((usb_stdreq_t*)&host->xfer.tx);
    return 0;
}

static int tc_getdesc_step(usb_host_t* host, void* data)
{
    getdesc_state_t* st = (getdesc_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = getdesc_strings[*st];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (*st) {
    case SendSETUP:
        // SendSETUP completed, so now send DATA0
	host->step++;
	*st = SendDATA0;
        // vpi_printf("Potatoe, tomatoe\n");
        // vpi_control(vpiFinish, 2);
        // if (host->op == HostIdle && xfer->type == XferIdle) {
        // }
        // return -1;
        return 0;

    case SendDATA0:
	host->step++;
	*st = RecvACK0;
	return 0;

    case RecvACK0:
	*st = SendIN;
        return 0;

    case SendIN:
	*st = RecvDATA1;
	return 0;

    case RecvDATA1:
	*st = SendACK;
	return 0;

    case SendACK:
	*st = SendOUT;
	return 0;

    case SendOUT:
	*st = SendZDP;
	return 0;

    case SendZDP:
	*st = RecvACK1;
	return 0;

    case RecvACK1:
        show_desc(xfer);
	*st = DescDone;
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid GET DESCRIPTOR state: 0x%x\n",
		   __FILE__, __LINE__, *st);
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
