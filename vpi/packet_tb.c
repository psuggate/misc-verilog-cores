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
    bit_t w_vld;
    bit_t w_rdy;
    bit_t w_lst;
    byte_t w_dat;
    bit_t r_vld;
    bit_t r_rdy;
    bit_t r_lst;
    byte_t r_dat;
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
    vpiHandle w_vld;
    vpiHandle w_rdy;
    vpiHandle w_lst;
    vpiHandle w_dat;
    vpiHandle r_vld;
    vpiHandle r_rdy;
    vpiHandle r_lst;
    vpiHandle r_dat;
    int sync_flag;
    int test_num;
    int test_curr;
    int test_step;
    testcase_t** tests;
    fifo_sigs_t prev;
    fifo_sigs_t sigs;
} pt_state_t;

typedef struct __test {
    uint32_t (*fill)(uint8_t* buf, const uint32_t len);
    uint32_t size;
    uint32_t length;
    uint8_t stage;
} test_t;

static char err_mesg[2048] = {0};

// -- Prototypes -- //

static int pt_error(const char* reason);
static int pt_failed(const char* mesg, const int line, pt_state_t* state);
static int pt_get_signal(vpiHandle* dst, vpiHandle iter);
static void pt_fetch_values(pt_state_t* state);
static void pt_update_values(pt_state_t* state, fifo_sigs_t* next);
static int pt_step(pt_state_t* state, fifo_sigs_t* next);

void show_pt_state(pt_state_t* state);

// -- Helpers -- //

uint32_t fill_fixed_len(uint8_t* buf, const uint32_t len)
{
    for (int i=len; i--;) {
        buf[i] = rand();
    }
    return len;
}

uint32_t fill_len_masked(uint8_t* buf, const uint32_t len)
{
    uint32_t size = rand() & len;
    return fill_fixed_len(buf, size);
}

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

static uint32_t byte_to_hex(const byte_t* in)
{
    return (uint32_t)in->b << 8 | (uint32_t)in->a;
}

static void fifo_sigs_show(fifo_sigs_t* sigs)
{
    vpi_printf(
        "reset: %u, level: 0x%04x, {v: %u, r: %u, l: %u, d: 0x%04x}, {v: %u, r: %u, l: %u, d: 0x%04x}\n",
        sigs->reset, byte_to_hex(&sigs->level), sigs->r_vld, sigs->r_rdy,
        sigs->r_lst, byte_to_hex(&sigs->r_dat), sigs->w_vld, sigs->w_rdy,
        sigs->w_lst, byte_to_hex(&sigs->w_dat)
        );
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
    vpi_get_value(state->w_vld, &curr_value);
    state->sigs.w_vld = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->w_rdy, &curr_value);
    state->sigs.w_rdy = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->w_lst, &curr_value);
    state->sigs.w_lst = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->w_dat, &curr_value);
    state->sigs.w_dat.a = (uint8_t)curr_value.value.vector->aval;
    state->sigs.w_dat.b = (uint8_t)curr_value.value.vector->bval;

    // Packet 'fetch' AXI4 stream output
    curr_value.format = vpiScalarVal;
    vpi_get_value(state->r_vld, &curr_value);
    state->sigs.r_vld = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->r_rdy, &curr_value);
    state->sigs.r_rdy = (bit_t)curr_value.value.scalar;

    vpi_get_value(state->r_lst, &curr_value);
    state->sigs.r_lst = (bit_t)curr_value.value.scalar;

    curr_value.format = vpiVectorVal;
    vpi_get_value(state->r_dat, &curr_value);
    state->sigs.r_dat.a = (uint8_t)curr_value.value.vector->aval;
    state->sigs.r_dat.b = (uint8_t)curr_value.value.vector->bval;
}

