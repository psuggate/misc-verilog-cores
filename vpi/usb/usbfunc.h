#ifndef __USBFUNC_H__
#define __USBFUNC_H__


#include "usbhost.h"
#include <stdint.h>


typedef struct __usb_func {
    uint64_t cycle;
    operation_t op;
    uint32_t step;
    uint16_t turnaround;
    uint8_t addr;
} usb_func_t;


void usbf_init(usb_func_t* func);
int usbf_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);



#endif  /* __USBFUNC_H__ */
