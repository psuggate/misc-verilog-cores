#include "testcase.h"
#include <vpi_user.h>
#include <stdlib.h>


testcase_t* tc_create(const char* name, void* data)
{
    testcase_t* test = malloc(sizeof(testcase_t));

    test->name = name;
    test->data = data;
    test->init = NULL;
    test->step = NULL;

    return test;
}

void tc_finish(testcase_t* test)
{
    if (test != NULL) {
        if (test->data != NULL) {
            free(test->data);
        }
        free(test);
    }
}
