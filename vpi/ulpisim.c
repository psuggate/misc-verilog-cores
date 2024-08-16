#include "ulpisim.h"
#include "testcase.h"
#include "tc_getdesc.h"
#include "tc_bulkout.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>


static const char op_strings[5][16] = {
    {"UT_PowerOn"},
    {"UT_StartUp"},
    {"UT_Idle"},
    {"UT_Test"},
    {"UT_Done"}
};

static char err_mesg[2048] = {0};


/**
 * Abort simulation and emit the error-reason.
 */
static int ut_error(const char* reason)
{
    vpi_printf("ERROR: $ulpi_step %s\n", reason);
    vpi_control(vpiFinish, 1);
    return 0;
}

static int ut_failed(const char* mesg, const int line, ut_state_t* state)
{
    vpi_printf("\t@%8lu ns  =>\tTest-case: %s failed\n", state->tick_ns, mesg);
    show_ut_state(state);
    sprintf(err_mesg, "[%s:%d] Test-case: %s failed\n", __FILE__, line, mesg);
    ut_error(err_mesg);

    return -1;
}

/**
 * Extract the current bus values using the VPI handles to each bus signal.
 */
static void ut_fetch_bus(ut_state_t* state)
{
    s_vpi_value curr_value;
    curr_value.format = vpiScalarVal;

    vpi_get_value(state->clock, &curr_value);
    state->bus.clock = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->rst_n, &curr_value);
    state->bus.rst_n = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->dir, &curr_value);
    state->bus.dir = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->nxt, &curr_value);
    state->bus.nxt = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->stp, &curr_value);
    state->bus.stp = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->dati, &curr_value);
    state->bus.data.a = (uint8_t)curr_value.value.vector->aval;
    state->bus.data.b = (uint8_t)curr_value.value.vector->bval;
}

static void ut_set_phy_idle(ut_state_t* state)
{
    s_vpi_value sig;

    sig.format = vpiScalarVal;
    sig.value.scalar = vpi0;

    vpi_put_value(state->dir, &sig, NULL, vpiNoDelay);
    vpi_put_value(state->nxt, &sig, NULL, vpiNoDelay);
}

static void ut_update_bus_state(ut_state_t* state, ulpi_bus_t* next)
{
    s_vpi_value sig;
    s_vpi_time now;
    const ulpi_bus_t* curr = &state->bus;

    sig.format = vpiScalarVal;
    now.type = vpiSimTime;
    vpi_get_time(NULL, &now);

    if (curr->dir != next->dir) {
        sig.value.scalar = next->dir;
        vpi_put_value(state->dir, &sig, NULL, vpiNoDelay);
    }

    if (curr->nxt != next->nxt) {
        sig.value.scalar = next->nxt;
        vpi_put_value(state->nxt, &sig, NULL, vpiNoDelay);
    }

    if (curr->data.a != next->data.a || curr->data.b != next->data.b) {
        s_vpi_vecval vec = {next->data.a, next->data.b};
        sig.format = vpiVectorVal;
        sig.value.vector = &vec;
        vpi_put_value(state->dato, &sig, NULL, vpiNoDelay);
    }

    memcpy(&state->phy.bus, next, sizeof(ulpi_bus_t));
}

static int ut_step_xfer(ut_state_t* state)
{
    return 0;
}

//
// Todo:
//  1. ~~handle reset~~
//  2. TX CMDs & line-speed negotiation
//  3. idle line-state
//  4. start-of-frame & end-of-frame
//  5. scheduling transactions
//  6. stepping current transaction to completion
//
static int stim_step(ulpi_phy_t* phy, usb_host_t* host, const ulpi_bus_t* curr, ulpi_bus_t* next)
{
    if (phy->state.speed < HighSpeed || phy->state.op != PhyIdle) {
        // Step-function for the ULPI PHY of the USB device/peripheral
        int result = uphy_step(phy, curr, next);
        if (result < 0) {
            return ut_error("ULPI PHY step failed\n");
        } else if (result > 0) {
            host->op = HostIdle;
        }
        host->cycle++;
    } else {
        // Step-function for the USB host, if the PHY 
        vpi_printf(".");
        int result = usbh_step(host, curr, next);
        if (result < 0) {
            vpi_printf("[%s:%d] USB host-step failed: host->op = %x\n\n",
                       __FILE__, __LINE__, host->op);
        }
        return result;
    }

    return 0;
}

