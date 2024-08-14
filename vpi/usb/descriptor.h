#ifndef __DESCRIPTOR_H__
#define __DESCRIPTOR_H__


#include "ulpi.h"


void show_desc(transfer_t* xfer);
int desc_recv(transfer_t* xfer, const ulpi_bus_t* in);
void test_desc_recv(void);


#endif  /* __DESCRIPTOR_H__ */
