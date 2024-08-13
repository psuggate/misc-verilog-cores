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


#ifdef __short_timers

#define UPHY_CHIRPK_TIMER 30
#define HOST_CHIRPK_TIMER 5
#define HOST_CHIRPJ_TIMER 5

#else  /* !__short_timers */
#ifdef __long_timers

#define UPHY_CHIRPK_TIMER 60000
#define HOST_CHIRPK_TIMER 3000
#define HOST_CHIRPJ_TIMER 3000

#else  /* !__long_timers */

#define UPHY_CHIRPK_TIMER 60
#define HOST_CHIRPK_TIMER 30
#define HOST_CHIRPJ_TIMER 30

#endif /* !__long_timers */
#endif /* !__short_timers */


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

/**
 * Return 'true' if the ULPI PHY is configured to send & receive chirps.
 */
static bool ulpi_phy_is_chirp(const ulpi_phy_t* phy)
{
    // printf("PHY function-control register: 0x%x\n", phy->state.regs[UPHY_REG_FN_CTRL]);
    return (phy->state.regs[UPHY_REG_FN_CTRL] & 0x1C) == 0x14;
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
	    phy->state.speed = FuncChirpK;
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
    phy->state.rx_cmd = 0x4C;
    phy->state.op = PowerOn;
}


//
//  Higher-Level Routines
///


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

    assert(in->clock == SIG1);

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

    case WaitForIdle:
	if (ulpi_bus_is_idle(in)) {
	    phy->state.op = PhyIdle;
	} else {
	    out->dir = SIG0;
	    out->nxt = SIG0;
	    out->data.a = 0x00;
	    out->data.b = 0xFF;
	}
	break;

    case StatusRXCMD:
	out->dir = SIG1;
	out->nxt = SIG0;
	if (ulpi_phy_is_chirp(phy)) {
	    // Termination disabled, non-NRZI, and not being driven by the USB
	    // host, so line-state is SE0, SE1, or chirp
	    phy->state.rx_cmd &= 0xFC;

	    switch (phy->state.speed) {

	    case FullSpeed:
		phy->state.speed = HostSE0;
		phy->state.timer = 0;
		break;

	    case HostSE0:
		break;

	    case FuncChirpK:
		phy->state.rx_cmd |= 0x01; // K
		break;

	    case HostChirpK1:
	    case HostChirpK2:
	    case HostChirpK3:
		phy->state.rx_cmd |= 0x01; // K
		phy->state.timer = 0;
		break;

	    case HostChirpJ1:
	    case HostChirpJ2:
	    case HostChirpJ3:
		phy->state.rx_cmd |= 0x02; // J
		phy->state.timer = 0;
		break;

	    case HighSpeed:
		// Squelch ??
		phy->state.timer = 0;
		break;

	    default:
		printf("Invalid line speed-state: 0x%x\n", phy->state.speed);
		return -1;
	    }
	}

	out->data.a = phy->state.rx_cmd;
	out->data.b = 0x00;
	phy->state.update = 0;
	phy->state.op = WaitForIdle;
	break;

    case PhyIdle:
	if (ulpi_bus_is_idle(&phy->bus)) {
	    if (in->data.b == 0x00 && in->data.a != 0x00) {
		// Idle -> Busy
		return uphy_txcmd_step(phy, in, out);
	    } else if (!ulpi_bus_is_idle(in)) {
		printf("Unexpected non-TX CMD, while idle: 0x%x\n",
		       ulpi_bus_data_hex(in));
		return -1;
	    } else if (phy->state.update != 0) {
		// Send an RX CMD
		out->dir = SIG1;
		out->data.b = 0xFF;
		phy->state.op = StatusRXCMD;
	    } else if (phy->state.speed > FuncChirpK && phy->state.speed < HighSpeed) {
		// Output K-J-K-J-K-J chirps
		if ((++phy->state.timer) >= HOST_CHIRPK_TIMER) {
		    phy->state.update = 1;
		    phy->state.speed++;
		}
	    }
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
	    out->dir = SIG0;
	    out->nxt = SIG0;
	    // PHY electrical settings may have changed, so schedule an RX CMD
	    phy->state.update = phy->state.regnum == UPHY_REG_FN_CTRL;
	    phy->state.regs[phy->state.regnum] = in->data.a;
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
	// Todo: return '1' ??
	break;

    case PhyChirpK:
	phy->state.timer++;
	if (in->stp == SIG1 && phy->state.timer > UPHY_CHIRPK_TIMER) {
	    out->dir = SIG0;
	    out->nxt = SIG0;
	    phy->state.op = WaitForIdle;
	    phy->state.update = 1;
	    phy->state.speed = HostChirpK1;
	}
	break;

    default:
	printf("Unexpected PHY state: 0x%x (%u)\n", phy->state.op, phy->state.op);
	phy->state.op = Undefined;
	return -1;
    }

    memcpy(&phy->bus, out, sizeof(ulpi_bus_t));
    return phy->state.op == PhyIdle && phy->state.speed == HighSpeed;
}