//
// Todo: keep progressing through the test-cases ...
//
static int test_step(ut_state_t* state)
{
    uint64_t cycle = state->cycle;

    if (state->test_curr < state->test_num) {
        testcase_t* test = state->tests[state->test_curr];
        usb_host_t* host = &state->host;
        int result;

        if (state->test_step++ == 0) {
            // show_host(host);
            result = test->init(host, test->data);
            if (result < 0) {
                return ut_failed("INIT", __LINE__, state);
            }
        } else {
            result = test->step(host, test->data);
            if (result < 0) {
                return ut_failed("STEP", __LINE__, state);
            }
        }

        if (result > 0) {
            // Test finished, advance to the next, if possible
            vpi_printf("HOST\t#%8lu cyc =>\t%s completed\n", cycle, test->name);
            state->test_step = 0;
            state->test_curr++;
        }
    } else {
        // No more tests remaining
        vpi_printf("HOST\t#%8lu cyc =>\tAll testbenches completed\n", cycle);
        return 1;
    }

    return 0;
}

void show_ut_state(ut_state_t* state)
{
    char* hstr = malloc(4096);
    int len = host_string(&state->host, hstr, 4);
    assert(len < 4096);

    vpi_printf("UT_STATE = {\n");
    vpi_printf("  tick_ns: %lu,\n", state->tick_ns);
    vpi_printf("  t_recip: %lu,\n", state->t_recip);
    vpi_printf("  cycle: %lu,\n", state->cycle);
    vpi_printf("  bus: {\n   %s\n  },\n", ulpi_bus_string(&state->bus));
    vpi_printf("  phy: {\n   xfer: %s,\n", transfer_string(&state->phy.xfer));
    vpi_printf("  },\n  host: {\n%s\n  },\n", hstr);
    vpi_printf("  sync_flag: %d,\n", state->sync_flag);
    vpi_printf("  test_curr: %d,\n", state->test_curr);
    vpi_printf("  test_step: %d,\n", state->test_step);
    vpi_printf("  tests[%d]: <%p>,\n", state->test_num, state->tests);
    vpi_printf("  op: %u (%s)\n};\n", state->op, op_strings[state->op]);

    free(hstr);
}

static int ut_step(ut_state_t* state, ulpi_bus_t* next)
{
    ulpi_phy_t* phy;
    usb_host_t* host;
    uint64_t cycle = state->cycle++;

    phy = &state->phy;
    host = &state->host;

    const ulpi_bus_t* prev = &phy->bus;
    const ulpi_bus_t* curr = &state->bus;
    bool changed = memcmp(prev, curr, sizeof(ulpi_bus_t)) != 0;
    int result;
    memcpy(next, curr, sizeof(ulpi_bus_t));

    switch (state->op) {

    case UT_PowerOn:
        // Wait for the power-on time to elapse
        vpi_printf("[%s:%d] Todo: implement power-on steps\n",
                   __FILE__, __LINE__);
        host->cycle++;
        state->op = UT_StartUp;
        break;

    case UT_StartUp:
        // Negotiate high-speed (bus) mode
        result = stim_step(phy, host, curr, next);
        if (result < 0) {
            char err[80] = {0};
            sprintf(err, "in state: speed = %x, phy->op = %x, host->op = %x,",
                    phy->state.speed, phy->state.op, host->op);
            return ut_failed(err, __LINE__, state);
        } else if (result > 0) {
            vpi_printf(
                "\t@%8lu ns  =>\tPHY/Host high-speed negotiation completed [%s:%d]\n",
                state->tick_ns, __FILE__, __LINE__);
            state->op = UT_Idle;
            // show_host(host);
        }
        break;

    case UT_Idle:
        if (!ulpi_bus_is_idle(curr)) {
            // Wait for the ULPI bus to become idle, first ...
            // show_host(host);
            result = usbh_step(host, curr, next);
        } else {
            // Initiate each of the various test-cases
            // show_host(host);
            result = test_step(state);
        }
        if (result < 0) {
            return ut_failed("", __LINE__, state);
        } else if (result > 0) {
            // Indicate that the test-cases completed successfully
            vpi_printf("\t@%8lu ns  =>\tAll test-cases completed [%s:%d]\n",
                       state->tick_ns, __FILE__, __LINE__);
            // vpi_printf("\t@%8lu ns  =>\tAll test-cases completed\n", state->tick_ns);
            state->op = UT_Done;
        } else {
            state->op = UT_Test;
        }
        break;

    case UT_Test:
        // Step each test-case to resolution
        result = usbh_step(host, curr, next);
        if (result < 0) {
            return ut_failed("USB host-step", __LINE__, state);
        } else if (result > 0) {
            // Proceed to the next test (sub-)step
            vpi_printf("\t@%8lu ns  =>\tTest-case USB host-step completed [%s:%d]\n",
                       state->tick_ns, __FILE__, __LINE__);
            state->op = UT_Idle;
        }
        break;

    case UT_Done:
        // Indicate that the test-cases completed successfully
        // vpi_printf("\t@%8lu ns  =>\tAll test-cases completed [%s:%d]\n",
        //         state->tick_ns, __FILE__, __LINE__);
        return 1;

    default:
        return ut_failed("test-operation invalid,", __LINE__, state);
    }

    changed |=
        memcmp(curr, next, sizeof(ulpi_bus_t)) != 0 ||
        memcmp(prev, next, sizeof(ulpi_bus_t)) != 0;

    if (changed) {
        vpi_printf("\t@%8lu ns  =>\t", state->tick_ns);
        ulpi_bus_show(next);
    }

    return 0;
}

