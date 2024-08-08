#include "usbfunc.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>


static int fn_token_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_datax_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_datax_send_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);

static int fn_send_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);
static int fn_recv_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out);


//
//  Helper Routines and Data
///

static char hstates[9][8] = {
    {"Error"}, {"Reset"}, {"Suspend"}, {"Resume"}, {"Idle"},
    {"SOF"}, {"SETUP"}, {"BulkOUT"}, {"BulkIN"}
};

static char fstates[6][8] = {
    {"IDLE"}, {"RECV"}, {"RXCMD"}, {"RxPID"}, {"BUSY"}, {"EOT"}
};

static void func_show(usb_func_t* func)
{
    printf("State\t = %d\t(%s)\n", func->state, fstates[func->state]);
    printf("OP   \t = %d\t(%s)\n", func->op, hstates[func->op - HostError]);
    printf("Step \t = %d\n", func->step);
    printf("Timer\t = %d\n", func->turnaround);
}

static int ulpi_bus_rx(const ulpi_bus_t* in) {
    if (in->dir != SIG1 || in->data.b != 0x00) {
        return -1;
    } else if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
        return 0;
    } else if (in->nxt == SIG1) {
        return 1;
    }
    return -1;
}

static int fn_token_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG1 && func->xfer.stage < Token2) {
        printf("Unexpected early termination of packet-receive\n");
        return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));
    int rx = ulpi_bus_rx(in);

    switch (func->xfer.stage) {
    case AssertDir:
        // If 'NXT' is asserted, then we are receiving a packet, else invalid
        // ULPI bus signals
        if (in->nxt == SIG1) {
            func->xfer.stage = InitRXCMD;
            return 0;
        }
        break;

    case InitRXCMD:
        if (in->nxt == SIG1 && check_pid(in)) {
            switch (in->data.a & 0x0f) {
            case USBPID_OUT:
            case USBPID_IN:
            case USBPID_SETUP:
            case USBPID_SOF:
                func->xfer.stage = TokenPID;
                return 0;
            default:
                printf("Token PID expected\n");
                break;
            }
        }
        break;

    case TokenPID:
        if (rx < 0) {
            break;
        } else if (rx > 0) {
            func->xfer.stage = Token1;
        }
        return 0;

    case Token1:
        if (rx < 0) {
            break;
        } else if (rx > 0) {
            func->xfer.tok1 = in->data.a;
            func->xfer.stage = Token2;
        }
        return 0;

    case Token2:
        if (rx < 0) {
            break;
        } else if (rx > 0) {
            func->xfer.tok2 = in->data.a;
            func->xfer.stage = EndRXCMD;
        }
        return 0;

    case EndRXCMD:
        if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) != RX_ACTIVE_BITS) {
            func->xfer.stage = EOP;
            return 0;
        }
        break;

    case EOP:
        if (in->nxt == SIG0) {
            func->step++;
            return 1;
        }
        return 0;

    default:
        break;
    }

    printf("Token-step failed\n");
    return -1;
}

