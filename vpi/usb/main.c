#include "usbhost.h"
#include <stdio.h>
#include <stdlib.h>


int main(int argc, char* argv[])
{
    usb_host_t* host = (usb_host_t*)malloc(sizeof(usb_host_t));
    ulpi_bus_t bus, upd;

    printf("Simulating ULPI\n");

    // Issue host-reset
    printf("Initialising ...\n");
    ulpi_bus_idle(&bus);
    usbh_init(host);

    // Wait > 1 ms, for RESET period
    // bus.rst_n = SIG0;
    // host->op = HostReset;
    while (host->op == HostReset) {
	usbh_step(host, &bus, &upd);
	memcpy(&bus, &upd, sizeof(ulpi_bus_t));
    }

    // Do some transactions
    printf("Starting ULPI transactions\n");

    // Disconnect device

    // Done
    free(host);
    return 0;
}
