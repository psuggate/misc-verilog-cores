#include "tc_getstrs.h"
#include "usb/stdreq.h"
#include "usb/descriptor.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __getstrs_step {
    SendSETUP,
    SendDATA0,
    RecvACK0,
    SendIN,
    RecvDATA1,
    SendACK,
    SendOUT,
    SendZDP,
    RecvACK1,
    DoneSETUP,
} getstrs_step_t;

typedef struct {
    uint8_t* buf;
    uint32_t len;
    uint8_t step;
    uint8_t stage;
} getstrs_state_t;


static const char tc_getstrs_name[] = "GET STRING DESCRIPTOR";
static const char getstrs_strings[10][16] = {
    {"SendSETUP"},
    {"SendDATA0"},
    {"RecvACK0"},
    {"SendIN"},
    {"RecvDATA0"},
    {"SendACK"},
    {"SendOUT"},
    {"SendZDP"},
    {"RecvACK1"},
    {"DoneSETUP"},
};


static int tc_getstrs_init(usb_host_t* host, void* data)
{
    getstrs_state_t* st = (getstrs_state_t*)data;
    transfer_t* xfer = &host->xfer;
    int result;

    st->buf = NULL;
    st->len = 0;
    st->step = SendSETUP;

    switch (st->stage) {
    case 0:
	result = stdreq_get_descriptor(host, 0x0300);
	break;
    case 1:
	result = stdreq_get_descriptor(host, 0x0301);
	break;
    case 2:
	result = stdreq_get_descriptor(host, 0x0302);
	break;
    case 3:
	result = stdreq_get_descriptor(host, 0x0303);
	break;
    case 4:
	result = stdreq_get_status(host);
	break;
    case 5:
	return 1;
    }

    vpi_printf("HOST\t#%8lu cyc =>\t%s INIT result = %d\n",
               host->cycle, tc_getstrs_name, result);

    if (result < 0) {
        vpi_printf("[%s:%d] GET STRINGS initialisation failed\n",
                   __FILE__, __LINE__);
        show_host(host);
        vpi_control(vpiFinish, 2);
	return result;
    }

    return 0;
}

/**
 * Step-function that is invoked as each packet of a SETUP transaction has been
 * sent/received.
 */
static int tc_getstrs_step(usb_host_t* host, void* data)
{
    getstrs_state_t* st = (getstrs_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = getstrs_strings[st->step];
    vpi_printf("[%s:%d] %s\n", __FILE__, __LINE__, str);

    switch (st->step) {
    case SendSETUP:
        // SendSETUP completed, so now send DATA0
        host->step++;
        st->step = SendDATA0;
        return 0;

    case SendDATA0:
        host->step++;
        st->step = RecvACK0;
        return 0;

    case RecvACK0:
        host->step++;
        host->xfer.ep_seq[0] = SIG1;
        st->step = SendIN;
        return 0;

    case SendIN:
        host->step++;
        st->step = RecvDATA1;
        return 0;

    case RecvDATA1:
        host->step++;
        st->step = SendACK;
        return 0;

    case SendACK:
        host->step++;
        st->step = SendOUT;
        return 0;

    case SendOUT:
        host->step++;
        st->step = SendZDP;
        host->xfer.tx_len = 0;
        host->xfer.type = DnDATA1;
        host->xfer.crc1 = 0x00;
        host->xfer.crc2 = 0x00;
        return 0;

    case SendZDP:
        host->step++;
        st->step = RecvACK1;
        return 0;

    case RecvACK1:
        host->step++;
        host->op = HostIdle;
        show_desc(xfer);
	if (++st->stage < 5) {
	    tc_getstrs_init(host, data);
	    return 0;
	} else {
	    st->step = DoneSETUP;
	    return 1;
	}

    case DoneSETUP:
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid GET STRINGS state: 0x%x\n",
                   __FILE__, __LINE__, st->step);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_getstrs(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    getstrs_state_t* st = malloc(sizeof(getstrs_state_t));

    st->step = SendSETUP;
    st->stage = 0;
    st->len = 0;
    st->buf = malloc(512);

    tc->name = tc_getstrs_name;
    tc->data = (void*)st;
    tc->init = tc_getstrs_init;
    tc->step = tc_getstrs_step;

    return tc;
}
