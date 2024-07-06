#include "ulpisim.h"
#include "testcase.h"
#include <stdlib.h>
#include <string.h>


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

static void ut_set_phy_idle(ut_state_t* state)
{
    s_vpi_value sig;
    s_vpi_time now;
    sig.format = vpiScalarVal;
    sig.value.scalar = vpi0;
    vpi_get_time(NULL, &now);
    vpi_put_value(state->dir, &sig, &now, vpiInertialDelay);
    vpi_put_value(state->nxt, &sig, &now, vpiInertialDelay);
}

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

    /* check the types of the objects in system task arguments */
    if (!get_signal(&state->clock, arg_iterator) ||
	!get_signal(&state->rst_n, arg_iterator) ||
	!get_signal(&state->dir  , arg_iterator) ||
	!get_signal(&state->nxt  , arg_iterator) ||
	!get_signal(&state->stp  , arg_iterator) ||
	!get_signal(&state->data , arg_iterator)) {
	return 0;
    }

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

/**
 * Emulates a USB host, USB bus, and the ULPI PHY of a link, and runs tests on
 * the simulated link/device, via ULPI.
 */
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
