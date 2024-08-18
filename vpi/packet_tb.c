#include "packet_tb.h"

#include <vpi_user.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>


#define NUM_TESTCASES 64

#define SIG0 vpi0
#define SIG1 vpi1
#define SIGZ vpiZ
#define SIGX vpiX


/**
 * VPI scalar value, 0-5.
 */
typedef uint8_t bit_t;

/**
 * Uses the same ('aval', 'bval') encoding as VPI vectors (but only 8b).
 */
typedef struct {
    uint8_t a;
    uint8_t b;
} byte_t;


typedef struct __fifo_sigs {
    bit_t clock;
    bit_t reset;
    byte_t level;
    bit_t drop;
    bit_t save;
    bit_t redo;
    bit_t next;
    bit_t vld_i;
    bit_t rdy_o;
    bit_t lst_i;
    byte_t dat_i;
    bit_t vld_o;
    bit_t rdy_i;
    bit_t lst_o;
    byte_t dat_o;
} fifo_sigs_t;

/**
 * Represents a single test-case, where a sequence of packets is fetched and/or
 * stored.
 *
 * The 'init(..)' routine sets up the test-data, and queues the initial packet,
 * while the 'step(..)' routine checks the responses, and queues additional
 * packets until the test has completed.
 */
typedef struct {
    const char* name;
    void* data;
    int (*init)(fifo_sigs_t* sigs, void* data);
    int (*step)(fifo_sigs_t* sigs, void* data);
} testcase_t;

typedef struct __pt_state {
    uint64_t tick_ns;
    uint64_t t_recip;
    uint64_t cycle;
    vpiHandle clock;
    vpiHandle reset;
    vpiHandle level;
    vpiHandle drop;
    vpiHandle save;
    vpiHandle redo;
    vpiHandle next;
    vpiHandle vld_i;
    vpiHandle rdy_o;
    vpiHandle lst_i;
    vpiHandle dat_i;
    vpiHandle vld_o;
    vpiHandle rdy_i;
    vpiHandle lst_o;
    vpiHandle dat_o;
    int sync_flag;
    int test_num;
    int test_curr;
    int test_step;
    testcase_t** tests;
    fifo_sigs_t prev;
    fifo_sigs_t sigs;
} pt_state_t;


static char err_mesg[2048] = {0};


static int pt_error(const char* reason);
static int pt_failed(const char* mesg, const int line, pt_state_t* state);
static int pt_get_signal(vpiHandle* dst, vpiHandle iter);
static void pt_fetch_values(pt_state_t* state);
static void pt_update_values(pt_state_t* state, fifo_sigs_t* next);
static int pt_step(pt_state_t* state, fifo_sigs_t* next);


void show_pt_state(pt_state_t* state);


/**
 * Abort simulation and emit the error-reason.
 */
static int pt_error(const char* reason)
{
    vpi_printf("ERROR: $packet_tb %s\n", reason);
    vpi_control(vpiFinish, 1);
    return 0;
}

static int pt_failed(const char* mesg, const int line, pt_state_t* state)
{
    vpi_printf("\t@%8lu ns  =>\tTest-case: %s failed\n", state->tick_ns, mesg);
    show_pt_state(state);
    sprintf(err_mesg, "[%s:%d] Test-case: %s failed\n", __FILE__, line, mesg);
    pt_error(err_mesg);

    return -1;
}

/**
 * Extract the current bus values using the VPI handles to each bus signal.
 */
static void pt_fetch_values(pt_state_t* state)
{
    s_vpi_value curr_value;

    curr_value.format = vpiScalarVal;
    vpi_get_value(state->clock, &curr_value);
    state->sigs.clock = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->reset, &curr_value);
    state->sigs.reset = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->level, &curr_value);
    state->sigs.level.a = (uint8_t)curr_value.value.vector->aval;
    state->sigs.level.b = (uint8_t)curr_value.value.vector->bval;

    curr_value.format = vpiScalarVal;
    vpi_get_value(state->drop, &curr_value);
    state->sigs.drop = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->save, &curr_value);
    state->sigs.save = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->redo, &curr_value);
    state->sigs.redo = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->next, &curr_value);
    state->sigs.next = (bit_t)curr_value.value.scalar;

    // Packet 'store' AXI4 stream input
    vpi_get_value(state->vld_i, &curr_value);
    state->sigs.vld_i = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->rdy_o, &curr_value);
    state->sigs.rdy_o = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->lst_i, &curr_value);
    state->sigs.lst_i = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->dat_i, &curr_value);
    state->sigs.dat_i.a = (uint8_t)curr_value.value.vector->aval;
    state->sigs.dat_i.b = (uint8_t)curr_value.value.vector->bval;

    // Packet 'fetch' AXI4 stream output
    curr_value.format = vpiScalarVal;
    vpi_get_value(state->vld_o, &curr_value);
    state->sigs.vld_o = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->rdy_i, &curr_value);
    state->sigs.rdy_i = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->lst_o, &curr_value);
    state->sigs.lst_o = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->dat_o, &curr_value);
    state->sigs.dat_o.a = (uint8_t)curr_value.value.vector->aval;
    state->sigs.dat_o.b = (uint8_t)curr_value.value.vector->bval;
}

