#ifndef __TESTCASE_H__
#define __TESTCASE_H__


#include "ulpi.h"
#include <stdint.h>


typedef struct {
    const char* name;
    void* data;
    ulpi_phy_t* state;
    uint64_t cycle;
    int (*init)(ulpi_bus_t* curr, ulpi_phy_t* state, void* data);
    int (*step)(uint64_t cycle, ulpi_bus_t* curr, ulpi_phy_t* state, void* data);
} testcase_t;


testcase_t* tc_alloc(const char* name, void* data);
void tc_free(testcase_t* test);
int tc_init(testcase_t* test, ulpi_bus_t* curr);
int tc_step(testcase_t* test, ulpi_bus_t* curr);


void tc_run(testcase_t* tests[], int num);


#endif  /* __TESTCASE_H__ */
