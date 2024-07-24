#include "usbhost.h"
#include <stdlib.h>
#include <vpi_user.h>


int main(int argc, char* argv[])
{
    usb_host_t* host = (usb_host_t*)malloc(sizeof(usb_host_t));
    ulpi_bus_t bus, upd;

    vpi_printf("Simulating ULPI\n");

    // Issue host-reset
    ulpi_bus_idle(&bus);
    usbh_init(host);

    // Do some transactions
    vpi_printf("Starting ULPI transactions\n");
    usbh_step(host, &bus, &upd);

    // Disconnect device

    // Done
    free(host);
    return 0;
}