static void pt_update_values(pt_state_t* state, fifo_sigs_t* next)
{
    s_vpi_value sig;
    s_vpi_time now;
    const fifo_sigs_t* curr = &state->sigs;

    sig.format = vpiScalarVal;
    now.type = vpiSimTime;
    vpi_get_time(NULL, &now);

    if (curr->r_rdy != next->r_rdy) {
        sig.value.scalar = next->r_rdy;
        vpi_put_value(state->r_rdy, &sig, NULL, vpiNoDelay);
    }

    if (curr->w_vld != next->w_vld) {
        sig.value.scalar = next->w_vld;
        vpi_put_value(state->w_vld, &sig, NULL, vpiNoDelay);
    }

    if (curr->w_lst != next->w_lst) {
        sig.value.scalar = next->w_lst;
        vpi_put_value(state->w_lst, &sig, NULL, vpiNoDelay);
    }

    if (curr->drop != next->drop) {
        sig.value.scalar = next->drop;
        vpi_put_value(state->drop, &sig, NULL, vpiNoDelay);
    }

    if (curr->save != next->save) {
        sig.value.scalar = next->save;
        vpi_put_value(state->save, &sig, NULL, vpiNoDelay);
    }

    if (curr->redo != next->redo) {
        sig.value.scalar = next->redo;
        vpi_put_value(state->redo, &sig, NULL, vpiNoDelay);
    }

    if (curr->next != next->next) {
        sig.value.scalar = next->next;
        vpi_put_value(state->next, &sig, NULL, vpiNoDelay);
    }

    if (curr->w_dat.a != next->w_dat.a || curr->w_dat.b != next->w_dat.b) {
        s_vpi_vecval vec = {next->w_dat.a, next->w_dat.b};
        sig.format = vpiVectorVal;
        sig.value.vector = &vec;
        vpi_put_value(state->w_dat, &sig, NULL, vpiNoDelay);
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
        }
    } else {
        // No more tests remaining
        vpi_printf("PT\t#%8lu cyc =>\tAll testbenches completed [%s:%d]\n",
                   cycle, __FILE__, __LINE__);
        result = 2;
    }

    changed |=
        memcmp(curr, next, sizeof(fifo_sigs_t)) != 0 ||
        memcmp(prev, next, sizeof(fifo_sigs_t)) != 0;

    if (changed) {
        vpi_printf("\t@%8lu ns  =>\t", state->tick_ns);
        fifo_sigs_show(next);
    }

    return result;
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


//
//  Test-cases of the Testbench
///

typedef struct __tc_state {
    int step;
    int size;
    int head;
    int tail;
    uint8_t buf[256];
} tc_state_t;

static void tc_state_show(tc_state_t* st)
{
    char str[2048];
    int p = 0;
    for (int i=0; i<st->size; i++) {
        p += sprintf(&str[p], "0x%02x, ", st->buf[i]);
    }
    vpi_printf("ST: {\n");
    vpi_printf("  step: %d,\n", st->step);
    vpi_printf("  size: %d,\n", st->size);
    vpi_printf("  head: %d,\n", st->head);
    vpi_printf("  tail: %d,\n", st->tail);
    vpi_printf("  buf[256]: {\n    %s\n  }\n};\n", str);
}

static int store_packet(fifo_sigs_t* curr, tc_state_t* st)
{
    assert(st->size > 0 && st->head >= 0 && st->buf != NULL);

    if (curr->w_vld == SIG1 && curr->w_rdy == SIG1) {
        if (curr->w_lst == SIG1) {
            curr->w_vld = SIG0;
            curr->w_lst = SIG0;
            curr->w_dat.a = 0x00;
            curr->w_dat.b = 0xFF;

            return 1;
        }
        if (curr->w_lst == SIG0) {
            st->head++;
        }
    }
    curr->w_lst = (st->head + 1) < st->size ? SIG0 : SIG1;

    if (st->head < st->size) {
        curr->w_vld = SIG1;
        curr->w_dat.a = st->buf[st->head];
        curr->w_dat.b = 0x00;
    } else {
        tc_state_show(st);
        return pt_error("overflow, store");
    }

    return 0;
}

