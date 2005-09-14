/*
** vim:ts=4 sw=4 expandtab
*/
/*
** Copyright (C) 1997-2005 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_context.h - defines Mercury multithreading stuff.
**
** A "context" is a Mercury thread.  (We use a different term than "thread"
** to avoid confusing Mercury threads and Posix threads.) 
** Each context is represented by a value of type MR_Context,
** which contains a detstack, a nondetstack, a trail (if needed), the various
** pointers that refer to them, a succip, and a thread-resumption continuation. 
** Contexts are initally stored in a free-list.
** When one is running, the Posix thread that is executing it has a pointer
** to its context structure `this_context'. When a context suspends, it
** calls `MR_save_context(context_ptr)' which copies the context from the
** various registers and global variables into the structure referred to
** by `context_ptr'. The context contains no rN or fN registers - all
** registers are "context save" (by analogy to caller-save).
**
** When a new context is created information is passed to the new context
** on the stack. The top stackframe of the current context is copied to
** become the first det stackframe in the new process. (XXX this will need
** fixing eventually to include the nondet frame as well.)
**
** Contexts can migrate transparently between multiple Posix threads.
**
** Each Posix thread has its own heap and solutions heap (both allocated
** in shared memory). This makes GC harder, but enables heap allocation
** to be done without locking which is very important for performance.
** Each context has a copy of the heap pointer that is taken when it is
** switched out. If the Posix thread's heap pointer is the same as the
** copied one when the context is switched back in, then it is safe for
** the context to do heap reclamation on failure.
**
** If MR_THREAD_SAFE is not defined, then everything gets executed within a
** single Posix thread. No locking is required.
*/

#ifndef MERCURY_CONTEXT_H
#define MERCURY_CONTEXT_H

#include "mercury_regs.h"       /* for MR_hp, etc. */
                                /* Must come before system headers. */

#include <stdio.h>

#include "mercury_types.h"      /* for MR_Word, MR_Code, etc */
#include "mercury_trail.h"      /* for MR_TrailEntry */
#include "mercury_memory.h"     /* for MR_MemoryZone */
#include "mercury_thread.h"     /* for MercuryLock */
#include "mercury_goto.h"       /* for MR_GOTO() */
#include "mercury_conf.h"       /* for MR_CONSERVATIVE_GC */

#ifdef  MR_THREAD_SAFE
  #define MR_IF_THREAD_SAFE(x)  x
#else
  #define MR_IF_THREAD_SAFE(x)
#endif

/*
** MR_Context structures have the following fields:
**
** id               A string to identify the context for humans who want to
**                  debug the handling of contexts.
**
** next             If this context is in the free-list `next' will point to
**                  the next free context. If this context is suspended waiting
**                  for a variable to become bound, `next' will point to the
**                  next waiting context. If this context is runnable but not
**                  currently running then `next' points to the next runnable
**                  context in the runqueue.
**
** resume           A pointer to the code at which execution should resume
**                  when this context is next scheduled.
**
** owner_thread     The owner_thread field is used to ensure that when we
**                  enter a Mercury engine from C, we return to the same
**                  engine. See the coments in mercury_engine.h.
**
** succip           The succip for this context.
**
** detstack_zone    The detstack zone for this context.
** sp               The saved sp for this context.
**
** nondetstack_zone The nondetstack zone for this context.
** curfr            The saved curfr for this context.
** maxfr            The saved maxfr for this context.
**
** genstack_zone    The generator stack zone for this context.
** gen_next         The saved gen_next for this context.
**
** cutstack_zone    The cut stack zone for this context.
** cut_next         The saved cut_next for this context.
**
** pnegstack_zone   The possibly_negated_context stack zone for this context.
** pneg_next        The saved pneg_next for this context.
**
** trail_zone       The trail zone for this context.
** trail_ptr        The saved MR_trail_ptr for this context.
** ticket_counter   The saved MR_ticket_counter for this context.
** ticket_highwater The saved MR_ticket_high_water for this context.
**
** hp               The saved hp for this context.
**
** min_hp_rec       This pointer marks the minimum value of MR_hp to which
**                  we can truncate the heap on backtracking. See comments
**                  before the macro set_min_heap_reclamation_point below.
*/

typedef struct MR_Context_Struct MR_Context;
struct MR_Context_Struct {
    const char          *MR_ctxt_id;
    MR_Context          *MR_ctxt_next; 
    MR_Code             *MR_ctxt_resume;
#ifdef  MR_THREAD_SAFE
    MercuryThread       MR_ctxt_owner_thread;
#endif

#ifndef MR_HIGHLEVEL_CODE
    MR_Code             *MR_ctxt_succip;

