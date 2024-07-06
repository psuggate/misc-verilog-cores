#ifndef __ULPI_H__
#define __ULPI_H__

#include <vpi_user.h>
#include <stdint.h>


#define MAX_PACKET (512u)
#define MAX_CONFIG (64u)


typedef uint8_t bit_t;

typedef struct {
    uint8_t a;
    uint8_t b;
} byte_t;

typedef struct {
    uint8_t regs[16];
    uint8_t LineState;
    uint8_t Vbus;
    uint8_t RxEvent;
} phy_state_t;

typedef struct {
    bit_t clock;
    bit_t rst_n;
    bit_t dir;
    bit_t stp;
    bit_t nxt;
    byte_t data;
} ulpi_bus_t;

typedef struct {
    uint8_t tx[MAX_PACKET];
    int tx_len;
    int tx_ptr;
    uint8_t rx[MAX_PACKET];
    int rx_len;
    int rx_ptr;
} transfer_t;

typedef struct {
    phy_state_t state;
    ulpi_bus_t bus;
    transfer_t xfer;
} ulpi_phy_t;


int set_phy_reg(uint8_t reg, uint8_t val);
int get_phy_reg(uint8_t reg, uint8_t* val);


#endif  /* __ULPI_H__ */