static int fetch_packet(fifo_sigs_t* curr, tc_state_t* st)
{
    assert(st->tail >= 0 && st->buf != NULL);

    if (curr->r_vld == SIG1 && curr->r_rdy == SIG1) {
        if (st->buf[st->tail++] != curr->r_dat.a || curr->r_dat.b != 0x00) {
            tc_state_show(st);
            fifo_sigs_show(curr);
            pt_error("fetched-data check");
        }
        // assert(st->buf[st->tail++] == curr->r_dat.a && curr->r_dat.b == 0x00);

        if (curr->r_lst == SIG1) {
            curr->r_rdy = SIG0;
            return 1;
        }
    }
    curr->r_rdy = SIG1;

    return 0;
}

// -- WAIT FOR RESET -- //

static const char tc_waitrst_name[] = "WAIT FOR RESET";

static int tc_waitrst_init(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    st->step = 0;
    return 0;
}

static int tc_waitrst_step(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    assert(curr->clock == SIG1 && st != NULL);
    switch (st->step) {
    case 0:
        if (curr->reset == SIG1) {
            curr->drop = SIG0;
            curr->save = SIG0;
            curr->redo = SIG0;
            curr->next = SIG0;
            curr->w_vld = SIG0;
            curr->r_rdy = SIG0;
            st->step = 1;
        }
        break;
    case 1:
        if (curr->reset == SIG0) {
            st->step = 2;
        }
        break;
    case 2:
        return 1;
    default:
        return -1;
    }
    return 0;
}

testcase_t* test_waitrst(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    tc_state_t* st = malloc(sizeof(tc_state_t));

    st->step = 0;
    tc->name = tc_waitrst_name;
    tc->data = st;
    tc->init = tc_waitrst_init;
    tc->step = tc_waitrst_step;

    return tc;
}

// -- WRITE PACKET -- //

static const char tc_wrdata1_name[] = "WRITE PACKET";

static int tc_wrdata1_init(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    st->step = 0;
    st->head = 0;
    st->tail = 0;
    assert(fill_fixed_len(st->buf, st->size) == st->size);
    return 0;
}

static int tc_wrdata1_step(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    int result;
    assert(curr->clock == SIG1 && curr->reset == SIG0 && st != NULL);

    switch (st->step) {

    case 0:
        curr->r_rdy = SIG0;
        if (curr->w_rdy == SIG1) {
            st->step = 1;
        }
        break;

    case 1:
        result = store_packet(curr, st);
        if (result < 0) {
            return result;
        } else if (result > 0) {
            st->step = 2;
        }
        break;
        
    case 2:
        curr->save = SIG1;
        st->step = 3;
        break;

    case 3:
        curr->save = SIG0;
        if (curr->r_vld == SIG1) {
            st->step = 4;
        }
        break;

    case 4:
        result = fetch_packet(curr, st);
        if (result < 0) {
            return result;
        } else if (result > 0) {
            st->step = 5;
            curr->next = SIG1;
        }
        break;

    case 5:
        curr->next = SIG0;
        return 1;

    default:
        return -1;
    }

    return 0;
}

testcase_t* test_wrdata1(uint8_t len)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    tc_state_t* st = malloc(sizeof(tc_state_t));

    st->step = 0;
    st->size = (uint32_t)len;
    tc->name = tc_wrdata1_name;
    tc->data = st;
    tc->init = tc_wrdata1_init;
    tc->step = tc_wrdata1_step;

    return tc;
}

// -- WRITE, FETCH REDO PACKET -- //

static const char tc_wr_redo_name[] = "WRITE, FETCH, REDO PACKET";

static int tc_wr_redo_init(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    st->step = 0;
    st->head = 0;
    st->tail = 0;
    assert(fill_fixed_len(st->buf, st->size) == st->size);
    return 0;
}

