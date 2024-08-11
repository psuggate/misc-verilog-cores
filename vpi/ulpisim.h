#ifndef __ULPISIM_H__
#define __ULPISIM_H__


#include <stdint.h>

#include "usb/usbhost.h"
#include "ulpivpi.h"
#include "testcase.h"


typedef enum __ulpi_op {
    ULPI_Error = -1,
    ULPI_PowerOn = 0,
    ULPI_Suspend,
    ULPI_Resume,
    ULPI_Reset,
    ULPI_FullSpeed,
    ULPI_HighSpeed,
    ULPI_Idle,
    ULPI_HostToPHY, // RECEIVE
    ULPI_PHYToHost, // TRANSMIT
    ULPI_LinkToPHY, // REGR/REGW/SPECIAL
} ulpi_op_t;


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
    uint64_t tick_ns;
    uint64_t t_recip;
    uint64_t cycle;
    ulpi_bus_t bus;
    ulpi_phy_t phy;
    usb_host_t host;
    int sync_flag;
    int test_num;
    int test_curr;
    testcase_t** tests;
    int8_t op;
} ut_state_t;


static inline int phy_is_driving(ut_state_t* state)
{
    return state->phy.bus.dir == SIG1;
}


#endif  /* __ULPISIM_H__ */