/**
 * Process the bus signal values, and update the state & signals, as required.
 */
static int cb_step_sync(p_cb_data cb_data)
{
    ulpi_bus_t next;
    ut_state_t* state = (ut_state_t*)cb_data->user_data;

    if (state == NULL) {
        ut_error("'*state' problem");
    }

    if (state->op == UT_Done) {
        state->cycle++;
        return 0;
    }

    int result = ut_step(state, &next);
    if (result < 0) {
        vpi_printf("Oh noes\n");
    } else if (result > 0) {
        vpi_printf("Done\n");
    }

    ut_update_bus_state(state, &next);
    state->sync_flag = 0;

    return 0;
}

/**
 * Event-handler for every posedge-clock event.
 */
static int cb_step_clock(p_cb_data cb_data)
{
    ut_state_t* state = (ut_state_t*)cb_data->user_data;
    if (state == NULL) {
        ut_error("'*state' missing");
    }

    // Check to see if posedge of clock
    s_vpi_value x;
    x.format = vpiIntVal;
    vpi_get_value(state->clock, &x);

    int clock = (int)x.value.integer;
    if (clock != 1) {
        return 0;
    }

    s_vpi_time t;
    t.type = vpiSimTime;
    vpi_get_time(NULL, &t);

    uint64_t tick_ns = ((uint64_t)t.high << 32) | (uint64_t)t.low;
    tick_ns /= state->t_recip;
    state->tick_ns = tick_ns;

    // Capture the bus signals at the time of the clock-edge
    ut_fetch_bus(state);

    // Setup a read/write synchronisation callback, to process the current bus
    // values, and update signals & state.
    t.type       = vpiSimTime;
    t.high       = 0;
    t.low        = 0;

    s_cb_data cb;
    cb.reason    = cbReadWriteSynch;
    cb.cb_rtn    = cb_step_sync;
    cb.user_data = (PLI_BYTE8*)state;
    cb.time      = &t;
    cb.value     = NULL;
    cb.obj       = NULL;

    vpiHandle cb_handle = vpi_register_cb(&cb);
    vpi_free_object(cb_handle);
    state->sync_flag = 1;

    return 0;
}

// Helper for parsing the argument-list.
static int get_signal(vpiHandle* dst, vpiHandle iter)
{
    vpiHandle arg_handle;
    int arg_type;

    arg_handle = vpi_scan(iter);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
        vpi_free_object(iter); /* free iterator memory */
        return ut_error("arg must be a net or reg");
    }
    *dst = arg_handle;
    return 1;
}

/**
 * Monitor the ULPI bus signals.
 * Arguments:
 *  - clock    --  PHY-to-link
 *  - rst_n    --  link-to-PHY
 *  - dir      --  PHY-to-link
 *  - nxt      --  PHY-to-link
 *  - stp      --  link-to-PHY
 *  - data[8]  --  bidirectional (and 0 idle)
 */
