#include "ulpiphy.h"
#include "usbhost.h"

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>


#define UPHY_TXCMD_MASK (0xC0u)
#define UPHY_NOPID_BITS (0x00u)
#define UPHY_XMIT_BITS  (0x40u)
#define UPHY_REGW_BITS  (0x80u)
#define UPHY_REGR_BITS  (0xC0u)

#define UPHY_DELAY_2_5_US 150


// Initialisation/reset/default values for the ULPI PHY registers.
static const uint8_t ULPI_REG_DEFAULTS[10] = {
    0x24, 0x04, 0x06, 0x00, 0x41, 0x41, 0x41, 0x00, 0x00, 0x00
};


bool ulpi_phy_is_idle(const ulpi_phy_t* phy)
{
    bool xfer_idle = phy->xfer.type == XferIdle && phy->xfer.stage == NoXfer;
    return phy->state.op == PhyIdle && ulpi_bus_is_idle(&phy->bus) && xfer_idle;
}

bool ulpi_phy_is_reg_read(const ulpi_phy_t* phy, const ulpi_bus_t* in)
{
    // A register read if the previous state was idle, and the ULPI link drives
    // '0b11xx_xxxx' onto the ULPI data bus.
    bool regr = in->rst_n == SIG1 && in->dir == SIG0 && in->data.b == 0x00 &&
	(in->data.a & UPHY_TXCMD_MASK == UPHY_REGR_BITS);
    return ulpi_phy_is_idle(phy) && regr;
}

bool ulpi_phy_is_reg_write(const ulpi_phy_t* phy, const ulpi_bus_t* in)
{
    // A register write if the previous state was idle, and the ULPI link drives
    // '0b10xx_xxxx' onto the ULPI data bus.
    bool regw = in->rst_n == SIG1 && in->dir == SIG0 && in->data.b == 0x00 &&
	(in->data.a & UPHY_TXCMD_MASK == UPHY_REGW_BITS);
    return ulpi_phy_is_idle(phy) && regw;
}

static uint32_t ulpi_bus_data_hex(const ulpi_bus_t* in)
{
    return (uint32_t)in->data.b << 8 | (uint32_t)in->data.a;
}


//
//  Step-Functions for Specific ULPI PHY Operations
///

static int uphy_chirp_kj_step(ulpi_phy_t* phy, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (phy->state.op) {

    case PhyChirpJ:
	phy->state.timer++;
	break;

    case PhyChirpK:
	break;

    default:
	printf("Unexpected PHY state: 0x%x (%u)\n", phy->state.op, phy->state.op);
	break;
    }

    return -1;
}

#define FN_CTRL_XCVR_HIGHSPEED (0x00u)
#define FN_CTRL_XCVR_FULLSPEED (0x01u)
#define FN_CTRL_XCVR_LOWSPEED  (0x02u)
#define FN_CTRL_XCVR_FS_AND_LS (0x03u)

#define FN_CTRL_TERM_DISABLE   (0x00u)

#define FN_CTRL_OPMODE_NORMAL  (0x00u)
#define FN_CTRL_OPMODE_OFF     (0x08u)
#define FN_CTRL_OPMODE_RAW     (0x10u)


static int uphy_txcmd_step(ulpi_phy_t* phy, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    uint8_t txcmd = in->data.a & UPHY_TXCMD_MASK;
    uint8_t regpid = in->data.a & 0x3F;

    assert(in->dir == SIG0 && in->nxt == SIG0);

    switch (txcmd) {

    case UPHY_XMIT_BITS:
	if (regpid == 0x00) {
	    // NOPID (so probably a CHIRPx)
	    phy->state.op = PhyChirpK;
	    phy->state.timer = 0;
	} else {
	    // Todo: needs to be able to get the USB host to step ...
	    phy->state.op = PhySend;
	}
	break;

    case UPHY_REGR_BITS:
	phy->state.regnum = in->data.a & 0x3F;
	phy->state.op = PhyREGR;
	break;

    case UPHY_REGW_BITS:
	phy->state.regnum = in->data.a & 0x3F;
	phy->state.op = PhyREGW;
	break;

    default:
	printf("Invalid TX CMD bits: 0x%x\n", in->data.a);
	return -1;
    }

    out->nxt = SIG1;
    return 0;
}

