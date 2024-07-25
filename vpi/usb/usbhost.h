#ifndef __USBHOST_H__
#define __USBHOST_H__
/**
 * Simulates a USB host controller, by handling USB transactions.
 * NOTE:
 *  - not cycle-accurate, as it works at the packet-level of abstraction;
 *  - to generate SOF's and EOF's, needs additional structure;
 */

#include "ulpi.h"
#include "stdreq.h"


#define MAX_PACKET_LEN 512
#define MAX_CONFIG_LEN 64

#define XACT_CONF_OUT 1
#define XACT_CONF_IN  2
#define XACT_BULK_OUT 3
#define XACT_BULK_IN  4


typedef enum {
    HostError = -1,
    HostReset = 0,
    HostSuspend,
    HostResume,
    HostIdle,
    HostSOF,
    HostSETUP,
    HostBulkOUT,
    HostBulkIN,
} operation_t;

typedef struct __usb_packet {
    uint16_t len;
    uint8_t pid;
    uint8_t body[MAX_PACKET_LEN];
} usb_packet_t;

typedef struct {
    float error_rate;
} host_mode_t;

typedef struct {
    uint64_t cycle;
    operation_t op;
    uint32_t step;
    transfer_t xfer;
    // ulpi_phy_t phy;
    uint16_t sof;
    uint16_t turnaround;
    uint8_t addr;
    uint8_t speed;
    uint8_t error_count;
    uint16_t* len;
    uint8_t* buf;
} usb_host_t;

typedef int (*step_fn_t)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);


typedef struct {
    /*
    int (*setup)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*data0)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*data1)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    int (*status)(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
    */
    step_fn_t setup;
    step_fn_t data0;
    step_fn_t data1;
    step_fn_t status;
} stdreq_steps_t;


typedef struct {
    uint8_t addr;
    uint8_t ep;
    uint16_t len;
    uint8_t* dat;
} usb_bulk_t;

/*
typedef struct {
    int type;
    union __payload {
	usb_stdreq_t* conf;
	usb_bulk_t* bulk;
    } payload;
} usb_xact_t;
*/


void usbh_init(usb_host_t* host);
int usbh_step(usb_host_t* host, const ulpi_bus_t* in, ulpi_bus_t* out);
int usbh_busy(usb_host_t* host);

// int usbh_send(usb_host_t* host, usb_xact_t* xact);
int usbh_recv(usb_host_t* host, usb_packet_t* packet);
int usbh_next(usb_host_t* host, usb_packet_t* packet);

int usbh_get_descriptor(usb_host_t* host, uint16_t num, uint8_t* buf, uint16_t* len);

void stdreq_init(stdreq_steps_t* steps);


#endif  /* __USBHOST_H__ */
