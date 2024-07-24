#include "usbfunc.h"


/**
 * Issue a device reset.
 */
void usbf_init(usb_func_t* func)
{
    func->cycle = 0ul;
    func->op = HostReset;
    func->step = 0u;
    func->turnaround = 0;
    func->addr = 0;
}

int usbf_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;
    return result;
}
