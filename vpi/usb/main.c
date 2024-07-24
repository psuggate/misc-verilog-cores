#include "usbhost.h"
#include "usbcrc.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static void check_crc5(void)
{
    uint16_t tok;

    tok = crc5_calc(0x710);
    assert(crc5_check(tok));

    tok = crc5_calc(0x715);
    assert(crc5_check(tok));

    tok = crc5_calc(0x53A);
    assert(crc5_check(tok));
}


int main(int argc, char* argv[])
{
    usb_host_t* host = (usb_host_t*)malloc(sizeof(usb_host_t));
    ulpi_bus_t bus, upd;

    check_crc5();
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