    MR_MemoryZone       *MR_ctxt_detstack_zone;
    MR_Word             *MR_ctxt_sp;

    MR_MemoryZone       *MR_ctxt_nondetstack_zone;
    MR_Word             *MR_ctxt_maxfr;
    MR_Word             *MR_ctxt_curfr;

  #ifdef MR_USE_MINIMAL_MODEL_STACK_COPY
    MR_MemoryZone       *MR_ctxt_genstack_zone;
    MR_Integer          MR_ctxt_gen_next;

    MR_MemoryZone       *MR_ctxt_cutstack_zone;
    MR_Integer          MR_ctxt_cut_next;

    MR_MemoryZone       *MR_ctxt_pnegstack_zone;
    MR_Integer          MR_ctxt_pneg_next;

  #endif /* MR_USE_MINIMAL_MODEL_STACK_COPY */
  #ifdef MR_USE_MINIMAL_MODEL_OWN_STACKS
    MR_Generator        *MR_ctxt_owner_generator;
  #endif /* MR_USE_MINIMAL_MODEL_OWN_STACKS */
#endif /* !MR_HIGHLEVEL_CODE */

#ifdef  MR_USE_TRAIL
    MR_MemoryZone       *MR_ctxt_trail_zone;
    MR_TrailEntry       *MR_ctxt_trail_ptr;
    MR_ChoicepointId    MR_ctxt_ticket_counter;
    MR_ChoicepointId    MR_ctxt_ticket_high_water;
#endif

#ifndef MR_CONSERVATIVE_GC
    MR_Word             *MR_ctxt_hp;
    MR_Word             *MR_ctxt_min_hp_rec;
#endif
};

/*
** The runqueue is a linked list of contexts that are runnable.
*/
extern      MR_Context  *MR_runqueue_head;
extern      MR_Context  *MR_runqueue_tail;
#ifdef  MR_THREAD_SAFE
  extern    MercuryLock MR_runqueue_lock;
  extern    MercuryCond MR_runqueue_cond;
#endif

/*
** As well as the runqueue, we maintain a linked list of contexts
** and associated file descriptors that are suspended blocked for
** reads/writes/exceptions. When the runqueue becomes empty, if
** this list is not empty then we call select and block until one
** or more of the file descriptors become ready for I/O, then
** wake the appropriate context.
** In addition, we should periodically check to see if the list of blocked
** contexts is non-empty and if so, poll to wake any contexts that
** can unblock. This, while not yielding true fairness (since this
** requires the current context to perform some yield-like action),
** ensures that it is possible for programmers to write concurrent
** programs with continuous computation and interleaved I/O dependent
** computation in a straight-forward manner. This polling is not
** currently implemented.
*/

typedef enum {
    MR_PENDING_READ  = 0x01,
    MR_PENDING_WRITE = 0x02,
    MR_PENDING_EXEC  = 0x04
} MR_WaitingMode;

typedef struct MR_PendingContext_Struct {
    struct MR_PendingContext_Struct *next;
    MR_Context                      *context;
    int                             fd;
    MR_WaitingMode                  waiting_mode;
} MR_PendingContext;

extern  MR_PendingContext   *MR_pending_contexts;
#ifdef  MR_THREAD_SAFE
  extern    MercuryLock     MR_pending_contexts_lock;
#endif

/*
** Initializes a context structure, and gives it the given id. If gen is
** non-NULL, the context is for the given generator.
*/
extern  void        MR_init_context(MR_Context *context, const char *id,
                        MR_Generator *gen);

/*
** Allocates and initializes a new context structure, and gives it the given
** id. If gen is non-NULL, the context is for the given generator.
*/
extern  MR_Context  *MR_create_context(const char *id, MR_Generator *gen);

/*
** MR_destroy_context(context) returns the pointed-to context structure
** to the free list, and releases resources as necessary.
*/
extern  void        MR_destroy_context(MR_Context *context);

/*
** MR_init_thread_stuff() initializes the lock structures for the runqueue.
*/
extern  void        MR_init_thread_stuff(void);

/*
** MR_finialize_runqueue() finalizes the lock structures for the runqueue.
*/
extern  void        MR_finalize_runqueue(void);

/*
** MR_flounder() aborts with a runtime error message. It is called if
** the runqueue becomes empty and none of the running processes are
** working, which means that the computation has floundered.
*/
extern  void        MR_flounder(void);

/*
** Append the given context onto the end of the run queue.
*/

extern  void        MR_schedule(MR_Context *ctxt);

