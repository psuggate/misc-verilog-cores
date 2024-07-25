#ifndef __USBCRC_H__
#define __USBCRC_H__


#include <stdint.h>


uint16_t crc5_calc(const uint16_t dat);
int crc5_check(uint16_t dat);

uint16_t crc16_calc(const uint8_t* ptr, const uint32_t len);
int crc16_check(const uint8_t* ptr, const uint32_t len);


#endif  /* __USBCRC_H__ */