static int ut_compiletf(char* user_data)
{
    vpiHandle systf_handle, arg_iterator, arg_handle;
    ut_state_t* state = (ut_state_t*)malloc(sizeof(ut_state_t));
    memset(state, 0, sizeof(ut_state_t));

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    if (systf_handle == NULL) {
        return ut_error("failed to obtain systf handle");
    }

    /* obtain handles to system task arguments */
    arg_iterator = vpi_iterate(vpiArgument, systf_handle);
    if (arg_iterator == NULL) {
        return ut_error("requires 7 arguments");
    }

    /* check the types of the objects in system task arguments */
    if (!get_signal(&state->clock, arg_iterator) ||
        !get_signal(&state->rst_n, arg_iterator) ||
        !get_signal(&state->dir  , arg_iterator) ||
        !get_signal(&state->nxt  , arg_iterator) ||
        !get_signal(&state->stp  , arg_iterator) ||
        !get_signal(&state->dati , arg_iterator) ||
        !get_signal(&state->dato , arg_iterator)) {
        return 0;
    }

    /* check that there are no more system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    if (arg_handle != NULL) {
        vpi_free_object(arg_iterator); /* free iterator memory */
        return ut_error("can only have 6 arguments");
    }

    if (vpi_get(vpiType, state->dir) != vpiReg ||
        vpi_get(vpiSize, state->dir) != 1) {
        return ut_error("ULPI 'dir' must be a 1-bit reg");
    }

    if (vpi_get(vpiType, state->nxt) != vpiReg ||
        vpi_get(vpiSize, state->nxt) != 1) {
        return ut_error("ULPI 'nxt' must be a 1-bit reg");
    }

    if (vpi_get(vpiType, state->dati) != vpiNet ||
        vpi_get(vpiSize, state->dati) != 8) {
        return ut_error("ULPI 'dati' must be an 8-bit net");
    }

    if (vpi_get(vpiType, state->dato) != vpiReg ||
        vpi_get(vpiSize, state->dato) != 8) {
        return ut_error("ULPI 'dato' must be an 8-bit reg");
    }

    state->cycle = 0;
    state->sync_flag = 0;
    usbh_init(&state->host);
    state->test_curr = 0;
    state->test_step = 0;
    state->test_num = 2;
    state->tests = (testcase_t**)malloc(sizeof(testcase_t*) * 2);
    state->tests[0] = test_getdesc();
    state->tests[1] = test_bulkout();

    // Todo: populate the set of tests ...

    vpi_put_userdata(systf_handle, (void*)state);

    return 0;
}

/**
 * Emulates a USB host, USB bus, and the ULPI PHY of a link, and runs tests on
 * the simulated link/device, via ULPI.
 */
static int ut_calltf(char* user_data)
{
    vpiHandle systf_handle;
    s_vpi_value x;
    s_vpi_time t;
    s_cb_data cb;
    vpiHandle cb_handle;
    ut_state_t* state;

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    /* check the user-data */
    state = (ut_state_t*)vpi_get_userdata(systf_handle);
    if (state == NULL) {
        return ut_error("'*state' problem");
    }

    /* compute the scaling-factor for displaying the simulation-time */
    int scale = -9 - vpi_get(vpiTimePrecision, NULL);
    uint64_t t_recip = 1;

    while (scale-- > 0) {
        t_recip *= 10;
    }
    state->t_recip = t_recip;

    /* setup the callback for clock-events */
    t.type       = vpiSuppressTime;
    x.format     = vpiSuppressVal;
    cb.reason    = cbValueChange;
    cb.cb_rtn    = cb_step_clock;
    cb.time      = &t;
    cb.value     = &x;
    cb.user_data = (PLI_BYTE8*)state;
    cb.obj       = state->clock;
    cb_handle    = vpi_register_cb(&cb);
    vpi_free_object(cb_handle);

    return 0;
}

void ut_register(void)
{
    s_vpi_systf_data tf_data;

    tf_data.type      = vpiSysTask;
    tf_data.tfname    = "$ulpi_step";
    tf_data.calltf    = ut_calltf;
    tf_data.compiletf = ut_compiletf;
    tf_data.sizetf    = NULL;
    tf_data.user_data = NULL;

    vpi_register_systf(&tf_data);
}

void (*vlog_startup_routines[])() = {
    ut_register,
    0,
};
