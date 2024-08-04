#ifndef __ULPI_H__
#define __ULPI_H__

#include <stdbool.h>
#include <stdint.h>


#define MAX_PACKET_SIZE (512u)
#define MAX_CONFIG_SIZE (64u)

// Todoos
#define MODE_HIGH_SPEED 2
#define MODE_FULL_SPEED 1
#define MODE_LOW_SPEED  0
#define MODE_SUSPEND    4

// Inter-packet delays
#define DELAY_HOST_TX_TX_MIN 11
#define DELAY_HOST_TX_TX_MAX 24
#define DELAY_PERI_RX_RX_MIN 4
#define DELAY_LINK_RX_TX_MIN 1
#define DELAY_LINK_RX_TX_MAX 24

// Timeout delays
#define DELAY_HOST_TX_RX_MIN 92
#define DELAY_HOST_TX_RX_MAX 102

// Signal/logic levels
#define SIG0 0
#define SIG1 1
#define SIGZ 2
#define SIGX 3


/**
 * VPI scalar value, 0-5.
 */
typedef uint8_t bit_t;

/**
 * Uses the same ('aval', 'bval') encoding as VPI vectors (but only 8b).
 */
typedef struct {
    uint8_t a;
    uint8_t b;
} byte_t;


//
//  RX CMD definitions
///

#define LINE_STATE_MASK 0x03
#define VBUS_STATE_MASK 0x0C
#define RX_EVENT_MASK   0x30
#define RX_ACTIVE_BITS  0x10

#define USBPID_OUT      0b0001
#define USBPID_IN       0b1001
#define USBPID_SOF      0b0101
#define USBPID_SETUP    0b1101
#define USBPID_DATA0    0b0011
#define USBPID_DATA1    0b1011
#define USBPID_DATA2    0b0111
#define USBPID_MDATA    0b1111
#define USBPID_ACK      0b0010
#define USBPID_NAK      0b1010
#define USBPID_STALL    0b1110
#define USBPID_NYET     0b0110
#define USBPID_PRE      0b1100
#define USBPID_ERR      0b1100
#define USBPID_SPLIT    0b1000
#define USBPID_PING     0b0100
#define USBPID_RESERVED 0b0000

typedef uint8_t RX_CMD_t;


/**
 * ULPI PHY register map.
 */
typedef enum {
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
typedef enum {
    Disconnected = -3,
    ErrorResetB = -2,
    Undefined = -1,
    PowerOn = 0,
    RefClkValid,
    Starting,
    WaitForIdle,
    StatusRXCMD,
    PhyIdle,
    PhyRecv,
    PhySend,
    PhySuspend,
    PhyResume,
    PhyChirpJ,
    PhyChirpK,
    HostChirp
} __phy_status_t;

typedef struct {
    uint8_t regs[10];
    RX_CMD_t rx_cmd;
    int8_t status;
} phy_state_t;

typedef struct {
    bit_t clock;
    bit_t rst_n;
    bit_t dir;
    bit_t stp;
    bit_t nxt;
    byte_t data;
} ulpi_bus_t;

typedef enum {
    XferIdle,
    NOPID, // Link to ULPI PHY
    RegWrite,
    RegRead,
    SETUP, // Host to Link
    OUT,
    IN,
    SOF,
    PING,
    DnDATA0,
    DnDATA1,
    DnACK,
    UpACK, // Link to Host
    UpNYET,
    UpNAK,
    UpSTALL,
    UpDATA0,
    UpDATA1,
} xfer_type_t;

typedef enum {
    NoXfer,
    AssertDir, // 1
    InitRXCMD, // 2
    TokenPID,  // 3
    Token1,
    Token2,
    HskPID,    // 6
    HskStop,   // 7
    DATAxPID,  // 8
    DATAxBody,
    DATAxCRC1,
    DATAxCRC2,
    DATAxStop,
    EndRXCMD,
    EOP,
    REGW,
    REGR,
    // REGA,
    REGD,
} xfer_stage_t;

typedef struct {
    uint8_t address;
    uint8_t endpoint;
    uint8_t type;
    uint8_t stage;
    bit_t ep_seq[16];
    uint32_t cycle;
    uint8_t tx[MAX_PACKET_SIZE];
    int tx_len;
    int tx_ptr;
    uint8_t rx[MAX_PACKET_SIZE];
    int rx_len;
    int rx_ptr;
} transfer_t;

typedef struct {
    phy_state_t state;
    ulpi_bus_t bus;
    transfer_t xfer;
} ulpi_phy_t;


// typedef int (*step_fn_t)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
typedef int (*step_fn_t)(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out);


static inline void phy_drive_rx_cmd(ulpi_phy_t* phy)
{
    phy->bus.dir = SIG1;
    phy->bus.nxt = SIG0;
    phy->bus.data.a = phy->state.rx_cmd;
    phy->bus.data.b = 0x00;
}

static inline void phy_bus_release(ulpi_bus_t* bus)
{
    bus->dir = SIG0;
    bus->nxt = SIG0;
    bus->data.a = 0x00;
    bus->data.b = 0xff;
}

static inline bool check_pid(const ulpi_bus_t* bus)
{
    if (bus->data.b != 0x00) {
	return false;
    }
    uint8_t u = (bus->data.a >> 4) ^ 0x0f;
    return u == (bus->data.a & 0x0f);
}

static inline bool check_seq(const transfer_t* xfer, const uint8_t pid)
{
    bool seq =
	pid == USBPID_DATA0 && xfer->ep_seq[xfer->endpoint & 0x0f] == 0 ||
	pid == USBPID_DATA1 && xfer->ep_seq[xfer->endpoint & 0x0f] == 1;
    return seq;
}

void ulpi_bus_idle(ulpi_bus_t* bus);

ulpi_phy_t* phy_init(void);

int phy_set_reg(uint8_t reg, uint8_t val);
int phy_get_reg(uint8_t reg, uint8_t* val);


#endif  /* __ULPI_H__ */
