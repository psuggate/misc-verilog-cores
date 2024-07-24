#ifndef __USBCRC_H__
#define __USBCRC_H__


#include <stdint.h>


uint16_t crc5_calc(const uint16_t dat);
int crc5_check(uint16_t dat);


#endif  /* __USBCRC_H__ */
