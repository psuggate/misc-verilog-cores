#ifndef __STDREQ_H__
#define __STDREQ_H__


#include "usbhost.h"


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


int set_configuration(uint16_t wValue);
int get_descriptor(uint16_t type, uint16_t lang, usb_desc_t);


#endif  /* __STDREQ_H__ */
