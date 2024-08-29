#ifndef __TESTCASE_H__
#define __TESTCASE_H__


#include "ulpivpi.h"
#include "usb/usbhost.h"
#include <stdint.h>


#define BULK_IN_EP 1
// #define BULK_IN_EP 2

#define BULK_OUT_EP 2
// #define BULK_OUT_EP 1


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
} testcase_t;


//
//  Test Setup-/Stop- Phase Routines
///

testcase_t* tc_create(const char* name, void* data);
void tc_finish(testcase_t* test);


//
//  Test Run-Phase Routines
///

int tc_init(testcase_t* test, ulpi_phy_t* phy);
int tc_step(testcase_t* test);


void tc_run(testcase_t* tests[], int num);


#endif  /* __TESTCASE_H__ */
