#include "ulpi.h"
#include "testcase.h"
#include <vpi_user.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>


/**
 * ULPI signals, state, and test-cases.
 */
typedef struct {
    vpiHandle clock;
    vpiHandle rst_n;
    vpiHandle dir;
    vpiHandle nxt;
    vpiHandle stp;
    vpiHandle data;
    uint64_t tick_ns;
    uint64_t t_recip;
    uint64_t cycle;
    ulpi_bus_t prev;
    int test_num;
    int test_curr;
    testcase_t* tests;
} ut_state_t;


/**
 * Abort simulation and emit the error-reason.
 */
static int ut_error(const char* reason)
{
    vpi_printf("ERROR: $ulpi_step %s\n", reason);
    vpi_control(vpiFinish, 1);
    return 0;
}

/**
 * Extract the current bus values using the VPI handles to each bus signal.
 */
static void ut_store_bus(ut_state_t* state, ulpi_bus_t* bus)
{
    s_vpi_value curr_value;
    curr_value.format = vpiScalarVal;

    vpi_get_value(state->clock, &curr_value);
    bus->clock = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->rst_n, &curr_value);
    bus->rst_n = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->dir, &curr_value);
    bus->dir = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->nxt, &curr_value);
    bus->nxt = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->stp, &curr_value);
    bus->stp = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->data, &curr_value);
    bus->data.a = (uint8_t)curr_value.value.vector->aval;
    bus->data.b = (uint8_t)curr_value.value.vector->bval;
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
    int arg_type;
    ut_state_t* state = (ut_state_t*)malloc(sizeof(ut_state_t));

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    if (systf_handle == NULL)
	return ut_error("failed to obtain systf handle");

    /* obtain handles to system task arguments */
    arg_iterator = vpi_iterate(vpiArgument, systf_handle);
    if (arg_iterator == NULL)
	return ut_error("requires 6 arguments");

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->clock = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->rst_n = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->dir = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->nxt = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->stp = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("arg must be a net or reg");
    }
    state->data = arg_handle;

    /* check that there are no more system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    if (arg_handle != NULL) {
	vpi_free_object(arg_iterator); /* free iterator memory */
	return ut_error("can only have 6 arguments");
    }

    /* track time in nanoseconds */
    // uint32_t t_unit = vpi_get(vpiTimeUnit, NULL);
    uint32_t t_prec = vpi_get(vpiTimePrecision, NULL);
    state->t_recip = 1;
    int scale = -9 - t_prec;
    while (scale-- > 0) {
	state->t_recip *= 10;
    }
    state->cycle = 0;
    state->test_curr = 0;

    // Todo: populate the set of tests ...

    vpi_put_userdata(systf_handle, (void*)state);

    return 0;
}

static int ut_calltf(char* user_data)
{
    vpiHandle systf_handle, arg_iterator, net_handle, time_handle;
    s_vpi_value value;
    ut_state_t* state;
    s_vpi_time time;
    ulpi_bus_t curr;

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    /* check the user-data */
    state = (ut_state_t*)vpi_get_userdata(systf_handle);
    if (state == NULL)
	ut_error("'*state' problem");

    /* get the simulation-time (in nanoseconds) */
    time.type = vpiSimTime;
    vpi_get_time(NULL, &time);
    uint64_t tick_ns = ((uint64_t)time.high << 32) | (uint64_t)time.low;
    tick_ns /= state->t_recip;
    state->tick_ns = tick_ns;

    uint64_t cycle = state->cycle++;
    ut_store_bus(state, &curr);

    if (cycle == 0) {
	// Todo: startup things ...
    } else if (curr.dir != state->prev.dir) {
	// Else, step ...
	net_handle = state->data;
	value.format = vpiVectorVal;
	vpi_get_value(net_handle, &value);
	vpi_printf("At: %8lu ns => signal %s has the value (a: %2x, b: %2x)\n",
		   tick_ns,
		   vpi_get_str(vpiFullName, net_handle),
		   value.value.vector[0].aval,
		   value.value.vector[0].bval);
    }

    memcpy(&state->prev, &curr, sizeof(ulpi_bus_t));
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
