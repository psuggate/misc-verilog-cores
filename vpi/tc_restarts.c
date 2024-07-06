#include "tc_restarts.h"
#include <stdlib.h>
#include <stdint.h>


/**
 * Test consists of waiting for RST# to go LO, then HI, and for the 'data[7:0]'
 * and 'stp' signals to be zero.
 */
typedef struct {
    int stage;
    int ticks;
} restart_t;

static const char tc_restarts[] = "Link-restart test-case";


int test_restarts_init(ulpi_bus_t* curr, ulpi_phy_t* state, void* data)
{
    // ut_set_phy_idle(state);
    return 0;
}

int test_restarts_step(uint64_t cycle, ulpi_bus_t* curr, ulpi_phy_t* state, void* data)
{
    return 0;
}


/**
 * Verify that the USB link restarts correctly.
 */
testcase_t* test_restarts(void)
{
    restart_t* data = (restart_t*)malloc(sizeof(restart_t));
    testcase_t* test = tc_alloc(tc_restarts, data);
    test->init = test_restarts_init;
    test->step = test_restarts_step;
    return test;
}