static void pt_update_values(pt_state_t* state, fifo_sigs_t* next)
{
    s_vpi_value sig;
    s_vpi_time now;
    const fifo_sigs_t* curr = &state->sigs;

    sig.format = vpiScalarVal;
    now.type = vpiSimTime;
    vpi_get_time(NULL, &now);

    if (curr->rdy_o != next->rdy_o) {
        sig.value.scalar = next->rdy_o;
        vpi_put_value(state->rdy_o, &sig, NULL, vpiNoDelay);
    }

    if (curr->vld_o != next->vld_o) {
        sig.value.scalar = next->vld_o;
        vpi_put_value(state->vld_o, &sig, NULL, vpiNoDelay);
    }

    if (curr->lst_o != next->lst_o) {
        sig.value.scalar = next->lst_o;
        vpi_put_value(state->lst_o, &sig, NULL, vpiNoDelay);
    }

    if (curr->level.a != next->level.a || curr->level.b != next->level.b) {
        s_vpi_vecval vec = {next->level.a, next->level.b};
        sig.format = vpiVectorVal;
        sig.value.vector = &vec;
        vpi_put_value(state->level, &sig, NULL, vpiNoDelay);
    }

    if (curr->dat_o.a != next->dat_o.a || curr->dat_o.b != next->dat_o.b) {
        s_vpi_vecval vec = {next->dat_o.a, next->dat_o.b};
        sig.format = vpiVectorVal;
        sig.value.vector = &vec;
        vpi_put_value(state->dat_o, &sig, NULL, vpiNoDelay);
    }

    memcpy(&state->sigs, next, sizeof(fifo_sigs_t));
}

//
// Todo: keep progressing through the test-cases ...
//
static int pt_step(pt_state_t* state, fifo_sigs_t* next)
{
    uint64_t cycle = state->cycle++;
    const fifo_sigs_t* prev = &state->prev;
    const fifo_sigs_t* curr = &state->sigs;
    bool changed = memcmp(prev, curr, sizeof(fifo_sigs_t)) != 0;
    int result;

    if (state->test_curr < state->test_num) {
        testcase_t* test = state->tests[state->test_curr];
        int result;

        if (state->test_step++ == 0) {
            result = test->init(next, test->data);
            if (result < 0) {
                return pt_failed("INIT", __LINE__, state);
            }
        } else {
            result = test->step(next, test->data);
            if (result < 0) {
                return pt_failed("STEP", __LINE__, state);
            }
        }

        if (result > 0) {
            // Test finished, advance to the next, if possible
            vpi_printf("TB\t#%8lu cyc =>\t%s completed [%s:%d]\n", cycle,
                       test->name, __FILE__, __LINE__);
            state->test_step = 0;
            state->test_curr++;
            return result;
        }
    } else {
        // No more tests remaining
        vpi_printf("PT\t#%8lu cyc =>\tAll testbenches completed [%s:%d]\n",
                   cycle, __FILE__, __LINE__);
        return 2;
    }

    changed |=
        memcmp(curr, next, sizeof(fifo_sigs_t)) != 0 ||
        memcmp(prev, next, sizeof(fifo_sigs_t)) != 0;

    if (changed) {
        vpi_printf("\t@%8lu ns  =>\t", state->tick_ns);
        // fifo_sigs_show(next);
    }

    return 0;
}

void show_pt_state(pt_state_t* state)
{
    vpi_printf("PT_STATE = {\n");
    vpi_printf("  tick_ns: %lu,\n", state->tick_ns);
    vpi_printf("  t_recip: %lu,\n", state->t_recip);
    vpi_printf("  cycle: %lu,\n", state->cycle);
    vpi_printf("  sync_flag: %d,\n", state->sync_flag);
    vpi_printf("  test_curr: %d,\n", state->test_curr);
    vpi_printf("  test_step: %d,\n", state->test_step);
    vpi_printf("  tests[%d]: <%p>\n};\n", state->test_num, state->tests);
}

/**
 * Process the bus signal values, and update the state & signals, as required.
 */
