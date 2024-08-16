#include "tc_waitsof.h"
#include "usb/usbcrc.h"
#include "usb/usbhost.h"

#include <assert.h>
#include <stdlib.h>
#include <vpi_user.h>


typedef enum __waitsof_state {
    WaitIdle,
    WaitDone,
} waitsof_state_t;

static const char tc_waitsof_name[] = "Wait for SOF";
static const char waitsof_strings[2][16] = {
    {"WaitIdle"},
    {"WaitDone"},
};


/**
 * Setup the wait-for-SOF test-case.
 */
static int tc_waitsof_init(usb_host_t* host, void* data)
{
    waitsof_state_t* st = (waitsof_state_t*)data;
    *st = WaitIdle;
    host->step = 0;
    vpi_printf("\n[%s:%d] %s INIT (cycle = %lu)\n\n", __FILE__, __LINE__,
               tc_waitsof_name, host->cycle);

    return 0;
}

/**
 * Step-function that is invoked as each packet of a BULK OUT transaction has
 * been sent/received.
 */
static int tc_waitsof_step(usb_host_t* host, void* data)
{
    waitsof_state_t* st = (waitsof_state_t*)data;
    transfer_t* xfer = &host->xfer;
    const char* str = waitsof_strings[*st];
    vpi_printf("\n[%s:%d] %s\n\n", __FILE__, __LINE__, str);

    switch (*st) {
    case WaitIdle:
        *st = WaitDone;
        return 1;

    case WaitDone:
        // Waiting for SOF test has completed
        vpi_printf("[%s:%d] WARN => Invoked post-completion\n", __FILE__, __LINE__);
        return 1;

    default:
        vpi_printf("[%s:%d] Invalid Wait-for-SOF state: 0x%x\n",
                   __FILE__, __LINE__, *st);
        vpi_control(vpiFinish, 1);
    }

    return -1;
}

testcase_t* test_waitsof(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    waitsof_state_t* st = malloc(sizeof(waitsof_state_t));
    *st = WaitIdle;

    tc->name = tc_waitsof_name;
    tc->data = (void*)st;
    tc->init = tc_waitsof_init;
    tc->step = tc_waitsof_step;

    return tc;
}
