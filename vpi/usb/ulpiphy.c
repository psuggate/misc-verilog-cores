#include "ulpiphy.h"
#include <stdbool.h>


#define UPHY_REGR_MASK (0xC0u)
#define UPHY_REGR_BITS (0xC0u)

#define UPHY_REGW_MASK (0xC0u)
#define UPHY_REGW_BITS (0x80u)


// Initialisation/reset/default values for the ULPI PHY registers.
static const uint8_t ULPI_REG_DEFAULTS[10] = {
    0x24, 0x04, 0x06, 0x00, 0x41, 0x41, 0x41, 0x00, 0x00, 0x00
};


bool ulpi_phy_is_idle(const ulpi_phy_t* phy)
{
    bool xfer_idle = phy->xfer.type == XferIdle && phy->xfer.stage == NoXfer;
    return phy->state.status == PhyIdle && ulpi_bus_is_idle(&phy->bus) && xfer_idle;
}

bool ulpi_phy_is_reg_read(const ulpi_phy_t* phy, const ulpi_bus_t* in)
{
    // A register read if the previous state was idle, and the ULPI link drives
    // '0b11xx_xxxx' onto the ULPI data bus.
    bool regr = in->rst_n == SIG1 && in->dir == SIG0 && in->data.b == 0x00 &&
	(in->data.a & UPHY_REGR_MASK == UPHY_REGR_BITS);
    return ulpi_phy_is_idle(phy) && regr;
}

bool ulpi_phy_is_reg_write(const ulpi_phy_t* phy, const ulpi_bus_t* in)
{
    // A register write if the previous state was idle, and the ULPI link drives
    // '0b10xx_xxxx' onto the ULPI data bus.
    bool regw = in->rst_n == SIG1 && in->dir == SIG0 && in->data.b == 0x00 &&
	(in->data.a & UPHY_REGW_MASK == UPHY_REGW_BITS);
    return ulpi_phy_is_idle(phy) && regw;
}


int uphy_step(ulpi_phy_t* phy, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    return -1;
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
