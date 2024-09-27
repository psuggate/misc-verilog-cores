#include <vpi_user.h>

void ut_register(void);
void pt_register(void);

void (*vlog_startup_routines[])() = {
    ut_register,
    pt_register,
    0,
};