static void uphy_reset(ulpi_phy_t* phy)
{
    memcpy(phy->state.regs, ULPI_REG_DEFAULTS, sizeof(ULPI_REG_DEFAULTS));
    phy->state.rx_cmd = 0x0C;
    phy->state.op = PowerOn;
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
    uphy_reset(phy);

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

int uphy_step(ulpi_phy_t* phy, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->rst_n == SIG0) {
	phy->state.op = PowerOn;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    const int8_t op = phy->state.op;
    switch (op) {

    case PowerOn:
	if (in->rst_n == SIG0) {
	    uphy_reset(phy);
	    out->dir = SIG0;
	    out->nxt = SIG0;
	    if (in->clock == SIG1 && in->dir == SIG0 && in->nxt == SIG0) {
		phy->state.op = RefClkValid;
	    }
	}
	break;

    case RefClkValid:
	if (in->clock == SIG1 && in->rst_n == SIG1 && in->data.a == 0x00 && in->data.b == 0x00) {
	    phy->state.timer = 0;
	    phy->state.op = Starting;
	}
	break;

    case Starting:
	if (in->clock != SIG1) {
	    break;
	} else if (in->rst_n != SIG1) {
	    phy->state.op = PowerOn;
	} else if (in->data.a == 0x00 && in->data.b == 0x00) {
	    // SE0 for at least 2.5 microseconds
	    if (++phy->state.timer > UPHY_DELAY_2_5_US) {
		phy->state.op = PhyIdle;
	    }
	} else if (ulpi_bus_is_idle(&phy->bus) && in->data.b == 0x00 && in->data.a != 0x00) {
	    // Idle -> Busy
	    // Todo: we only allow REG(R/W) commands, during start-up
	    assert((in->data.a & 0x80) == 0x80);
	    return uphy_txcmd_step(phy, in, out);
	} else {
	    printf("Invalid start-up, SE0 expected for 2.5 us (0x%x)\n",
		   ulpi_bus_data_hex(in));
	    phy->state.op = Undefined;
	    return -1;
	}
	break;

    case PhyIdle:
	if (ulpi_bus_is_idle(&phy->bus) && in->data.b == 0x00 && in->data.a != 0x00) {
	    // Idle -> Busy
	    return uphy_txcmd_step(phy, in, out);
	}
	break;

    case PhyREGW:
	if (in->data.b == 0x00) {
	    out->nxt = SIG1;
	    phy->state.op = PhyREGI;
	} else {
	    printf("Invalid UPLI bus (TXCMD) value: 0x%x\n", ulpi_bus_data_hex(in));
	    phy->state.op = Undefined;
	    return -1;
	}
	break;

    case PhyREGI:
	if (in->data.b == 0x00) {
	    phy->state.regs[phy->state.regnum] = in->data.a;
	    out->dir = SIG0;
	    out->nxt = SIG0;
	    phy->state.op = PhyStop;
	} else {
	    printf("Invalid UPLI bus data: 0x%x\n", ulpi_bus_data_hex(in));
	    phy->state.op = Undefined;
	    return -1;
	}
	break;

    case PhyStop:
	assert(in->dir == SIG0 && in->nxt == SIG0);
	if (in->stp == SIG1) {
	    phy->state.op = PhyIdle;
	} else {
	    printf("Expected link to assert 'stp' (%u)\n", in->stp);
	    phy->state.op = Undefined;
	    return -1;
	}
	break;

    case PhyREGR:
	out->dir = SIG1;
	out->nxt = SIG0;
	out->data.a = 0x00;
	out->data.b = 0xFF;
	phy->state.op = PhyREGZ;
	break;

    case PhyREGZ:
	out->dir = SIG1;
	out->nxt = SIG1;
	out->data.a = phy->state.regs[phy->state.regnum];
	out->data.b = 0x00;
	phy->state.op = PhyREGO;
	break;

    case PhyREGO:
	out->dir = SIG0;
	out->nxt = SIG0;
	out->data.a = 0x00;
	out->data.b = 0xFF;
	phy->state.op = PhyIdle;
	break;

    case PhySend:
    case PhyRecv:
	// These states should be handled by the USB host, as they are not ULPI-
	// PHY specific.
	break;

    default:
	printf("Unexpected PHY state: 0x%x (%u)\n", phy->state.op, phy->state.op);
	phy->state.op = Undefined;
	return -1;
    }

#if 0
    if (phy->state.op != op) {
	printf("PHY state: %u (prev: %u)\n", phy->state.op, op);
    }
#endif

    memcpy(&phy->bus, out, sizeof(ulpi_bus_t));
    return 0;
}
