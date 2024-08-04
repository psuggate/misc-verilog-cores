#include "ulpi.h"
#include "stdreq.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#define ZDP_CRC16_BYTE1 0x00u
#define ZDP_CRC16_BYTE2 0x00u


// Global, default configuration-request step-functions
stdreq_steps_t stdreqs;


static int stdreq_setup_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_data0_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_data1_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

static int stdreq_status_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    int result = -1;

    switch (xfer->stage) {
    default:
	xfer->stage++;
	printf("H@%8u => ERROR\n", xfer->cycle);
	exit(1);
    }

    return result;
}

void stdreq_init(stdreq_steps_t* steps)
{
    steps->setup = stdreq_setup_step;
    steps->data0 = stdreq_data0_step;
    steps->data1 = stdreq_data1_step;
    steps->status = stdreq_status_step;
}

/**
 * Configure a USB device to use the given 'addr'.
 */
int usbh_set_address(transfer_t* xfer, uint8_t addr)
{
    return -1;
}

/**
 * Set the device to use the indicated configuration.
 */
int usbh_set_config(transfer_t* xfer, uint8_t num)
{
    return -1;
}


int set_configuration(usb_stdreq_t* req, uint16_t wValue)
{
    return -1;
}

int get_descriptor(usb_stdreq_t* req, uint16_t type, uint16_t lang, uint16_t len, usb_desc_t* desc)
{
    req->bmRequestType = 0x80;
    req->bRequest = STDREQ_GET_DESCRIPTOR;
    req->wValue = type;
    req->wIndex = lang;
    req->wLength = len;
    req->data = (uint8_t*)desc;

    return 1;
}


// -- Testbench -- //

int token_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    switch (xfer->type) {
    case SETUP:
    case OUT:
    case IN:
    case SOF:
	switch (xfer->stage) {
	case NoXfer: break;
	case AssertDir: break;
	case TokenPID: break;
	case Token1: break;
	case Token2: break;
	case EndRXCMD: return 1;
	case EOP: return 1;
	default:
	    printf("Not a valid TOKEN stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a TOKEN: %u\n", xfer->type);
	return -1;
    }

    xfer->stage++;
    return 0;
}