#ifndef MR_HIGHLEVEL_CODE
  MR_declare_entry(MR_do_runnext);
  #define MR_runnext()                          \
    do {                                        \
        MR_GOTO(MR_ENTRY(MR_do_runnext));       \
    } while (0)
#endif

#ifdef  MR_THREAD_SAFE
  #define MR_IF_MR_THREAD_SAFE(x)   x
#else
  #define MR_IF_MR_THREAD_SAFE(x)
#endif

#ifndef MR_HIGHLEVEL_CODE
  /*
  ** fork_new_context(MR_Code *child, MR_Code *parent, int numslots):
  ** create a new context to execute the code at `child', and
  ** copy the topmost `numslots' from the current stackframe.
  ** The new context gets put on the runqueue, and the current
  ** context resumes at `parent'.
  */
  #define MR_fork_new_context(child, parent, numslots)          \
    do {                                                        \
        MR_Context  *f_n_c_context;                             \
        int         fork_new_context_i;                         \
                                                                \
        f_n_c_context = MR_create_context();                    \
        MR_IF_MR_THREAD_SAFE(                                   \
            f_n_c_context->owner_thread = NULL;                 \
        )                                                       \
        for (fork_new_context_i = (numslots);                   \
            fork_new_context_i > 0;                             \
            fork_new_context_i--)                               \
        {                                                       \
            *(f_n_c_context->context_sp) = MR_stackvar(fork_new_context_i); \
            f_n_c_context->MR_ctxt_sp++;                        \
        }                                                       \
        f_n_c_context->MR_ctxt_resume = (child);                \
        MR_schedule(f_n_c_context);                             \
        MR_GOTO(parent);                                        \
    } while (0)
#endif /* MR_HIGHLEVEL_CODE */

#ifndef MR_CONSERVATIVE_GC

  /*
  ** To figure out the maximum amount of heap we can reclaim on backtracking,
  ** we compare MR_hp with the MR_ctxt_hp.
  **
  ** If MR_ctxt_hp == NULL then this is the first time this context has been
  ** scheduled, so the furthest back down the heap we can reclaim is to the
  ** current value of MR_hp. 
  **
  ** If MR_hp > MR_ctxt_hp, another context has allocated data on the heap
  ** since we were last scheduled, so the furthest back that we can reclaim is
  ** to the current value of MR_hp, so we set MR_min_hp_rec and the
  ** field of the same name in our context structure.
  **
  ** If MR_hp < MR_ctxt_hp, then another context has truncated the heap on
  ** failure. For this to happen, it must be the case that last time we were
  ** that other context was the last one to allocate data on the heap, and we
  ** scheduled, did not allocate any heap during that period of execution.
  ** That being the case, the furthest back to which we can reset the heap is
  ** to the current value of hp. This is a conservative approximation - it is
  ** possible that the current value of hp is the same as some previous value
  ** that we held, and we are now contiguous with our older data, so this
  ** algorithm will lead to holes in the heap, though GC will reclaim these.
  **
  ** If hp == MR_ctxt_hp then no other process has allocated any heap since we
  ** were last scheduled, so we can proceed as if we had not stopped, and the
  ** furthest back that we can backtrack is the same as it was last time we
  ** were executing.
  */
  #define MR_set_min_heap_reclamation_point(ctxt)           \
    do {                                                    \
        if (MR_hp != (ctxt)->MR_ctxt_hp || (ctxt)->MR_ctxt_hp == NULL) { \
            MR_min_hp_rec = MR_hp;                          \
            (ctxt)->MR_ctxt_min_hp_rec = MR_hp;             \
        } else {                                            \
            MR_min_hp_rec = (ctxt)->MR_ctxt_min_hp_rec;     \
        }                                                   \
    } while (0)

  #define MR_save_hp_in_context(ctxt)                       \
    do {                                                    \
        (ctxt)->MR_ctxt_hp = MR_hp;                         \
        (ctxt)->MR_ctxt_min_hp_rec = MR_min_hp_rec;         \
    } while (0)

#else

  #define MR_set_min_heap_reclamation_point(ctxt)   do { } while (0)

  #define MR_save_hp_in_context(ctxt)               do { } while (0)

#endif

#ifdef MR_USE_TRAIL
  #define MR_IF_USE_TRAIL(x) x
#else
  #define MR_IF_USE_TRAIL(x)
#endif

#ifdef MR_USE_MINIMAL_MODEL_STACK_COPY
  #define MR_IF_USE_MINIMAL_MODEL_STACK_COPY(x) x
#else
  #define MR_IF_USE_MINIMAL_MODEL_STACK_COPY(x)
#endif

