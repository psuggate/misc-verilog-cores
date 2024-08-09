#ifndef __ULPIVPI_H__
#define __ULPIVPI_H__


#include <vpi_user.h>
#include <stdint.h>

#include "usb/ulpi.h"
#include "usb/ulpiphy.h"


void ulpi_bus_idle(ulpi_bus_t* bus);

ulpi_phy_t* phy_init(void);

int phy_set_reg(uint8_t reg, uint8_t val);
int phy_get_reg(uint8_t reg, uint8_t* val);


#endif  /* __ULPIVPI_H__ */
