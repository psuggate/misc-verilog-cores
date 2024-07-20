#ifndef __USBHOST_H__
#define __USBHOST_H__


#include "ulpi.h"


typedef enum {
    HostError = -1,
    HostSuspend = 0,
    HostReset,
    HostIdle,
    HostSETUP,
    HostBulkOUT,
} host_state_t;

typedef struct {
    float error_rate;
} host_mode_t;

typedef struct {
    host_state_t hs;
    // transfer_t* xfer;
    ulpi_phy_t phy;
    uint16_t sof;
    uint16_t turnaround;
    uint8_t addr;
    uint8_t speed;
    uint8_t error_count;
} usb_host_t;


void usbh_init(usb_host_t* host);
int usbh_step(usb_host_t* host, ulpi_bus_t* bus);
int usbh_busy(usb_host_t* host);


#endif  /* __USBHOST_H__ */
