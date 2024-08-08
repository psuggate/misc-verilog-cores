#include "ulpivpi.h"
#include <vpi_user.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>


/**
 * ULPI signals being monitored.
 */
typedef struct {
    vpiHandle clock;
    vpiHandle rst_n;
    vpiHandle dir;
    vpiHandle nxt;
    vpiHandle stp;
    vpiHandle data;
    int t_unit;
    int t_prec;
    uint64_t t_recip;
    ulpi_bus_t ulpi_prev;
} ulpim_handles_t;

PLI_INT32 ulpim_StartOfSim(p_cb_data cb_data)
{
    vpiHandle systf_handle;
    return 0;
}

static void ulpim_store_bus(ulpim_handles_t* ulpim_data, ulpi_bus_t* bus)
{
    s_vpi_value curr_value;
    curr_value.format = vpiScalarVal;

    vpi_get_value(ulpim_data->clock, &curr_value);
    bus->clock = (bit_t)curr_value.value.scalar;

    vpi_get_value(ulpim_data->rst_n, &curr_value);
    bus->rst_n = (bit_t)curr_value.value.scalar;

    vpi_get_value(ulpim_data->dir, &curr_value);
    bus->dir = (bit_t)curr_value.value.scalar;

    vpi_get_value(ulpim_data->nxt, &curr_value);
    bus->nxt = (bit_t)curr_value.value.scalar;

    vpi_get_value(ulpim_data->stp, &curr_value);
    bus->stp = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(ulpim_data->data, &curr_value);
    bus->data.a = (uint8_t)curr_value.value.vector->aval;
    bus->data.b = (uint8_t)curr_value.value.vector->bval;
}

static int ulpim_set_handles(ulpim_handles_t** data)
{
    vpiHandle systf_handle, arg_iterator, arg_handle;
    int arg_type;
    ulpim_handles_t* ulpim_data = (ulpim_handles_t*)malloc(sizeof(ulpim_handles_t));

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    if (systf_handle == NULL) {
	vpi_printf("ERROR: $ulpi_monitor failed to obtain systf handle\n");
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }

    /* obtain handles to system task arguments */
    arg_iterator = vpi_iterate(vpiArgument, systf_handle);
    if (arg_iterator == NULL) {
	vpi_printf("ERROR: $ulpi_monitor requires 6 arguments\n");
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->clock = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->rst_n = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->dir = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->nxt = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->stp = arg_handle;

    /* check the type of object in system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    arg_type = vpi_get(vpiType, arg_handle);
    if (arg_type != vpiNet && arg_type != vpiReg) {
	vpi_printf("ERROR: $ulpi_monitor arg must be a net or reg\n");
	vpi_free_object(arg_iterator); /* free iterator memory */
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }
    ulpim_data->data = arg_handle;

    /* check that there are no more system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    if (arg_handle != NULL) {
	vpi_printf("ERROR: $ulpi_monitor can only have 6 arguments\n");
	vpi_free_object(arg_iterator);
	vpi_control(vpiFinish, 1); /* abort simulation */
	return 0;
    }

    if (data == NULL) { /* success */
	free(ulpim_data);
	return 0;
    }

    ulpim_data->t_unit = vpi_get(vpiTimeUnit, NULL);
    ulpim_data->t_prec = vpi_get(vpiTimePrecision, NULL);
    ulpim_data->t_recip = 1;
    int scale = -9 - ulpim_data->t_prec;
    while (scale-- > 0) {
	ulpim_data->t_recip *= 10;
    }

    ulpim_store_bus(ulpim_data, &ulpim_data->ulpi_prev);

    vpi_put_userdata(systf_handle, (void*)ulpim_data);
    *data = ulpim_data;

    return 0;
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
static int ulpim_compiletf(char* user_data)
{
    ulpim_handles_t* ulpim_data;
    return ulpim_set_handles(&ulpim_data);
    // return ulpim_set_handles(NULL);
}

static int ulpim_calltf(char* user_data)
{
    vpiHandle systf_handle, arg_iterator, net_handle, time_handle;
    s_vpi_value current_value;
    ulpim_handles_t* ulpim_data;
    s_vpi_time curr_time;
    ulpi_bus_t ulpi_curr;

    /* obtain a handle to the system task instance */
    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    /* check the user-data */
    ulpim_data = (ulpim_handles_t*)vpi_get_userdata(systf_handle);
    if (ulpim_data == NULL) {
	vpi_printf("ERROR: $ulpi_monitor '*ulpim_data' problem\n");
	vpi_control(vpiFinish, 2); /* abort simulation */
    }

#if 0
    curr_time.type = vpiScaledRealTime;
    vpi_get_time(ulpim_data->clock, &curr_time);
    tick_ns = round(curr_time->real);
    exit(1);
#else  /* !0 */
    curr_time.type = vpiSimTime;
    vpi_get_time(NULL, &curr_time);
    uint64_t tick_ns = ((uint64_t)curr_time.high << 32) | (uint64_t)curr_time.low;
    tick_ns /= ulpim_data->t_recip;
#endif /* !0 */

#if 0
    /* read current 'rst_n' value */
    net_handle = ulpim_data->rst_n;
    current_value.format = vpiBinStrVal; /* read value as a string */
    vpi_get_value(net_handle, &current_value);
    vpi_printf("At: %8lu ns => signal %s has the value %s\n",
	       tick_ns,
	       vpi_get_str(vpiFullName, net_handle),
	       current_value.value.str);

    net_handle = ulpim_data->dir;
    current_value.format = vpiScalarVal;
    vpi_get_value(net_handle, &current_value);
    vpi_printf("At: %8lu ns => signal %s has the value %x\n",
	       tick_ns,
	       vpi_get_str(vpiFullName, net_handle),
	       current_value.value.scalar);
#endif /* 0 */

    ulpim_store_bus(ulpim_data, &ulpi_curr);

    if (ulpi_curr.dir != ulpim_data->ulpi_prev.dir) {
	net_handle = ulpim_data->data;
	current_value.format = vpiVectorVal;
	vpi_get_value(net_handle, &current_value);
	vpi_printf("At: %8lu ns => signal %s has the value (a: %2x, b: %2x)\n",
		   tick_ns,
		   vpi_get_str(vpiFullName, net_handle),
		   current_value.value.vector[0].aval,
		   current_value.value.vector[0].bval);
    }
    memcpy(&ulpim_data->ulpi_prev, &ulpi_curr, sizeof(ulpi_bus_t));

    return 0;
}

void ulpim_register(void)
{
    s_vpi_systf_data tf_data;
    tf_data.type      = vpiSysTask; // vs 'vpiSysFunc'
    tf_data.tfname    = "$ulpi_monitor";
    tf_data.calltf    = ulpim_calltf;
    tf_data.compiletf = ulpim_compiletf;
    tf_data.sizetf    = 0;
    tf_data.user_data = 0;
    vpi_printf("goats are the best\n");
    vpi_register_systf(&tf_data);
}

#if 0
void (*vlog_startup_routines[])() = {
    ulpim_register,
    0,
};
#endif /* 0 */