static int datax_send_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    uint8_t pid = xfer->type == DnDATA0 ? 0xC3 : 0x4B;

    if (!check_seq(xfer, pid)) {
	printf("Invalid send DATAx operation: %u\n", pid);
	return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (xfer->type) {
    case DnDATA0:
    case DnDATA1:
	switch (xfer->stage) {
	case NoXfer:
	    if (in->data.a != 0x00 || in->stp != SIG0) {
		printf("ULPI bus not idle (data = %x, stp = %u) cannot send DATAx\n",
		       (unsigned)in->data.a << 8 | (unsigned)in->data.b, in->stp);
		return -1;
	    }
	    out->dir = SIG1;
	    out->nxt = SIG1;
	    out->data.a = 0x00;
	    out->data.b = 0xff;
	    xfer->stage = InitRXCMD;
	    break;
	case AssertDir:
	    out->nxt = SIG0;
	    out->data.a = 0x5D; // RX CMD: RxActive = 1
	    out->data.b = 0x00;
	    xfer->stage = InitRXCMD;
	    break;

	case InitRXCMD:
	    // RX CMD was drive onto ULPI bus, now output PID
	    out->nxt = SIG1;
	    out->data.a = pid;
	    out->data.b = 0x00;
	    xfer->stage = DATAxPID;
	    break;

	case DATAxPID:
	    // PID driven onto ULPI bus, now send the DATA
	    out->nxt = SIG1;
	    out->data.b = 0x00;
	    if (xfer->tx_len > 0) {
		out->data.a = xfer->tx[xfer->tx_ptr++];
		xfer->stage = DATAxBody;
	    } else {
		out->data.a = ZDP_CRC16_BYTE1;
		xfer->stage = DATAxCRC1;
	    }
	    break;

	case DATAxBody:
	    // Keep driving data onto ULPI bus, then send the first CRC-byte
	    out->nxt = SIG1;
	    out->data.b = 0x00;
	    if (xfer->tx_ptr < xfer->tx_len) {
		out->data.a = xfer->tx[xfer->tx_ptr++];
		xfer->stage = DATAxBody;
	    } else {
		out->data.a = ZDP_CRC16_BYTE1; // Todo ...
		xfer->stage = DATAxCRC1;
	    }
	    break;

	case DATAxCRC1:
	    out->nxt = SIG1;
	    out->data.a = ZDP_CRC16_BYTE2; // Todo ...
	    out->data.b = 0x00;
	    xfer->stage = DATAxCRC2;
	    break;
	case DATAxCRC2:
	    out->nxt = SIG0;
	    out->data.a = 0x5C; // RX CMD: RxActive = 1
	    out->data.b = 0x00;
	    xfer->stage = EndRXCMD;
	    break;

	case EndRXCMD:
	    out->data.a = 0x4C; // RX CMD: RxActive = 0, LineState = 0
	    out->data.b = 0x00;
	    xfer->stage = EOP;
	    break;

	case EOP:
	    // End-of-Packet, so stop driving the ULPI bus
	    out->dir = SIG0;
	    out->data.a = 0x00;
	    out->data.b = 0xFF;
	    return 1;

	default:
	    printf("Not a valid DATAx stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a DATAx packet: %u\n", xfer->type);
	return -1;
    }

    return 0;
}

static int datax_recv_step(transfer_t* xfer, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (xfer->type) {
    case UpDATA0:
    case UpDATA1:
	switch (xfer->stage) {
	case NoXfer:
	    out->dir = SIG0;
	    if (in->data.a != 0x00) {
		out->nxt = SIG1;
		xfer->stage = DATAxPID;
	    }
	    break;

	case DATAxPID:
	    if (!check_pid(in) || !check_seq(xfer, in->data.a & 0x0f)) {
		printf("Invalid PID value\n");
		return -1;
	    }
	    xfer->stage = DATAxBody;
	    xfer->rx_ptr = 0;
	    break;

	case DATAxBody:
	    if (in->nxt == SIG1) {
		xfer->rx[xfer->rx_ptr++] = in->data.a;
	    }
	    if (in->stp == SIG1) {
		out->nxt = SIG0;
		xfer->stage = DATAxStop;
		xfer->rx_len = xfer->rx_ptr - 2;
	    }
	    break;

	case DATAxStop:
	    // Todo: check CRC
	    xfer->stage = EndRXCMD;
	    break;

	case EndRXCMD:
	case EOP:
	    return 1;

	default:
	    printf("Not a valid DATAx stage: %u\n", xfer->stage);
	    return -1;
	}
	break;
    default:
	printf("Not a DATAx packet: %u\n", xfer->type);
	return -1;
    }

    return 0;
}

static int ulpi_step_with(step_fn_t step_fn, transfer_t* xfer, ulpi_bus_t* bus)
{
    ulpi_bus_t out = {0};
    int result = 0;

    xfer->stage = 0;
    ulpi_bus_idle(bus);

    while (result == 0) {
	result = step_fn(xfer, bus, &out);
	memcpy(bus, &out, sizeof(ulpi_bus_t));
    }

    return result;
}

void transfer_out(transfer_t* xfer, uint8_t addr, uint8_t ep)
{
    xfer->address = addr;
    xfer->endpoint = ep;
    xfer->type = OUT;
    xfer->stage = 0;
    xfer->tx_len = 0;
    xfer->tx_ptr = 0;
}

void transfer_in(transfer_t* xfer, uint8_t addr, uint8_t ep)
{
    xfer->address = addr;
    xfer->endpoint = ep;
    xfer->type = IN;
    xfer->stage = 0;
    xfer->rx_len = 0;
    xfer->rx_ptr = 0;
}


/**
 * Request a descriptor, stepping through and checking all stages.
 */
void test_stdreq_get_desc(uint16_t num)
{
    usb_stdreq_t req = {0};
    usb_desc_t desc = {0};
    transfer_t xfer = {0};
    ulpi_bus_t bus = {0};
    int result;


    // -- Stage 1: SETUP -- //

    // Phase I: send the 'SETUP' token
    // Phase II: send the 'DATA0' packet with the configuration request params
    // Phase III: wait for the 'ACK' (if successful)
    xfer.type = SETUP;
    get_descriptor(&req, num, 0x00, MAX_CONFIG_SIZE, &desc);
    assert(ulpi_step_with(token_send_step, &xfer, &bus) == 1);
    xfer.type = DnDATA0;
    assert(ulpi_step_with(datax_send_step, &xfer, &bus) == 1);
    xfer.ep_seq[0] = SIG1; // 'ACK'


    // -- Stage 2: DATA0/1 IN -- //

    // Phase IV: send the 'IN' token
    // Phase V: wait for the 'DATA1'
    // Phase VI: send 'ACK' handshake if receive was successful
    transfer_in(&xfer, 0, 0);
    assert(ulpi_step_with(token_send_step, &xfer, &bus) == 1);
    xfer.type = UpDATA1;
    assert(ulpi_step_with(datax_recv_step, &xfer, &bus) == 1);
    xfer.ep_seq[0] = SIG0; // 'ACK'


    // -- Stage 3: STATUS OUT -- //

    // Phase VII: send 'OUT' token
    // Phase VIII: send 'DATA1' (ZDP)
    // Phase IX: wait for 'ACK' handshake (if successful)
    transfer_out(&xfer, 0, 0);
    xfer.ep_seq[0] = SIG1; // Required by USB standard
    assert(ulpi_step_with(token_send_step, &xfer, &bus) == 1);
    xfer.type = DnDATA1;
    xfer.tx_len = 0;
    assert(ulpi_step_with(datax_send_step, &xfer, &bus) == 1);
    xfer.ep_seq[0] = SIG0; // 'ACK'

    printf("\t\tSUCCESS\n");
}
