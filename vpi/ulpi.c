#include "ulpi.h"
#include <stdlib.h>
#include <string.h>


// Initialisation/reset/default values for the ULPI PHY registers.
static const uint8_t ULPI_REG_DEFAULTS[10] = {
    0x24, 0x04, 0x06, 0x00, 0x41, 0x41, 0x41, 0x00, 0x00, 0x00
};


// Todo ...
ulpi_phy_t* phy_init(void)
{
    ulpi_phy_t* phy = (ulpi_phy_t*)malloc(sizeof(ulpi_phy_t));

    memcpy(phy->state.regs, ULPI_REG_DEFAULTS, sizeof(ULPI_REG_DEFAULTS));

    phy->state.rx_cmd.LineState = 0; // squelch
    phy->state.rx_cmd.VbusState = 3; // VbusValid
    phy->state.rx_cmd.RxEvent = 0;
    phy->state.rx_cmd.ID = 0;
    phy->state.rx_cmd.alt_int = 0;
    phy->state.status = PowerOn;

    phy->bus.clock = vpiX;
    phy->bus.rst_n = vpiX;
    phy->bus.dir = vpiZ;
    phy->bus.nxt = vpiZ;
    phy->bus.stp = vpiX;
    phy->bus.data.a = 0x00;
    phy->bus.data.b = 0xff;

    return phy;
}

void phy_free(ulpi_phy_t* phy)
{
    free(phy);
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