static int tc_wr_redo_step(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    int result;
    assert(curr->clock == SIG1 && curr->reset == SIG0 && st != NULL);

    switch (st->step) {

    case 0:
        curr->r_rdy = SIG0;
        if (curr->w_rdy == SIG1) {
            st->step = 1;
        }
        break;

    case 1:
        result = store_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("store packet 1");
            return -1;
        } else if (result > 0) {
            curr->save = SIG1;
            st->head = 0;
            st->step = 2;
        }
        break;

    case 2:
        curr->save = SIG0;
        result = store_packet(curr, st);
        if (result != 0) {
            tc_state_show(st);
            pt_error("store packet 2");
            return -1;
        }
        st->step = 3;
        break;
        
    case 3:
        result = store_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("store/fetch packet");
        } else if (result > 0) {
            curr->save = SIG1;
            st->step = 4;
        }
        result = fetch_packet(curr, st);
        if (result != 0) {
            tc_state_show(st);
            pt_error("fetch/store packet");
        }
        break;

    case 4:
        curr->save = SIG0;
        result = fetch_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("fetch packet 1");
        } else if (result > 0) {
            curr->redo = SIG1;
            st->step = 5;
            st->tail = 0;
        }
        break;

    case 5:
        curr->redo = SIG0;
    case 6:
        curr->next = SIG0;
        result = fetch_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("fetch packet 2");
        } else if (result > 0) {
            curr->next = SIG1;
            st->step++;
            st->tail = 0;
        }
        break;

    case 7:
        curr->next = SIG0;
        return 1;

    default:
        return -1;
    }

    return 0;
}

testcase_t* test_wr_redo(uint8_t len)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    tc_state_t* st = malloc(sizeof(tc_state_t));

    st->step = 0;
    st->size = (uint32_t)len;
    tc->name = tc_wr_redo_name;
    tc->data = st;
    tc->init = tc_wr_redo_init;
    tc->step = tc_wr_redo_step;

    return tc;
}

// -- WRITE, DROP, WRITE, FETCH PACKET -- //

static const char tc_wr_drop_name[] = "WRITE, DROP, WRITE, FETCH PACKET";

static int tc_wr_drop_init(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    st->step = 0;
    st->head = 0;
    st->tail = 0;
    assert(fill_fixed_len(st->buf, st->size) == st->size);
    return 0;
}

static int tc_wr_drop_step(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    int result;
    assert(curr->clock == SIG1 && curr->reset == SIG0 && st != NULL);

    switch (st->step) {

    case 0:
        curr->r_rdy = SIG0;
        if (curr->w_rdy == SIG1) {
            st->step = 1;
        }
        break;

    case 1:
        result = store_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("store packet 1");
            return -1;
        } else if (result > 0) {
            curr->drop = SIG1;
            st->head = 0;
            st->step = 2;
        }
        break;

    case 2:
        curr->drop = SIG0;
        result = store_packet(curr, st);
        if (result != 0) {
            tc_state_show(st);
            pt_error("re-store packet 1");
            return -1;
        }
        st->step = 3;
        break;
        
    case 3:
        result = store_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("store/fetch packet");
        } else if (result > 0) {
            curr->save = SIG1;
            st->step = 4;
        }
        result = fetch_packet(curr, st);
        if (result != 0) {
            tc_state_show(st);
            pt_error("fetch/store packet");
        }
        break;

    case 4:
        curr->save = SIG0;
        result = fetch_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("fetch packet 1");
        } else if (result > 0) {
            curr->next = SIG1;
            st->step = 5;
            st->tail = 0;
        }
        break;

    case 5:
        curr->next = SIG0;
        return 1;

    default:
        return -1;
    }

    return 0;
}

testcase_t* test_wr_drop(uint8_t len)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    tc_state_t* st = malloc(sizeof(tc_state_t));

    st->step = 0;
    st->size = (uint32_t)len;
    tc->name = tc_wr_drop_name;
    tc->data = st;
    tc->init = tc_wr_drop_init;
    tc->step = tc_wr_drop_step;

    return tc;
}

// -- TOGGLE TREADY TO STOP-GO-STOP-GO-... -- //

