#ifndef __USBHOST_H__
#define __USBHOST_H__


#include "ulpi.h"


typedef struct {
    uint8_t speed;
    ulpi_phy_t phy;
} usb_host_t;


void usbh_init(usb_host_t* host);


#endif  /* __USBHOST_H__ */
