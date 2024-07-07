#include "tc_restarts.h"
#include <stdlib.h>
#include <stdint.h>


typedef enum {
    ErrReset = -1,
    PowerOff = 0,
    RefClock,
    TStart,
    LinkIdle,
    RXCMD,
    Restarted
} __restart_stage_t;

/**
 * Test consists of waiting for RST# to go LO, then HI, and for the 'data[7:0]'
 * and 'stp' signals to be zero.
 */
typedef struct {
    int stage;
    int ticks;
} restart_t;

static const char tc_restarts[] = "Link-restart test-case";


int test_restarts_init(ulpi_phy_t* phy, void* data)
{
    data->stage = PowerOff;
    data->ticks = 0;
    return 0;
}

int test_restarts_step(ulpi_phy_t* phy, void* data)
{
    switch (data->stage) {

    ErrReset: return -1;

    PowerOff:
	if (phy->bus.rst_n == vpi0) {
	    // Todo:
	    //  - reset the PHY registers
	    data->stage = RefClock;
	}
	break;

    RefClock:
	if (phy->bus.rst_n == vpi1) {
	    data->stage = TStart;
	    data->ticks = 0;
	    // Todo: correctly drive the bus to ULPI-idle
	    phy->bus.dir = vpi1;
	    phy->bus.nxt = vpi0;
	    phy->bus.data.a = 0x00;
	    phy->bus.data.b = 0x00;
	} else if (phy->bus.rst_n == vpi0) {
	    vpi_printf("ERROR: RESETB != 0 or 1\n");
	    vpi_control(vpiFinish, 3);
	    data->stage = ErrReset;
	    return -1;
	}
	break;

    TStart:
	if (phy->bus.rst_n == vpi1 && phy->bus.dir == vpi1 && phy->bus.data.a == 0x00 && phy->bus.data.b == 0x00) {
	    if (++data->ticks >= TSTART_TICKS && phy->bus.stp == vpi0) {
		data->stage = LinkIdle;
		data->ticks = 0;
	    }
	} else {
	    vpi_printf("ERROR: Bad TStart bus state\n");
	    vpi_control(vpiFinish, 3);
	    return -1;
	}
	break;

    LinkIdle:
	if (phy->bus.rst_n == vpi1 && phy->bus.dir == vpi0 && phy->bus.data.a == 0x00 && phy->bus.data.b == 0x00 && phy->bus.stp == vpi0) {
	    if (++data->ticks >= LINK_IDLE_TICKS) {
		// Todo:
		//  - assert 'dir'
		data->stage = RXCMD;
		data->ticks = 0;
	    }
	}
	break;

    RXCMD:
	// Todo ...
	break;

    Restarted:
	// Todo ...
	break;

    default:
	// Todo ...
	break;
    }
    return 0;
}


/**
 * Verify that the USB link restarts correctly.
 */
testcase_t* test_restarts(void)
{
    restart_t* data = (restart_t*)malloc(sizeof(restart_t));
    testcase_t* test = tc_create(tc_restarts, data);

    test->init = test_restarts_init;
    test->step = test_restarts_step;

    return test;
}
