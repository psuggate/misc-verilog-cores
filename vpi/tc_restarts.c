#include "tc_restarts.h"
#include "usb/ulpi.h"

#include <stdlib.h>
#include <stdint.h>


#define RESETB_TICKS    60
#define TSTART_TICKS    61800
#define LINK_IDLE_TICKS 1


/**
 * Various stages during Power-On Reset (POR), for a ULPI PHY.
 */
typedef enum {
    ErrReset = -1,
    PowerOff = 0,
    RefClock,
    TStart,
    LinkIdle,
    RXCMD,
    Restarted,
    Completed
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


//
//  Helpers
///

static inline int data_is_idle(ulpi_bus_t* bus)
{
    return (bus->data.a == 0x00 && bus->data.b == 0x00);
}

static inline int phy_is_driving(ulpi_bus_t* bus)
{
    return (bus->rst_n == vpi1 && bus->dir == vpi1);
}

static inline int link_is_idle(ulpi_bus_t* bus)
{
    return (bus->rst_n == vpi1 && bus->dir == vpi0 &&
            bus->nxt == vpi0 && bus->stp == vpi0 && data_is_idle(bus));
}


//
//  Simulation Routines
///

static int tc_restarts_init(usb_host_t* host, void* data)
{
    restart_t* por = (restart_t*)data;
    por->stage = PowerOff;
    por->ticks = 0;
    return 0;
}

static int tc_restarts_step(usb_host_t* host, void* data)
{
    restart_t* por = (restart_t*)data;
    ulpi_bus_t* bus = &host->prev;

    switch (por->stage) {

    case ErrReset: return -1;

    case PowerOff:
        if (bus->rst_n == vpi0) {
            // Todo:
            //  - reset the PHY registers
            por->stage = RefClock;
        }
        break;

    case RefClock:
        if (bus->rst_n == vpi1) {
            por->stage = TStart;
            por->ticks = 0;
            // Todo: correctly drive the bus to ULPI-idle
            bus->dir = vpi1;
            bus->nxt = vpi0;
            bus->data.a = 0x00;
            bus->data.b = 0x00;
        } else if (bus->rst_n != vpi0) {
            vpi_printf("ERROR: RESETB != 0 or 1\n");
            vpi_control(vpiFinish, 3);
            por->stage = ErrReset;
            return -1;
        } else {
            por->ticks++;
        }
        break;

    case TStart:
        if (phy_is_driving(bus) && data_is_idle(bus)) {
            if (++por->ticks >= TSTART_TICKS && bus->stp == vpi0) {
                por->stage = LinkIdle;
                por->ticks = 0;
                phy_bus_release(bus);
            }
        } else {
            vpi_printf("ERROR: Bad TStart bus state\n");
            vpi_control(vpiFinish, 3);
            return -1;
        }
        break;

    case LinkIdle:
        if (link_is_idle(bus)) {
            if (++por->ticks >= LINK_IDLE_TICKS) {
                // Todo:
                //  - assert 'dir'
                por->stage = RXCMD;
                por->ticks = 0;
                bus->dir = vpi1;
            }
        }
        break;

    case RXCMD:
        // phy_drive_rx_cmd(phy);
        por->stage = Restarted;
        por->ticks = 0;
        break;

    case Restarted:
        phy_bus_release(bus);
        por->stage = Completed;
        por->ticks = 0;
        break;

    case Completed:
        return 1;

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

    test->init = tc_restarts_init;
    test->step = tc_restarts_step;

    return test;
}
