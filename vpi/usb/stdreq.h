#ifndef __STDREQ_H__
#define __STDREQ_H__


#include "usbhost.h"
#include <stdint.h>


#define STDREQ_GET_STATUS        0
#define STDREQ_CLEAR_FEATURE     1
#define STDREQ_SET_FEATURE       3
#define STDREQ_SET_ADDRESS       5
#define STDREQ_GET_DESCRIPTOR    6
#define STDREQ_SET_DESCRIPTOR    7
#define STDREQ_GET_CONFIGURATION 8
#define STDREQ_SET_CONFIGURATION 9
#define STDREQ_GET_INTERFACE     10
#define STDREQ_SET_INTERFACE     11
#define STDREQ_SYNCH_FRAME       12

#define DESC_DEVICE              1
#define DESC_CONFIGURATION       2
#define DESC_STRING              3
#define DESC_INTERFACE           4
#define DESC_ENDPOINT            5
#define DESC_DEVICE_QUALIFIER    6
#define DESC_OTHER_SPEED_CONFIG  7
#define DESC_INTERFACE_POWER     8


/**
 * Represents the contents of a USB "standard request;" e.g., set an active
 * configuration.
 *
 * Note(s):
 *  - these are described in Chapter 9, of the USB 2.0 Specification;
 */
typedef struct {
    uint8_t bmRequestType;
    uint8_t bRequest;
    uint16_t wValue;
    uint16_t wIndex;
    uint16_t wLength;
    uint8_t* data;
} usb_stdreq_t;

typedef struct {
    uint8_t dtype;
    union {
        char* str;
        uint8_t* dat;
    } value;
} usb_desc_t;

#if 0
typedef struct {
    /*
    int (*setup)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*data0)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*data1)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*status)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    */
    step_fn_t setup;
    step_fn_t data0;
    step_fn_t data1;
    step_fn_t status;
} stdreq_steps_t;
#endif /* 0 */


// -- Helper Procedures -- //

int set_configuration(usb_stdreq_t* req, uint16_t wValue);
int get_descriptor(usb_stdreq_t* req, uint16_t type, uint16_t lang, uint16_t len, usb_desc_t* desc);

// -- Main API Routines -- //

// void stdreq_init(stdreq_steps_t* steps);
void stdreq_show(usb_stdreq_t* req);
int stdreq_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);

int stdreq_get_descriptor(usb_host_t* host, uint16_t num);
int stdreq_get_desc_device(usb_host_t* host);
int stdreq_get_desc_config(usb_host_t* host, uint16_t len);

int stdreq_get_status(usb_host_t* host);
int stdreq_set_address(usb_host_t* host, uint8_t addr);
int stdreq_set_config(usb_host_t* host, uint8_t conf);

// -- Unit Tests -- //

void test_stdreq_get_desc(uint16_t num);


#endif  /* __STDREQ_H__ */