static int fn_datax_recv_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG1 && func->xfer.stage < EndRXCMD) {
        printf("Unexpected early termination of packet-receive\n");
        return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {

    case NoXfer:
        if (in->dir != SIG1) {
            // Todo: use a turn-around timer, instead of the above termination-
            //   condition !?
            func->turnaround++;
            return 0;
        } else if (in->dir == SIG1 && in->nxt == SIG1) {
            func->xfer.stage = AssertDir;
            return 0;
        }
        break;

    case AssertDir:
        // If 'NXT' is asserted, then we are receiving a packet, else invalid
        // ULPI bus signals
        if (in->nxt == SIG0 && (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
            func->xfer.stage = InitRXCMD;
            return 0;
        }
        break;

    case InitRXCMD:
        if (in->nxt == SIG1 && check_pid(in)) {
            if (check_seq(&func->xfer, in->data.a & 0x0f)) {
                func->xfer.stage = DATAxPID;
                func->xfer.rx_ptr = 0;
                func->xfer.rx_len = 0;
                return 0;
            }
        }
        printf("DATAx PID expected\n");
        break;

    case DATAxPID:
    case DATAxBody:
        if (in->nxt == SIG1) {
            func->xfer.rx[func->xfer.rx_ptr++] = in->data.a;
            return 0;
        } else if (in->nxt == SIG0) {
            // If 'NXT' deasserts, could be a wait-state, or end-of-packet
            if (in->data.a & RX_EVENT_MASK != RX_ACTIVE_BITS) {
                // Todo: End-of-Packet, so check CRC16
                func->xfer.stage = EndRXCMD;
                func->xfer.rx_len = func->xfer.rx_ptr - 2;
                func->step++;
            }
            return 0;
        }
        printf("Receiving DATAx packet failed\n");
        break;

    case EndRXCMD:
    case EOP:
        func->xfer.type = UpACK;
        return 0;

    default:
        printf("Unexpected DATAx receive-step\n");
        break;
    }

    return -1;
}

static int fn_datax_send_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG0) {
        printf("Packet transmission interrupted\n");
        return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case NoXfer: {
        // Drive ULPI 'Transmit' onto bus
        uint8_t pid = func->xfer.ep_seq[func->xfer.endpoint] == 0 ? ULPITX_DATA0 : ULPITX_DATA1;
        out->data.a = pid;
        out->data.b = 0x00;
        out->stp = SIG0;
        func->xfer.stage = DATAxPID;
        return 0;
    }

    case DATAxPID:
        if (in->nxt == SIG1) {
            if (func->xfer.tx_len > 0) {
                out->data.a = func->xfer.tx[func->xfer.tx_ptr++];
                out->data.b = 0x00;
                out->stp = SIG0;
                func->xfer.stage = DATAxBody;
            } else {
                // Send a ZDP:
                out->data.a = func->xfer.crc1;
                out->data.b = 0x00;
                out->stp = SIG0;
                func->xfer.stage = DATAxCRC1;
            }
        }
        return 0;

    case DATAxBody:
        if (in->nxt == SIG1) {
            if (func->xfer.tx_ptr < func->xfer.tx_len) {
                out->data.a = func->xfer.tx[func->xfer.tx_ptr++];
                out->data.b = 0x00;
                out->stp = SIG0;
            } else {
                out->data.a = func->xfer.crc1;
                out->data.b = 0x00;
                out->stp = SIG0;
                func->xfer.stage = DATAxCRC1;
            }
        }
        return 0;

    case DATAxCRC1:
        if (in->nxt == SIG1) {
            out->data.a = func->xfer.crc2;
            out->data.b = 0x00;
            out->stp = SIG1;
            func->xfer.stage = DATAxCRC2;
        }
        return 0;

    case DATAxCRC2:
        // After 2nd CRC byte has been transferred, set the ULPI bus to idle
        if (in->nxt == SIG1) {
            out->data.a = 0x00;
            out->data.b = 0x00;
            out->stp = SIG0;
            func->xfer.stage = EOP;
        }
        return 0;

    case EOP:
        out->data.a = 0x00;
        out->data.b = 0x00;
        out->stp = SIG0;
        return 0;

    default:
        break;
    }

    return -1;
}

static int fn_recv_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {

    case NoXfer:
        if (ulpi_bus_is_idle(in)) {
            // Wait for 'ACK'
            func->turnaround++;
            return 0;
        } else if (in->dir == SIG1 && in->nxt == SIG1) {
            func->xfer.stage = InitRXCMD;
            return 0;
        }
        printf("Invalid ULPI bus signal levels, while waiting for 'ACK'\n");
        break;

    case AssertDir:
        if (in->dir == SIG1 && in->nxt == SIG0 && in->data.b == 0x00 &&
            (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
            func->xfer.stage = InitRXCMD;
            return 0;
        }

    case InitRXCMD:
        if (in->dir == SIG1 && in->nxt == SIG1 && check_pid(in) &&
            in->data.b == 0x00 && (in->data.a & 0x0F) == USBPID_ACK) {
            func->xfer.stage = HskPID;
            return 0;
        }
        printf("Handshake 'ACK' PID expected\n");
        break;

    case HskPID:
        if (in->dir != SIG0 || in->nxt != SIG0) {
            printf("Expected ULPI bus turn-around\n");
            break;
        }
        func->step++;
        func->xfer.stage = NoXfer;
        return 1;

    default:
        break;
    }

    return -1;
}

