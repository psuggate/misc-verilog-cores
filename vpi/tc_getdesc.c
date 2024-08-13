#include "tc_getdesc.h"


static const char tc_getdesc_name[] = "GET CONFIG DESCRIPTOR";


static int tc_getdesc_init(usb_host_t* host, void* data)
{
    return -1;
}

static int tc_getdesc_step(usb_host_t* host, void* data)
{
    return -1;
}

new_testcase_t* tc_getdesc_create(void)
{
    new_testcase_t* tc = malloc(sizeof(new_testcase_t));
    tc->name = tc_getdesc_name;
    tc->data = NULL;
    tc->init = tc_getdesc_init;
    tc->step = tc_getdesc_step;
}

void tc_getdesc_destroy(new_testcase_t* tc)
{
    if (tc != NULL) {
        free(tc);
    }
}
