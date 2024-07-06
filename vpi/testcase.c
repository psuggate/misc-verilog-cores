#include "testcase.h"
#include <stdlib.h>


testcase_t* tc_alloc(const char* name, void* data)
{
    testcase_t* test = malloc(sizeof(testcase_t));

    test->name = name;
    test->data = data;
    test->state = malloc(sizeof(ulpi_phy_t));
    test->cycle = 0;
    test->init = NULL;
    test->step = NULL;

    return test;
}

void tc_free(testcase_t* test)
{
    if (test != NULL) {
	if (test->data != NULL) {
	    free(test->data);
	}
	if (test->state != NULL) {
	    free(test->state);
	}
	free(test);
    }
}

int tc_init(testcase_t* test, ulpi_bus_t* curr)
{
    if (test->init != NULL) {
	return test->init(curr, test->state, test->data);
    }
    return 0;
}

int tc_step(testcase_t* test, ulpi_bus_t* curr)
{
    uint64_t cycle = ++test->cycle;
    ulpi_phy_t* state = test->state;

    if (curr->rst_n != vpi1) {
	// Todo: reset the ULPI PHY ...
	return tc_init(test, curr);
    } else if (test->step != NULL) {
	int result = test->step(cycle, curr, state, test->data);
	if (result < 0) {
	    // Todo: error-handling
	    return -1;
	} else if (result != 0) {
	    // Todo: done
	    return 1;
	}
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

int test_hs_neg_init(ulpi_bus_t* curr, ulpi_phy_t* state, void* data)
{
    return 0;
}

int test_hs_neg_step(uint64_t cycle, ulpi_bus_t* curr, ulpi_phy_t* state, void* data)
{
    return 0;
}

void test_hs_negotiation(void)
{
    testcase_t* test = malloc(sizeof(testcase_t));
    test->name = hs_neg;
    test->data = 0;
    test->state = malloc(sizeof(ulpi_phy_t));
    test->cycle = 0;
    test->init = test_hs_neg_init;
    test->step = test_hs_neg_step;
}
