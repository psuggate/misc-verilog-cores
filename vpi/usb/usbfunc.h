#ifndef __USBFUNC_H__
#define __USBFUNC_H__


#include "usbhost.h"
#include <stdint.h>


typedef enum {
    FuncIdle,
    FuncRecv,
    FuncRXCMD,
    FuncRxPID,
    FuncBusy,
    FuncEOT,
} usbf_state;

typedef struct __usb_func {
    uint64_t cycle;
    host_op_t op;
    uint8_t state;
    uint32_t step;
    transfer_t xfer;
    uint16_t turnaround;
    uint8_t addr;
} usb_func_t;


void usbf_init(usb_func_t* func);
int usbf_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);


void test_func_recv(void);


#endif  /* __USBFUNC_H__ */
