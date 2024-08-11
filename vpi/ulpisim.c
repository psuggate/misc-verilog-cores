#include "ulpisim.h"
#include "testcase.h"
#include <stdlib.h>
#include <string.h>

#include "tc_restarts.h"


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

/**
 * Process the bus signal values, and update the state & signals, as required.
 */
static int cb_step_sync(p_cb_data cb_data)
{
    vpiHandle net_handle;
    s_vpi_value x;
    ulpi_phy_t* phy;
    ulpi_bus_t curr, next;
    ut_state_t* state = (ut_state_t*)cb_data->user_data;
    if (state == NULL) {
	ut_error("'*state' problem");
    }

    uint64_t cycle = state->cycle++;
    phy = &state->phy;
    memcpy(&curr, &state->bus, sizeof(ulpi_bus_t));

    x.format = vpiIntVal;
    vpi_get_value(state->rst_n, &x);
    int rst_n = (int)x.value.integer;

    //
    // Todo:
    //  1. handle reset
    //  2. TX CMDs & line-speed negotiation
    //  3. idle line-state
    //  4. start-of-frame & end-of-frame
    //  5. scheduling transactions
    //  6. stepping current transaction to completion
    //

    if (memcmp(&phy->bus, &curr, sizeof(ulpi_bus_t)) != 0) {
	ulpi_bus_show(&curr);
    }

    if (uphy_step(phy, &curr, &next) < 0) {
	return ut_error("ULPI PHY step failed\n");
    }
    if (phy->state.op == PhyRecv || phy->state.op == PhySend) {
	usbh_step(&state->host, &curr, &next);
    }

/*
    if (rst_n == SIG0) {

	if (phy->bus.rst_n != SIG0) {
	    vpi_printf("RST#\n");
	}
	state->cycle = 0;

    } else {

    }
*/

    if (memcmp(&curr, &next, sizeof(ulpi_bus_t)) != 0) {
	ulpi_bus_show(&next);
    }
    ut_update_bus_state(state, &next);

#ifdef __being_weird

    } else if (cycle == 0) {
	//
	// Todo: startup things ...
	//
	int result = -1;
	if (state->test_curr < state->test_num) {
	    testcase_t* test = state->tests[state->test_curr];
	    result = tc_init(test, phy);
	}
	vpi_printf("ZERO: result = %d !!\n", result);
    } else if (phy->xfer.type != XferIdle) {
	//
	// Todo:
	//  - step the current transfer, until complete;
	//  - make sure the bus is back to idle;
	//  - then proceed to the next test-stage;
	//
	vpi_printf("NOT IDLE!\n");
    } else if (state->test_curr < state->test_num) {
	//
	// Todo: keep progressing through the test-cases ...
	//
	testcase_t* test = state->tests[state->test_curr];
	int result = tc_step(test);

	if (result < 0) {
	    // Test failed
	    vpi_printf("At: %8lu => %s STEP failed, result = %d\n",
		       cycle, test->name, result);
	    ut_error("test STEP failed");
	} else if (result > 0) {
	    // Test finished, advance to the next, if possible
	    vpi_printf("At: %8lu => %s completed\n",
		       cycle, test->name);

	    if (++state->test_curr < state->test_num) {
		// Todo: start the next test
		test = state->tests[state->test_curr];
		result = tc_init(test, phy);
		if (result < 0) {
		    vpi_printf("At: %8lu => %s INIT failed, result = %d\n",
			       cycle, test->name, result);
		    ut_error("test INIT failed");
		}
	    } else {
		vpi_printf("At: %8lu => testbench completed\n", cycle);
		vpi_control(vpiFinish, 0);
	    }
	}
    } else if (curr.dir != state->prev.dir) {
	// Else, step ...
	net_handle = state->dati;
	x.format = vpiVectorVal;
	vpi_get_value(net_handle, &x);
	vpi_printf("At: %8lu => signal %s has the value (a: %2x, b: %2x)\n",
		   cycle,
		   vpi_get_str(vpiFullName, net_handle),
		   x.value.vector[0].aval,
		   x.value.vector[0].bval);
	vpi_printf("I AM BEING ABUSED!\n");
    }

    // If the update-step has changed the bus-state, then schedule that change
    ulpi_bus_t* next = &phy->bus;
    ut_update_bus_state(state, next);

#endif /* __being_weird */

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
	// vpi_printf("Clock = %d (cycle: %lu)\n", clock, state->cycle);
	return 0;
    }

    // Capture the bus signals at the time of the clock-edge
    ut_fetch_bus(state);

    // Setup a read/write synchronisation callback, to process the current bus
    // values, and update signals & state.
    s_vpi_time t;
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

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    if (systf_handle == NULL)
	return ut_error("failed to obtain systf handle");

    /* obtain handles to system task arguments */
    arg_iterator = vpi_iterate(vpiArgument, systf_handle);
    if (arg_iterator == NULL)
	return ut_error("requires 7 arguments");

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
    state->test_num = 1;
    state->tests = (testcase_t**)malloc(sizeof(testcase_t*));
    state->tests[0] = test_restarts();

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