static int cb_step_sync(p_cb_data cb_data)
{
    fifo_sigs_t next;
    pt_state_t* state = (pt_state_t*)cb_data->user_data;

    if (state == NULL) {
        pt_error("'*state' problem");
    }

    memcpy(&next, &state->sigs, sizeof(fifo_sigs_t));

    int result = pt_step(state, &next);
    if (result < 0) {
        vpi_printf("Oh noes [%s:%d]\n", __FILE__, __LINE__);
    } else if (result > 0) {
        vpi_printf("Done [%s:%d]\n", __FILE__, __LINE__);
    }

    pt_update_values(state, &next);
    state->sync_flag = 0;

    return 0;
}

/**
 * Event-handler for every posedge-clock event.
 */
static int cb_step_clock(p_cb_data cb_data)
{
    pt_state_t* state = (pt_state_t*)cb_data->user_data;
    if (state == NULL) {
        pt_error("'*state' missing");
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
    pt_fetch_values(state);

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
static int pt_get_signal(vpiHandle* dst, vpiHandle iter)
{
    vpiHandle arg_handle;
    int arg_type;

    arg_handle = vpi_scan(iter);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
        vpi_free_object(iter); /* free iterator memory */
        return pt_error("arg must be a net or reg");
    }
    *dst = arg_handle;
    return 1;
}

/**
 * Populates the state data-structure before the Verilog simulation starts.
 */
static int pt_compiletf(char* user_data)
{
    vpiHandle systf_handle, arg_iterator, arg_handle;
    pt_state_t* state = (pt_state_t*)malloc(sizeof(pt_state_t));
    memset(state, 0, sizeof(pt_state_t));

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    if (systf_handle == NULL) {
        return pt_error("failed to obtain systf handle");
    }

    /* obtain handles to system task arguments */
    arg_iterator = vpi_iterate(vpiArgument, systf_handle);
    if (arg_iterator == NULL) {
        return pt_error("requires 15 arguments");
    }

    /* check the types of the objects in system task arguments */
    if (!pt_get_signal(&state->clock, arg_iterator) ||
        !pt_get_signal(&state->reset, arg_iterator) ||
        !pt_get_signal(&state->level, arg_iterator) ||
        !pt_get_signal(&state->drop , arg_iterator) ||
        !pt_get_signal(&state->save , arg_iterator) ||
        !pt_get_signal(&state->redo , arg_iterator) ||
        !pt_get_signal(&state->next , arg_iterator) ||
        !pt_get_signal(&state->vld_i, arg_iterator) ||
        !pt_get_signal(&state->rdy_o, arg_iterator) ||
        !pt_get_signal(&state->lst_i, arg_iterator) ||
        !pt_get_signal(&state->dat_i, arg_iterator) ||
        !pt_get_signal(&state->vld_o, arg_iterator) ||
        !pt_get_signal(&state->rdy_i, arg_iterator) ||
        !pt_get_signal(&state->lst_o, arg_iterator) ||
        !pt_get_signal(&state->dat_o, arg_iterator)) {
        return 0;
    }

    /* check that there are no more system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    if (arg_handle != NULL) {
        vpi_free_object(arg_iterator); /* free iterator memory */
        return pt_error("can only have 6 arguments");
    }

    if (vpi_get(vpiSize, state->dat_i) != 8) {
        return pt_error("FIFO 'dat_i' must be an 8-bit net");
    }

    if (vpi_get(vpiSize, state->dat_o) != 8) {
        return pt_error("FIFO 'dat_o' must be an 8-bit net");
    }

    state->cycle = 0;
    state->sync_flag = 0;
    state->test_curr = 0;
    state->test_step = 0;
    int i = 0;
    state->tests = (testcase_t**)malloc(sizeof(testcase_t*) * NUM_TESTCASES);
    state->test_num = i;

    // Todo: populate the set of tests ...

    vpi_put_userdata(systf_handle, (void*)state);

    return 0;
}

/**
 * Callback for the packet FIFO testbench.
 */
static int pt_calltf(char* user_data)
{
    vpiHandle systf_handle;
    s_vpi_value x;
    s_vpi_time t;
    s_cb_data cb;
    vpiHandle cb_handle;
    pt_state_t* state;

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    /* check the user-data */
    state = (pt_state_t*)vpi_get_userdata(systf_handle);
    if (state == NULL) {
        return pt_error("'*state' problem");
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

void pt_register(void)
{
    s_vpi_systf_data tf_data;

    tf_data.type      = vpiSysTask;
    tf_data.tfname    = "$packet_tb";
    tf_data.calltf    = pt_calltf;
    tf_data.compiletf = pt_compiletf;
    tf_data.sizetf    = NULL;
    tf_data.user_data = NULL;

    vpi_register_systf(&tf_data);
}

/*
void (*vlog_startup_routines[])() = {
    pt_register,
    0,
};
*/
