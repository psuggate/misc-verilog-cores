#ifndef __TC_GETDESC_H__
#define __TC_GETDESC_H__

#include "testcase.h"
#include "usb/usbhost.h"


/**
 * Represents a single test-case, where a sequence of packets is sent to the
 * USB (ULPI, peripheral) device.
 *
 * The 'init(..)' routine sets up the test-data, and queues the initial packet,
 * while the 'step(..)' routine checks the responses, and queues additional
 * packets until the test has completed.
 */
typedef struct {
    const char* name;
    void* data;
    int (*init)(usb_host_t* host, void* data);
    int (*step)(usb_host_t* host, void* data);
} new_testcase_t;


new_testcase_t* tc_getdesc_create(void);
void tc_getdesc_destroy(new_testcase_t* tc);


#endif  /* __TC_GETDESC_H__ */
