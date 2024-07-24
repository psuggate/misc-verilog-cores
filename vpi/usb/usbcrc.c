#include "usbcrc.h"
#include <stdio.h>


#define CRC5_START 0x1F
#define CRC5_POLYN 0x05

#define CRC5_START_REFLECTED 0xF800
#define CRC5_POLYN_REFLECTED 0x14


static uint8_t reflect8(uint8_t x)
{
    uint8_t y = 0;
    for (int j=8; j--;) {
	y |= (x & 0x01) << j;
	x >>= 1;
    }
    return y;
}

/**
 * The CRC5 value is calculated for the lower 11-bits of 'dat', and the output
 * is the concatenated result of the 11-bit payload and 5-bit CRC value.
 */
uint16_t crc5_calc(const uint16_t dat)
{
    uint16_t crc = CRC5_START_REFLECTED | (dat & 0x07FF);
    for (int j = 11; j--;) {
	crc = (crc >> 1) ^ (((crc ^ (crc << 11)) & 0x0800) * CRC5_POLYN_REFLECTED);
    }
    return (dat & 0x07FF) | ((~crc) & 0xF800);
}

int crc5_check(uint16_t dat)
{
    uint8_t crc = CRC5_START;
    for (int j = 16; j--;) {
	crc = (crc << 1) ^ (((dat ^ (crc >> 4)) & 0x01) * CRC5_POLYN);
	dat >>= 1;
    }
    return (crc & 0x1F) == 0x0C;
}
