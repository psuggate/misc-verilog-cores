#ifndef __ULPIPHY_H__
#define __ULPIPHY_H__


#include "ulpi.h"
#include <stdlib.h>
#include <string.h>


/**
 * ULPI PHY register map.
 */
typedef enum __ulpi_reg_map {
    VendorIDLow = 0,
    VendorIDHigh,
    ProductIDLow = 2,
    ProductIDHigh,
    FunctionControlWrite = 4,
    FunctionControlSet,
    FunctionControlClear,
    InterfaceControlWrite = 7,
    InterfaceControlSet,
    InterfaceControlClear,
} ulpi_reg_map_t;


#define UPHY_REG_FN_CTRL 4
#define UPHY_REG_IF_CTRL 7


#define XCVR_SELECT_MASK 0x03
#define TERM_SELECT_MASK 0x04
#define OP_MODE_MASK     0x18
#define RESET_MASK       0x20
#define SUSPENDM_MASK    0x40

typedef uint8_t FunctionControl_t;

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


/**
 * Current PHY state/mode.
 */
typedef enum __phy_op {
    Disconnected = -3,
    ErrorResetB = -2,
    Undefined = -1,
    PowerOn = 0,
    RefClkValid,
    Starting,
    WaitForIdle,
    StatusRXCMD,
    PhyIdle,    // 5
    PhyRecv,
    PhySend,
    PhyREGW,    // 8
    PhyREGI,    // 9
    PhyStop,    // 10
    PhyREGR,
    PhyREGZ,
    PhyREGO,
    PhySuspend, // 14
    PhyResume,  // 15
    PhyChirpJ,  // 16
    PhyChirpK,  // 17
    HostChirp
} ulpi_phy_op_t;

typedef enum __line_speed {
    FullSpeed = 0,
    HostSE0,
    FuncChirpK,
    HostChirpK1,
    HostChirpJ1,
    HostChirpK2,
    HostChirpJ2,
    HostChirpK3,
    HostChirpJ3,
    HighSpeed
} line_speed_t;

typedef struct {
    uint32_t timer;
    int8_t op;
    RX_CMD_t rx_cmd;
    uint8_t regs[10];
    uint8_t regnum;
    uint8_t update;
    uint8_t speed;
} phy_state_t;

typedef struct {
    phy_state_t state;
    ulpi_bus_t bus;
    transfer_t xfer;
} ulpi_phy_t;


// -- Helpers -- //

static inline void phy_drive_rx_cmd(ulpi_phy_t* phy)
{
    phy->bus.dir = SIG1;
    phy->bus.nxt = SIG0;
    phy->bus.data.a = phy->state.rx_cmd;
    phy->bus.data.b = 0x00;
}


// -- PHY Settings -- //

ulpi_phy_t* phy_init(void);
void phy_free(ulpi_phy_t* phy);
int uphy_step(ulpi_phy_t* phy, const ulpi_bus_t* in, ulpi_bus_t* out);


#endif  /* __ULPIPHY_H__ */
