#ifndef __ULPISIM_H__
#define __ULPISIM_H__


#include <vpi_user.h>
#include <stdint.h>
#include "ulpi.h"
#include "testcase.h"


/**
 * ULPI signals, state, and test-cases.
 */
typedef struct {
    vpiHandle clock;
    vpiHandle rst_n;
    vpiHandle dir;
    vpiHandle nxt;
    vpiHandle stp;
    vpiHandle data;
    uint64_t tick_ns;
    uint64_t t_recip;
    uint64_t cycle;
    ulpi_bus_t prev;
    int test_num;
    int test_curr;
    testcase_t** tests;
} ut_state_t;


#endif  /* __ULPISIM_H__ */