static const char tc_stop_go_name[] = "STOP-GO-STOP-GO...";

static int tc_stop_go_init(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    st->step = 0;
    st->head = 0;
    st->tail = 0;
    assert(fill_fixed_len(st->buf, st->size) == st->size);
    return 0;
}

static int fetch_stop_go(fifo_sigs_t* curr, tc_state_t* st)
{
    int result = fetch_packet(curr, st);
    if (result != 0) {
	return result;
    }
    if ((rand() & 0x01) == 1) {
	curr->r_rdy = SIG1;
    } else {
	curr->r_rdy = SIG0;
    }
    return 0;
}

static int tc_stop_go_step(fifo_sigs_t* curr, void* data)
{
    tc_state_t* st = (tc_state_t*)data;
    int result;
    assert(curr->clock == SIG1 && curr->reset == SIG0 && st != NULL);

    switch (st->step) {

    case 0:
        curr->r_rdy = SIG0;
        if (curr->w_rdy == SIG1) {
            st->step = 1;
        }
        break;

    case 1:
        result = store_packet(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("store packet");
            return -1;
        } else if (result > 0) {
            curr->save = SIG1;
            st->head = 0;
            st->step = 2;
        }
        break;

    case 2:
        curr->save = SIG0;
        result = fetch_stop_go(curr, st);
        if (result < 0) {
            tc_state_show(st);
            pt_error("fetch stop-go");
        } else if (result > 0) {
            curr->next = SIG1;
            st->step = 3;
            st->tail = 0;
        }
        break;

    case 3:
        curr->next = SIG0;
        return 1;

    default:
        return -1;
    }

    return 0;
}

testcase_t* test_stop_go(void)
{
    testcase_t* tc = malloc(sizeof(testcase_t));
    tc_state_t* st = malloc(sizeof(tc_state_t));

    st->step = 0;
    st->size = 32;
    tc->name = tc_stop_go_name;
    tc->data = st;
    tc->init = tc_stop_go_init;
    tc->step = tc_stop_go_step;

    return tc;
}


//
//  VPI Callbacks
///

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
        if (result > 1) {
            vpi_control(vpiFinish, 0);
        }
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
        !pt_get_signal(&state->w_vld, arg_iterator) ||
        !pt_get_signal(&state->w_rdy, arg_iterator) ||
        !pt_get_signal(&state->w_lst, arg_iterator) ||
        !pt_get_signal(&state->w_dat, arg_iterator) ||
        !pt_get_signal(&state->r_vld, arg_iterator) ||
        !pt_get_signal(&state->r_rdy, arg_iterator) ||
        !pt_get_signal(&state->r_lst, arg_iterator) ||
        !pt_get_signal(&state->r_dat, arg_iterator)) {
        return 0;
    }

    /* check that there are no more system task arguments */
    arg_handle = vpi_scan(arg_iterator);
    if (arg_handle != NULL) {
        vpi_free_object(arg_iterator); /* free iterator memory */
        return pt_error("can only have 6 arguments");
    }

    if (vpi_get(vpiSize, state->w_dat) != 8) {
        return pt_error("FIFO 'w_dat' must be an 8-bit net");
    }

    if (vpi_get(vpiSize, state->r_dat) != 8) {
        return pt_error("FIFO 'r_dat' must be an 8-bit net");
    }

    state->cycle = 0;
    state->sync_flag = 0;
    state->test_curr = 0;
    state->test_step = 0;
    int i = 0;
    state->tests = (testcase_t**)malloc(sizeof(testcase_t*) * NUM_TESTCASES);
    state->tests[i++] = test_waitrst();
    state->tests[i++] = test_wrdata1(8);
    state->tests[i++] = test_wr_redo(8);
    state->tests[i++] = test_wrdata1(3);
    state->tests[i++] = test_wr_redo(3);
    state->tests[i++] = test_wr_drop(8);
    state->tests[i++] = test_wr_drop(1);
    state->tests[i++] = test_stop_go();
    state->test_num = i;

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