static int fn_send_ack_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (in->dir != SIG0) {
        printf("Handshake transmission interrupted\n");
        return -1;
    }
    memcpy(out, in, sizeof(ulpi_bus_t));

    switch (func->xfer.stage) {
    case NoXfer:
        // Drive ULPI 'Transmit' onto bus, with 'ACK' PID
        out->data.a = ULPITX_ACK;
        out->data.b = 0x00;
        out->stp = SIG0;
        func->xfer.stage = HskPID;
        return 0;

    case HskPID:
        // Once the PID has been accepted, assert 'STP'
        if (in->nxt == SIG1) {
            out->data.a = 0x00;
            out->data.b = 0x00;
            out->stp = SIG1;
            func->xfer.stage = HskStop;
        }
        return 0;

    case HskStop:
        // Return ULPI bus to idle
        out->data.a = 0x00;
        out->data.b = 0x00;
        out->stp = SIG0;
        func->xfer.stage = EOP;
        func->step++;
        return 0;

    case EOP:
        // Done
        out->data.a = 0x00;
        out->data.b = 0x00;
        out->stp = SIG0;
        return 0;

    default:
        break;
    }
        
    return -1;
}

static int stdreq_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    return -1;
}

/**
 * Steps through the various phases and packets of a complete transaction.
 */
static int func_xfer_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    if (func->step == 0) {
        // Token step
        return fn_token_recv_step(func, in, out);
    }

    switch (func->op) {

    case HostBulkOUT:
        if (func->step < 2) {
            return fn_datax_recv_step(func, in, out);
        } else if (func->step < 3) {
            return fn_send_ack_step(func, in, out);
        }
        return 1;

    case HostBulkIN:
        if (func->step < 2) {
            return fn_datax_send_step(func, in, out);
        } else if (func->step < 3) {
            return fn_recv_ack_step(func, in, out);
        }
        return 1;

    case HostSETUP:
	if (func->step < 2) {
	    return fn_datax_recv_step(func, in, out);
	} else if (func->step < 3) {
            return fn_recv_ack_step(func, in, out);
	}
        return 1;

    case HostSOF:
        printf("SOF should have already been processed\n");
        break;

    default:
        printf("Invalid host-wait state: %u\n", func->op);
        break;
    }

    return -1;
}


//
//  Public API Routines
///

/**
 * Issue a device reset.
 */
void usbf_init(usb_func_t* func)
{
    func->cycle = 0ul;
    func->op = HostReset;
    func->step = 0u;
    func->turnaround = 0;
    func->addr = 0;
}

/**
 * Step through a complete USB transaction (which is at least 3x packets).
 */
