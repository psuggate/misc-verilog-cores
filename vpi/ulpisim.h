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
    vpiHandle dati;
    vpiHandle dato;
    uint64_t cycle;
    ulpi_bus_t prev;
    ulpi_phy_t phy;
    int sync_flag;
    int test_num;
    int test_curr;
    testcase_t** tests;
} ut_state_t;


static inline int phy_is_driving(ut_state_t* state)
{
    return state->prev.dir == vpi1;
}


#endif  /* __ULPISIM_H__ */
