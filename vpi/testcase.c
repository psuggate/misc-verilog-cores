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

#if 0

int tc_init(testcase_t* test, ulpi_phy_t* phy)
{
    if (test->init != NULL && test->step != NULL && test->phy == NULL) {
        test->phy = phy;
        return test->init(test->phy, test->data);
    } else {
        vpi_printf("Invalid initial state for test-case\n");
        vpi_control(vpiFinish, 2);
    }
    return 0;
}

int tc_step(testcase_t* test)
{
    if (test->step != NULL) {
        int result = test->step(test->phy, test->data);
        if (result < 0) {
            // Todo: error-handling
            return -1;
        } else if (result != 0) {
            // Todo: done
            return 1;
        }
    } else {
        vpi_printf("Missing STEP function for test-case\n");
        vpi_control(vpiFinish, 2);
    }

    return 0;
}

/**
 * Run each test in-order, and passing the final-state from each preceding test
 * to the next test in the list, until all tests have been completed (or until
 * an error occurs).
 */
void tc_run(testcase_t* tests[], int num)
{
}


typedef struct {
    int stage;
    int ticks;
} hs_neg_t;

static const char hs_neg[] = "High-speed negotiation";

int test_hs_neg_init(ulpi_phy_t* phy, void* data)
{
    return 0;
}

int test_hs_neg_step(ulpi_phy_t* phy, void* data)
{
    return 0;
}

void test_hs_negotiation(void)
{
    testcase_t* test = malloc(sizeof(testcase_t));
    test->name = hs_neg;
    test->data = NULL;
    test->phy  = NULL;
    test->init = test_hs_neg_init;
    test->step = test_hs_neg_step;
}

#endif /* 0 */
