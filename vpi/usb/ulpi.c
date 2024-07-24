#include "ulpi.h"
#include <stdlib.h>
#include <string.h>

//
// Todo:
//  - HS negotiation (pp.39, ULPI_v1_1.pdf)
//  - Reset handling
//  - Suspend and Resume
//


// Initialisation/reset/default values for the ULPI PHY registers.
static const uint8_t ULPI_REG_DEFAULTS[10] = {
    0x24, 0x04, 0x06, 0x00, 0x41, 0x41, 0x41, 0x00, 0x00, 0x00
};


// Todo ...
ulpi_phy_t* phy_init(void)
{
    ulpi_phy_t* phy = (ulpi_phy_t*)malloc(sizeof(ulpi_phy_t));

    memcpy(phy->state.regs, ULPI_REG_DEFAULTS, sizeof(ULPI_REG_DEFAULTS));

    phy->state.rx_cmd = 0x0C;
    phy->state.status = PowerOn;

    phy->bus.clock = SIGX;
    phy->bus.rst_n = SIGX;
    phy->bus.dir = SIGZ;
    phy->bus.nxt = SIGZ;
    phy->bus.stp = SIGX;
    phy->bus.data.a = 0x00;
    phy->bus.data.b = 0xff;

    return phy;
}

void phy_free(ulpi_phy_t* phy)
{
    free(phy);
}


//
//  Helper Routines
///

void ulpi_bus_idle(ulpi_bus_t* bus)
{
    bus->clock = SIG1;
    bus->rst_n = SIG1;
    bus->dir = SIG0;
    bus->nxt = SIG0;
    bus->stp = SIG0;
    bus->data.a = 0x00;
    bus->data.b = 0x00;
}


//
//  Higher-Level Routines
///

/**
 * Todo:
 *  - on pp.22, USB3317C datasheet, register values for each mode;
 */
int phy_set_reg(uint8_t reg, uint8_t val)
{
    return -1;
}

int phy_get_reg(uint8_t reg, uint8_t* val)
{
    return -1;
}