#ifndef MR_HIGHLEVEL_CODE
  #define MR_IF_NOT_HIGHLEVEL_CODE(x) x
#else
  #define MR_IF_NOT_HIGHLEVEL_CODE(x)
#endif

#define MR_load_context(cptr)                                                 \
    do {                                                                      \
        MR_Context  *load_context_c;                                          \
                                                                              \
        load_context_c = (cptr);                                              \
        MR_IF_NOT_HIGHLEVEL_CODE(                                             \
            MR_succip_word = (MR_Word) load_context_c->MR_ctxt_succip;        \
            MR_sp_word     = (MR_Word) load_context_c->MR_ctxt_sp;            \
            MR_maxfr_word  = (MR_Word) load_context_c->MR_ctxt_maxfr;         \
            MR_curfr_word  = (MR_Word) load_context_c->MR_ctxt_curfr;         \
            MR_IF_USE_MINIMAL_MODEL_STACK_COPY(                               \
                MR_gen_next = load_context_c->MR_ctxt_gen_next;               \
                MR_cut_next = load_context_c->MR_ctxt_cut_next;               \
                MR_pneg_next = load_context_c->MR_ctxt_pneg_next;             \
            )                                                                 \
        )                                                                     \
        MR_IF_USE_TRAIL(                                                      \
            MR_trail_zone = load_context_c->MR_ctxt_trail_zone;               \
            MR_trail_ptr = load_context_c->MR_ctxt_trail_ptr;                 \
            MR_ticket_counter = load_context_c->MR_ctxt_ticket_counter;       \
            MR_ticket_high_water = load_context_c->MR_ctxt_ticket_high_water; \
        )                                                                     \
        MR_IF_NOT_HIGHLEVEL_CODE(                                             \
            MR_ENGINE(MR_eng_context).MR_ctxt_detstack_zone =                 \
                load_context_c->MR_ctxt_detstack_zone;                        \
            MR_ENGINE(MR_eng_context).MR_ctxt_nondetstack_zone =              \
                load_context_c->MR_ctxt_nondetstack_zone;                     \
            MR_IF_USE_MINIMAL_MODEL_STACK_COPY(                               \
                MR_ENGINE(MR_eng_context).MR_ctxt_genstack_zone =             \
                    load_context_c->MR_ctxt_genstack_zone;                    \
                MR_ENGINE(MR_eng_context).MR_ctxt_cutstack_zone =             \
                    load_context_c->MR_ctxt_cutstack_zone;                    \
                MR_ENGINE(MR_eng_context).MR_ctxt_pnegstack_zone =            \
                    load_context_c->MR_ctxt_pnegstack_zone;                   \
                MR_gen_stack = (MR_GenStackFrame *)                           \
                    MR_ENGINE(MR_eng_context).MR_ctxt_genstack_zone->         \
                        MR_zone_min;                                          \
                MR_cut_stack = (MR_CutStackFrame *)                           \
                    MR_ENGINE(MR_eng_context).MR_ctxt_cutstack_zone->         \
                        MR_zone_min;                                          \
                MR_pneg_stack = (MR_PNegStackFrame *)                         \
                    MR_ENGINE(MR_eng_context).MR_ctxt_pnegstack_zone->        \
                        MR_zone_min;                                          \
             )                                                                \
        )                                                                     \
        MR_set_min_heap_reclamation_point(load_context_c);                    \
    } while (0)

