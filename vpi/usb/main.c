#include "descriptor.h"
#include "usbfunc.h"
#include "usbhost.h"
#include "usbcrc.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


static void check_crc16(void)
{
    uint8_t* buf = (uint8_t*)malloc(512);
    uint8_t* ptr = buf;

    for (int i = 0; i < 512; i++) {
        buf[i] = rand();
    }

    for (int i = 4; i--;) {
        uint16_t crc = crc16_calc(buf, 56);
        buf[56] = crc & 0x0ff;
        buf[57] = crc >> 8;
        assert(crc16_check(buf, 58));
        buf += 64;
    }

    free(ptr);
}

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

void usb_unit_tests(void)
{
    printf("\nUSB simultor/model start-up unit-tests:\n");
    check_crc5();
    check_crc16();
    test_desc_recv();
    test_func_recv();
    printf("Done\n\n");
}


/**
 * Main entry-point for the USB simulator/model.
 */
int main(int argc, char* argv[])
{
    usb_host_t* host = (usb_host_t*)malloc(sizeof(usb_host_t));
    ulpi_bus_t bus, upd;
    int result;
    uint8_t buf[64];
    uint16_t len = 64;

    usb_unit_tests();

    printf("Simulating ULPI\n");

    // Issue host-reset
    printf("Initialising ...\n");
    ulpi_bus_idle(&bus);
    usbh_init(host);

    // Wait > 1 ms, for RESET period
    // bus.rst_n = SIG0;
    // host->op = HostReset;
    while (host->op == HostReset) {
        result = usbh_step(host, &bus, &upd);
        if (result < 0) {
            printf("ERROR: %d\n", result);
            break;
        }
        memcpy(&bus, &upd, sizeof(ulpi_bus_t));
    }

    // Do some transactions
    printf("Starting ULPI transactions\n");

    printf("Requesting CONFIG DESCRIPTOR\n");
    // result = usbh_get_descriptor(host, 0x01, buf, &len);
    result = usbh_get_descriptor(host, 0x01);
    if (result < 0) {
        printf("ERROR: %d\n", result);
        exit(1);
    }

    while (host->op != HostIdle) {
        result = usbh_step(host, &bus, &upd);
        if (result < 0) {
            printf("ERROR: %d\n", result);
            break;
        }
        memcpy(&bus, &upd, sizeof(ulpi_bus_t));
    }

    // Disconnect device

    // Done
    free(host);
    return 0;
}