int usbf_step(usb_func_t* func, const ulpi_bus_t* in, ulpi_bus_t* out)
{
    ulpi_bus_show(in);

    if (in->rst_n != SIG1) {
        printf("ULPI PHY has RST# asserted\n");
        return -1;
    } else if (in->clock != SIG1) {
        printf("ULPI PHY must be driven at the positive clock-edge\n");
        return -1;
    }

    switch (func->state) {

    case FuncIdle:
        if (ulpi_bus_is_idle(in)) {
            memcpy(out, in, sizeof(ulpi_bus_t));
            return 0;
        }

        // If 'DIR' asserts then we are waiting for a token, or merely receiving
        // an RX CMD
        if (in->dir == SIG1) {
            if (in->nxt > SIG1) {
                printf("Invalid NXT signal level: %u\n", in->nxt);
            } else {
                func->state = in->nxt == SIG0 ? FuncRXCMD : FuncRecv;
                memcpy(out, in, sizeof(ulpi_bus_t));
                return 0;
            }
        }
        printf("Invalid ULPI bus signal levels\n");
        break;

    case FuncRXCMD:
        if (in->dir == SIG1 && in->nxt == SIG0) {
            // Stay in 'FuncRXCMD' until 'DIR' deasserts
            return 0;
        } else if (in->dir == SIG0) {
            func->state = FuncIdle;
            memcpy(out, in, sizeof(ulpi_bus_t));
            return 0;
        }
        printf("Invalid ULPI bus signal levels\n");
        break;

    case FuncRecv:
        // We are expecting an RX CMD followed by a USB token
        if (in->dir == SIG1 && in->nxt == SIG0 && in->data.b == 0x00 &&
            (in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
            func->state = FuncRxPID;
            memcpy(out, in, sizeof(ulpi_bus_t));
            return 0;
        }
        break;

    case FuncRxPID:
        // When 'NXT' asserts, we have received a USB PID for the packet
        if (in->dir == SIG1) {
            if (in->nxt == SIG1 && check_pid(in)) {
                func->state = FuncBusy;
                func->step = 0u; // We are at the "TOKEN" step
                func->xfer.stage = Token1;

                switch (in->data.a & 0x0F) {
                case USBPID_OUT:
                    func->op = HostBulkOUT;
                    func->xfer.type = OUT;
                    break;

                case USBPID_IN:
                    func->op = HostBulkIN;
                    func->xfer.type = IN;
                    break;

                case USBPID_SETUP:
                    func->op = HostSETUP;
                    func->xfer.type = SETUP;
                    break;

                case USBPID_SOF:
                    func->op = HostSOF;
                    func->xfer.type = SOF;
                    break;

                default:
                    printf("Expecting token\n");
                    return -1;
                }

                memcpy(out, in, sizeof(ulpi_bus_t));
                return 0;
            } else if (in->nxt == SIG0 && in->data.b == 0x00) {
                if ((in->data.a & RX_EVENT_MASK) == RX_ACTIVE_BITS) {
                    // Just another RX CMD
                    memcpy(out, in, sizeof(ulpi_bus_t));
                    return 0;
                }
            }
        }
        printf("Failed to receive a USB packet\n");
        break;

    case FuncBusy:
        return func_xfer_step(func, in, out);

    case FuncEOT:
        if (ulpi_bus_is_idle(in)) {
            // Todo: is this stuff correct ?!
            func->xfer.type = XferIdle;
            func->xfer.stage = NoXfer;
            memcpy(out, in, sizeof(ulpi_bus_t));
            return 1;
        }

    default:
        break;
    }

    return -1;
}


//
//  USB Function Testbench
///

void test_func_recv(void)
{
    ulpi_bus_t bus = {0};
    ulpi_bus_t out;
    int result = 0;
    uint16_t index = 0;
    uint8_t packet[8] = {
        0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x40, 0x00
    };
    transfer_t host = {0};
    usb_func_t func = {0};
    uint8_t pid;

    // Bring the USB bus & device to idle.
    func.op = HostIdle;
    func.state = FuncIdle;
    bus.clock = SIG1;
    bus.rst_n = SIG1;
    assert(usbf_step(&func, &bus, &out) == 0);
    memcpy(&bus, &out, sizeof(ulpi_bus_t));

    // Transmit a 'SETUP' token to the device.
    host.type = SETUP;
    host.tok1 = 0x00;
    host.tok2 = 0x10;

    assert(ulpi_step_with(token_send_step, &host, &bus, (user_fn_t)usbf_step, (void*)(&func)) == 1);
    printf("Token Sent\n");

    // Host-to-device transmission of a DATA0 packet, containing the parameters
    // of the CONTROL request.
    host.type = DnDATA0;
    host.crc1 = 0xDD;
    host.crc2 = 0x94;
    host.tx_len = 8;
    memcpy(&host.tx, &packet, sizeof(packet));
    func_show(&func);

    assert(ulpi_step_with(datax_send_step, &host, &bus, (user_fn_t)usbf_step, (void*)(&func)) == 1);
    printf("DATA0 Sent\n");

#if 0

    bus.dir = SIG1;
    bus.nxt = SIG1;
    bus.data.a = ((uint8_t)(~pid & 0x0f) << 4) | pid;

    func.xfer.type = UpDATA1;
    func.xfer.stage = DATAxPID;
    func.xfer.ep_seq[0] = 1;
    func.xfer.rx_len = 64;

    do {
        result = usbf_step(&func, &bus, &out);
        memcpy(&bus, &out, sizeof(ulpi_bus_t));

        if (func.xfer.stage == DATAxBody) {
            printf(".");
            bus.data.a = packet[index++];
            if (index >= length) {
                bus.stp = SIG1;
            }
        } else {
            bus.stp = SIG0;
        }
    } while (result == 0);

    if (result < 0) {
        printf("\t\tERROR\n");
    } else if (result > 0) {
        printf("\t\tSUCCESS\n");
    } else {
        printf("\t\tHAIL SEITAN\n");
    }

#endif /* 0 */

}
