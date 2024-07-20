#include "usbhost.h"


void usbh_init(usb_host_t* host)
{
    // Todo ...
    if (host == NULL) {
	return;
    }

    host->hs = HostReset;
    host->sof = 0;
    host->turnaround = 0;
    host->addr = 0;
    host->speed = 0;
    host->error_count = 0;
}

int usbh_step(usb_host_t* host, ulpi_bus_t* bus)
{
    return 0; 
}

int usbh_busy(usb_host_t* host)
{
    return host->hs != HostIdle;
}


/**
 * Queue-up a device reset, to be issued.
 */
int usbh_reset_device(usb_host_t* host, uint8_t addr)
{
    return -1;
}

/**
 * Request the indicated descriptor, from a device.
 */
int usbh_get_descriptor(usb_host_t* host, uint8_t num, uint8_t* buf, uint16_t* len)
{
    return -1;
}

/**
 * Configure a USB device to use the given 'addr'.
 */
int usbh_set_address(usb_host_t* host, uint8_t addr)
{
    return -1;
}

/**
 * Set the device to use the indicated configuration.
 */
int usbh_set_config(usb_host_t* host, uint8_t num)
{
    return -1;
}

int usbh_bulk_out(usb_host_t* host, uint8_t* data, uint16_t len)
{
    return -1;
}

int usbh_bulk_in(usb_host_t* host, uint8_t* data, uint16_t* len)
{
    return -1;
}
