#ifndef __ULPIVPI_H__
#define __ULPIVPI_H__


#include <vpi_user.h>
#include <stdint.h>

#include "usb/ulpi.h"


#if 0

typedef struct {
    uint8_t XcvrSelect : 2;
    uint8_t TermSelect : 1;
    uint8_t OpMode : 2;
    uint8_t Reset : 1;
    uint8_t SuspendM : 1;
    uint8_t Reserved : 1;
} FunctionControl_t;

typedef struct {
    uint8_t FsLsSerialMode_6pin : 1;
    uint8_t FsLsSerialMode_3pin : 1;
    uint8_t CarkitMode : 1;
    uint8_t ClockSuspendM : 1;
    uint8_t AutoResume : 1;
    uint8_t IndicatorComplement : 1;
    uint8_t IndicatorPassThru : 1;
    uint8_t InterfaceProtectDisable : 1;
} InterfaceControl_t;

typedef struct {
    uint8_t LineState : 2;
    uint8_t VbusState : 2;
    uint8_t RxEvent : 2;
    uint8_t ID : 1;
    uint8_t alt_int : 1;
} RX_CMD_t;


static inline void phy_drive_rx_cmd(ulpi_phy_t* phy)
{
    phy->bus.dir = vpi1;
    phy->bus.nxt = vpi0;
    uint8_t val = phy->state.rx_cmd.alt_int << 7 | phy->state.rx_cmd.ID << 6 |
	phy->state.rx_cmd.RxEvent << 4 | phy->state.rx_cmd.VbusState << 2 |
	phy->state.rx_cmd.LineState;
    phy->bus.data.a = val;
    phy->bus.data.b = 0x00;
}

static inline void phy_bus_release(ulpi_bus_t* bus)
{
    bus->dir = vpi0;
    bus->nxt = vpi0;
    bus->data.a = 0x00;
    bus->data.b = 0xff;
}

#endif /* 0 */


void ulpi_bus_idle(ulpi_bus_t* bus);

ulpi_phy_t* phy_init(void);

int phy_set_reg(uint8_t reg, uint8_t val);
int phy_get_reg(uint8_t reg, uint8_t* val);


#endif  /* __ULPIVPI_H__ */
