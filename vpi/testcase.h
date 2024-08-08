#ifndef __TESTCASE_H__
#define __TESTCASE_H__


#include "ulpivpi.h"
#include <stdint.h>


typedef struct {
    const char* name;
    void* data;
    ulpi_phy_t* phy;
    int (*init)(ulpi_phy_t* phy, void* data);
    int (*step)(ulpi_phy_t* phy, void* data);
} testcase_t;

//     int (*step)(ulpi_bus_t* curr, void* data);


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