#define MR_save_context(cptr)                                                 \
    do {                                                                      \
        MR_Context  *save_context_c;                                          \
                                                                              \
        save_context_c = (cptr);                                              \
        MR_IF_NOT_HIGHLEVEL_CODE(                                             \
            save_context_c->MR_ctxt_succip  = MR_succip;                      \
            save_context_c->MR_ctxt_sp      = MR_sp;                          \
            save_context_c->MR_ctxt_maxfr   = MR_maxfr;                       \
            save_context_c->MR_ctxt_curfr   = MR_curfr;                       \
            MR_IF_USE_MINIMAL_MODEL_STACK_COPY(                               \
                save_context_c->MR_ctxt_gen_next = MR_gen_next;               \
                save_context_c->MR_ctxt_cut_next = MR_cut_next;               \
                save_context_c->MR_ctxt_pneg_next = MR_pneg_next;             \
            )                                                                 \
        )                                                                     \
        MR_IF_USE_TRAIL(                                                      \
            save_context_c->MR_ctxt_trail_zone = MR_trail_zone;               \
            save_context_c->MR_ctxt_trail_ptr = MR_trail_ptr;                 \
            save_context_c->MR_ctxt_ticket_counter =                          \
                MR_ticket_counter;                                            \
            save_context_c->MR_ctxt_ticket_high_water =                       \
                MR_ticket_high_water;                                         \
        )                                                                     \
        MR_IF_NOT_HIGHLEVEL_CODE(                                             \
            save_context_c->MR_ctxt_detstack_zone =                           \
                MR_ENGINE(MR_eng_context).MR_ctxt_detstack_zone;              \
            save_context_c->MR_ctxt_nondetstack_zone =                        \
                MR_ENGINE(MR_eng_context).MR_ctxt_nondetstack_zone;           \
            MR_IF_USE_MINIMAL_MODEL_STACK_COPY(                               \
                save_context_c->MR_ctxt_genstack_zone =                       \
                    MR_ENGINE(MR_eng_context).MR_ctxt_genstack_zone;          \
                save_context_c->MR_ctxt_cutstack_zone =                       \
                    MR_ENGINE(MR_eng_context).MR_ctxt_cutstack_zone;          \
                save_context_c->MR_ctxt_pnegstack_zone =                      \
                    MR_ENGINE(MR_eng_context).MR_ctxt_pnegstack_zone;         \
                assert(MR_gen_stack == (MR_GenStackFrame *)                   \
                    MR_ENGINE(MR_eng_context).MR_ctxt_genstack_zone->         \
                        MR_zone_min);                                         \
                assert(MR_cut_stack == (MR_CutStackFrame *)                   \
                    MR_ENGINE(MR_eng_context).MR_ctxt_cutstack_zone->         \
                        MR_zone_min);                                         \
                assert(MR_pneg_stack == (MR_PNegStackFrame *)                 \
                    MR_ENGINE(MR_eng_context).MR_ctxt_pnegstack_zone->        \
                        MR_zone_min);                                         \
          )                                                                   \
        )                                                                     \
        MR_save_hp_in_context(save_context_c);                                \
    } while (0)

typedef struct MR_Sync_Term_Struct MR_SyncTerm;
struct MR_Sync_Term_Struct {
  #ifdef MR_THREAD_SAFE
    MercuryLock     MR_st_lock;
  #endif
    int             MR_st_count;
    MR_Context      *MR_st_parent;
};

#define MR_init_sync_term(sync_term, nbranches)                     \
    do {                                                            \
        MR_SyncTerm *st;                                            \
                                                                    \
        st = (MR_SyncTerm *) sync_term;                             \
        MR_IF_THREAD_SAFE(                                          \
            pthread_mutex_init(&(st->MR_st_lock), MR_MUTEX_ATTR);   \
        )                                                           \
        st->MR_st_count = (nbranches);                              \
        st->MR_st_parent = NULL;                                    \
    } while (0)

#define MR_join_and_terminate(sync_term)                            \
    do {                                                            \
        MR_SyncTerm *st;                                            \
                                                                    \
        st = (MR_SyncTerm *) sync_term;                             \
        MR_LOCK(&(st->MR_st_lock), "terminate");                    \
        (st->MR_st_count)--;                                        \
        if (st->MR_st_count == 0) {                                 \
            assert(st->MR_st_parent != NULL);                       \
            MR_UNLOCK(&(st->MR_st_lock), "terminate i");            \
            MR_schedule(st->MR_st_parent);                          \
        } else {                                                    \
            assert(st->MR_st_count > 0);                            \
            MR_UNLOCK(&(st->MR_st_lock), "terminate ii");           \
        }                                                           \
        MR_destroy_context(MR_ENGINE(MR_eng_this_context));         \
        MR_runnext();                       \
    } while (0)

#define MR_join_and_continue(sync_term, where_to)                   \
    do {                                                            \
        MR_SyncTerm *st;                                            \
                                                                    \
        st = (MR_SyncTerm *) sync_term;                             \
        MR_LOCK(&(st->MR_st_lock), "continue");                     \
        (st->MR_st_count)--;                                        \
        if (st->MR_st_count == 0) {                                 \
            MR_UNLOCK(&(st->MR_st_lock), "continue i");             \
            MR_GOTO((where_to));                                    \
        }                                                           \
        assert(st->MR_st_count > 0);                                \
        MR_save_context(MR_ENGINE(MR_eng_this_context));            \
        MR_ENGINE(MR_eng_this_context)->MR_ctxt_resume = (where_to);\
        st->MR_st_parent = MR_ENGINE(MR_eng_this_context);          \
        MR_UNLOCK(&(st->MR_st_lock), "continue ii");                \
        MR_runnext();                                               \
    } while (0)

#endif /* not MERCURY_CONTEXT_H */
