/*
** Copyright (C) 1998-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** Main author: Mark Brown
**
** This file implements the back end of the declarative debugger.  The
** back end is an extension to the internal debugger which collects
** related trace events and builds them into an annotated trace.  Once
** built, the structure is passed to the front end where it can be
** analysed to find bugs.  The front end is implemented in
** browse/declarative_debugger.m.
**
** The interface between the front and back ends is via the
** annotated_trace/2 typeclass, which is documented in
** browse/declarative_debugger.m.  It would be possible to replace
** the front end or the back end with an alternative implementation
** which also conforms to the typeclass constraints.  For example:
** 	- An alternative back end could generate the same tree
** 	  structure in a different way, such as via program
** 	  transformation.
** 	- An alternative front end could graphically display the
** 	  generated trees as part of a visualization tool rather
** 	  than analyzing them for bugs.
*/

#include "mercury_imp.h"
#include "mercury_trace_declarative.h"

#ifdef MR_USE_DECLARATIVE_DEBUGGER

#include "mercury_trace.h"
#include "mercury_trace_browse.h"
#include "mercury_trace_internal.h"
#include "mercury_trace_tables.h"
#include "mercury_trace_util.h"
#include "mercury_trace_vars.h"

#include "mercury_layout_util.h"
#include "mercury_deep_copy.h"
#include "mercury_stack_trace.h"
#include "mercury_string.h"
#include "mercury_trace_base.h"

#include "mdb.declarative_debugger.h"
#include "mdb.declarative_execution.h"
#ifdef MR_HIGHLEVEL_CODE
  #include "mercury.std_util.h"
#else
  #include "std_util.h"
#endif

#include <errno.h>

/*
** We only build the annotated trace for events down to a certain
** depth.  The following macro gives the default depth limit (relative
** to the starting depth).  In future it would be nice to dynamically
** adjust this factor based on profiling information.
*/

#define MR_EDT_DEPTH_STEP_SIZE		6

/*
** These macros are to aid debugging of the code which constructs
** the annotated trace.
*/

#ifdef MR_DEBUG_DD_BACK_END

#define MR_decl_checkpoint_event(event_info)				\
		MR_decl_checkpoint_event_imp("EVENT", event_info)

#define MR_decl_checkpoint_filter(event_info)				\
		MR_decl_checkpoint_event_imp("FILTER", event_info)

#define MR_decl_checkpoint_find(location)				\
		MR_decl_checkpoint_loc("FIND", location)

#define MR_decl_checkpoint_step(location)				\
		MR_decl_checkpoint_loc("STEP", location)

#define MR_decl_checkpoint_match(location)				\
		MR_decl_checkpoint_loc("MATCH", location)

#define MR_decl_checkpoint_alloc(location)				\
		MR_decl_checkpoint_loc("ALLOC", location)

#else /* !MR_DEBUG_DD_BACK_END */

#define MR_decl_checkpoint_event(event_info)
#define MR_decl_checkpoint_filter(event_info)
#define MR_decl_checkpoint_find(location)
#define MR_decl_checkpoint_step(location)
#define MR_decl_checkpoint_match(location)
#define MR_decl_checkpoint_alloc(location)

#endif

/*
** The declarative debugger back end is controlled by the
** settings of the following variables.  They are set in
** MR_trace_start_decl_debug when the back end is started.  They
** are used by MR_trace_decl_debug to decide what action to
** take for a particular trace event.
**
** Events that are deeper than the maximum depth, or which are
** outside the top call being debugged, are ignored.  Events which
** are beyond the given last event cause the internal debugger to
** be switched back into interactive mode.
*/

static	Unsigned	MR_edt_max_depth;
static	Unsigned	MR_edt_last_event;
static	bool		MR_edt_inside;
static	Unsigned	MR_edt_start_seqno;

/*
** This is used as the abstract map from node identifiers to nodes
** in the data structure passed to the front end.  It should be
** incremented each time the data structure is destructively
** updated, before being passed to Mercury code again.
*/

static	Unsigned	MR_trace_node_store;

/*
** The front end state is stored here in between calls to it.
** MR_trace_decl_ensure_init should be called before using the state.
*/

static	Word		MR_trace_front_end_state;

static	void
MR_trace_decl_ensure_init(void);

/*
** MR_trace_current_node always contains the last node allocated,
** or NULL if the collection has just started.
*/

static	MR_Trace_Node	MR_trace_current_node;

/*
** When in test mode, MR_trace_store_file points to an open file to
** which the store should be written when built.  This global is
** set in MR_trace_start_decl_debug, and keeps the same value
** throughout the declarative debugging session.
*/

static	FILE		*MR_trace_store_file;

static	MR_Trace_Node
MR_trace_decl_call(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_exit(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_redo(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_fail(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_switch(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_disj(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_cond(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_then(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_else(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_neg_enter(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_neg_success(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_neg_failure(MR_Event_Info *event_info, MR_Trace_Node prev);

static	MR_Trace_Node
MR_trace_decl_get_slot(const MR_Stack_Layout_Entry *entry, Word *saved_regs);

static	void
MR_trace_decl_set_slot(const MR_Stack_Layout_Entry *entry, Word *saved_regs,
		MR_Trace_Node node);

static	MR_Trace_Node
MR_trace_matching_call(MR_Trace_Node node);

static	bool
MR_trace_first_disjunct(MR_Event_Info *event_info);

static	bool
MR_trace_matching_cond(const char *path, MR_Trace_Node node);

static	bool
MR_trace_matching_neg(const char *path, MR_Trace_Node node);

static	bool
MR_trace_matching_disj(const char *path, MR_Trace_Node node);

static	bool
MR_trace_same_construct(const char *p1, const char *p2);

static	bool
MR_trace_single_component(const char *path);

static	Word
MR_decl_make_atom(const MR_Stack_Layout_Label *layout, Word *saved_regs,
		MR_Trace_Port port);

static	ConstString
MR_decl_atom_name(const MR_Stack_Layout_Entry *entry);

static	Word
MR_decl_atom_args(const MR_Stack_Layout_Label *layout, Word *saved_regs);

static	const char *
MR_trace_start_collecting(Unsigned event, Unsigned seqno, Unsigned maxdepth,
		MR_Trace_Cmd_Info *cmd, MR_Event_Info *event_info,
		MR_Event_Details *event_details, Code **jumpaddr);

static	Code *
MR_trace_restart_decl_debug(Unsigned event, Unsigned seqno,
		MR_Trace_Cmd_Info *cmd, MR_Event_Info *event_info,
		MR_Event_Details *event_details);

static	Code *
MR_decl_diagnosis(MR_Trace_Node root, MR_Trace_Cmd_Info *cmd,
		MR_Event_Info *event_info, MR_Event_Details *event_details);

static	void
MR_decl_diagnosis_test(MR_Trace_Node root);

static	Code *
MR_decl_handle_bug_found(Unsigned event, MR_Trace_Cmd_Info *cmd,
		MR_Event_Info *event_info, MR_Event_Details *event_details);

static	String
MR_trace_node_path(MR_Trace_Node node);

static	MR_Trace_Port
MR_trace_node_port(MR_Trace_Node node);

static	Unsigned
MR_trace_node_seqno(MR_Trace_Node node);

static	MR_Trace_Node
MR_trace_node_first_disj(MR_Trace_Node node);

static	MR_Trace_Node
MR_trace_step_left_in_contour(MR_Trace_Node node);

static	MR_Trace_Node
MR_trace_find_prev_contour(MR_Trace_Node node);

static	void
MR_decl_checkpoint_event_imp(const char *str, MR_Event_Info *event_info);

static	void
MR_decl_checkpoint_loc(const char *str, MR_Trace_Node node);

Code *
MR_trace_decl_debug(MR_Trace_Cmd_Info *cmd, MR_Event_Info *event_info)
{
	MR_Stack_Layout_Entry 	*entry;
	Unsigned		depth;
	MR_Trace_Node		trace;
	MR_Event_Details	event_details;

	entry = event_info->MR_event_sll->MR_sll_entry;
	depth = event_info->MR_call_depth;

	if (event_info->MR_event_number > MR_edt_last_event) {
		/* This shouldn't ever be reached. */
		fprintf(MR_mdb_err, "Warning: missed final event.\n");
		fprintf(MR_mdb_err, "event %lu\nlast event %lu\n",
				(unsigned long) event_info->MR_event_number,
				(unsigned long) MR_edt_last_event);
		MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
		return MR_trace_event_internal(cmd, TRUE, event_info);
	}

	if (!MR_ENTRY_LAYOUT_HAS_EXEC_TRACE(entry)) {
		/* XXX this should be handled better. */
		MR_fatal_error("layout has no execution tracing");
	}

	if (depth > MR_edt_max_depth) {
		/*
		** We filter out events which are deeper than a certain
		** limit given by MR_edt_max_depth.  These events are
		** implicitly represented in the structure being built.
		*/
		return NULL;
	}

	if (MR_edt_inside) {
		if (event_info->MR_call_seqno == MR_edt_start_seqno &&
			MR_port_is_final(event_info->MR_trace_port))
		{
			/*
			** We are leaving the topmost call.
			*/
			MR_edt_inside = FALSE;
		}
	} else {
		if (event_info->MR_call_seqno == MR_edt_start_seqno) {
			/*
			** The port must be either CALL or REDO;
			** we are (re)entering the topmost call.
			*/
			MR_edt_inside = TRUE;
		} else {
			/*
			** Ignore this event---it is outside the
			** topmost call.
			*/
			MR_decl_checkpoint_filter(event_info);
			return NULL;
		}
	}

	if (MR_ENTRY_LAYOUT_COMPILER_GENERATED(entry)) {
		/*
		** Filter out events for compiler generated procedures.
		*/
		return NULL;
	}

#ifdef MR_USE_DECL_STACK_SLOT
	if (entry->MR_sle_maybe_decl_debug < 1) {
		/*
		** If using reserved stack slots, we ignore any event
		** for a procedure that does not have a slot reserved.
		** Such procedures are effectively assumed correct.
		*/
		return NULL;
	}
#endif /* MR_USE_DECL_STACK_SLOT */

	event_details.MR_call_seqno = MR_trace_call_seqno;
	event_details.MR_call_depth = MR_trace_call_depth;
	event_details.MR_event_number = MR_trace_event_number;

	MR_trace_enabled = FALSE;
	MR_decl_checkpoint_event(event_info);
	trace = MR_trace_current_node;
	switch (event_info->MR_trace_port) {
		case MR_PORT_CALL:
			trace = MR_trace_decl_call(event_info, trace);
			break;
		case MR_PORT_EXIT:
			trace = MR_trace_decl_exit(event_info, trace);
			break;
		case MR_PORT_REDO:
			trace = MR_trace_decl_redo(event_info, trace);
			break;
		case MR_PORT_FAIL:
			trace = MR_trace_decl_fail(event_info, trace);
			break;
		case MR_PORT_DISJ:
			trace = MR_trace_decl_disj(event_info, trace);
			break;
		case MR_PORT_SWITCH:
			trace = MR_trace_decl_switch(event_info, trace);
			break;
		case MR_PORT_COND:
			trace = MR_trace_decl_cond(event_info, trace);
			break;
		case MR_PORT_THEN:
			trace = MR_trace_decl_then(event_info, trace);
			break;
		case MR_PORT_ELSE:
			trace = MR_trace_decl_else(event_info, trace);
			break;
		case MR_PORT_NEG_ENTER:
			trace = MR_trace_decl_neg_enter(event_info, trace);
			break;
		case MR_PORT_NEG_SUCCESS:
			trace = MR_trace_decl_neg_success(event_info, trace);
			break;
		case MR_PORT_NEG_FAILURE:
			trace = MR_trace_decl_neg_failure(event_info, trace);
			break;
		case MR_PORT_PRAGMA_FIRST:
		case MR_PORT_PRAGMA_LATER:
			MR_fatal_error("MR_trace_decl_debug: "
				"foreign language code is not handled (yet)");
		case MR_PORT_EXCEPTION:
			MR_fatal_error("MR_trace_decl_debug: "
				"exceptions are not handled (yet)");
		default:
			MR_fatal_error("MR_trace_decl_debug: unknown port");
	}
	MR_decl_checkpoint_alloc(trace);
	MR_trace_current_node = trace;
	
	/*
	** Restore globals from the saved copies.
	*/
	MR_trace_call_seqno = event_details.MR_call_seqno;
	MR_trace_call_depth = event_details.MR_call_depth;
	MR_trace_event_number = event_details.MR_event_number;

	if (MR_trace_event_number == MR_edt_last_event) {
		/*
		** Call the front end.
		*/
		switch (MR_trace_decl_mode) {
			case MR_TRACE_DECL_DEBUG:
				return MR_decl_diagnosis(
						MR_trace_current_node, cmd,
						event_info, &event_details);

			case MR_TRACE_DECL_DEBUG_TEST:
				MR_decl_diagnosis_test(MR_trace_current_node);
				break;

			default:
				MR_fatal_error("MR_trace_decl_debug: "
						"unexpected mode");
		}
		MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
		return MR_trace_event_internal(cmd, TRUE, event_info);
	}

	MR_trace_enabled = TRUE;
	return NULL;
}

static	MR_Trace_Node
MR_trace_decl_call(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node			node;
	Word				atom;
	bool				at_depth_limit;
	const MR_Stack_Layout_Label	*layout = event_info->MR_event_sll;

	if (event_info->MR_call_depth == MR_edt_max_depth) {
		at_depth_limit = TRUE;
	} else {
		at_depth_limit = FALSE;
	}

	atom = MR_decl_make_atom(layout, event_info->MR_saved_regs,
			MR_PORT_CALL);
	MR_TRACE_CALL_MERCURY(
		node = (MR_Trace_Node) MR_DD_construct_call_node(
					(Word) prev, atom,
					(Word) event_info->MR_call_seqno,
					(Word) event_info->MR_event_number,
					(Word) at_depth_limit);
	);

#ifdef MR_USE_DECL_STACK_SLOT
	MR_trace_decl_set_slot(layout->MR_sll_entry,
					event_info->MR_saved_regs, node);
#endif

	return node;
}
	
static	MR_Trace_Node
MR_trace_decl_exit(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		call;
	Word			last_interface;
	Word			atom;

	atom = MR_decl_make_atom(event_info->MR_event_sll,
				event_info->MR_saved_regs,
				MR_PORT_EXIT);

#ifdef MR_USE_DECL_STACK_SLOT
	call = MR_trace_decl_get_slot(event_info->MR_event_sll->MR_sll_entry,
				event_info->MR_saved_regs);
#else
	call = MR_trace_matching_call(prev);
	MR_decl_checkpoint_match(call);
#endif
	
	MR_TRACE_CALL_MERCURY(
		last_interface = MR_DD_call_node_get_last_interface(
				(Word) call);
		node = (MR_Trace_Node) MR_DD_construct_exit_node(
				(Word) prev, (Word) call, last_interface,
				atom, (Word) event_info->MR_event_number);
		MR_DD_call_node_set_last_interface((Word) call, (Word) node);
	);

	return node;
}

static	MR_Trace_Node
MR_trace_decl_redo(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		call;
	MR_Trace_Node		next;
	Word			last_interface;

#ifdef MR_USE_DECL_STACK_SLOT
	call = MR_trace_decl_get_slot(event_info->MR_event_sll->MR_sll_entry,
				event_info->MR_saved_regs);
#else
	/*
	** Search through previous contour for a matching EXIT event.
	*/
	next = MR_trace_find_prev_contour(prev);
	while (MR_trace_node_port(next) != MR_PORT_EXIT
		|| MR_trace_node_seqno(next) != event_info->MR_call_seqno)
	{
		next = MR_trace_step_left_in_contour(next);
	}
	MR_decl_checkpoint_match(next);

	MR_TRACE_CALL_MERCURY(
		MR_trace_node_store++;
		if (!MR_DD_trace_node_call(MR_trace_node_store, (Word) next,
					(Word *) &call))
		{
			MR_fatal_error("MR_trace_decl_redo: no matching EXIT");
		}
	);
#endif /* !MR_USE_DECL_STACK_SLOT */

	MR_TRACE_CALL_MERCURY(
		last_interface = MR_DD_call_node_get_last_interface(
					(Word) call);
		node = (MR_Trace_Node) MR_DD_construct_redo_node(
					(Word) prev,
					last_interface);
		MR_DD_call_node_set_last_interface((Word) call, (Word) node);
	);

	return node;
}

static	MR_Trace_Node
MR_trace_decl_fail(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		next;
	MR_Trace_Node		call;
	Word			redo;

#ifdef MR_USE_DECL_STACK_SLOT
	call = MR_trace_decl_get_slot(event_info->MR_event_sll->MR_sll_entry,
				event_info->MR_saved_regs);
#else
	if (MR_trace_node_port(prev) == MR_PORT_CALL)
	{
		/*
		** We are already at the corresponding call, so there
		** is no need to search for it.
		*/
		call = prev;
	}
	else
	{
		next = MR_trace_find_prev_contour(prev);
		call = MR_trace_matching_call(next);
	}
	MR_decl_checkpoint_match(call);
#endif

	MR_TRACE_CALL_MERCURY(
		redo = MR_DD_call_node_get_last_interface( (Word) call);
		node = (MR_Trace_Node) MR_DD_construct_fail_node(
					(Word) prev, (Word) call, (Word) redo,
					(Word) event_info->MR_event_number);
		MR_DD_call_node_set_last_interface((Word) call, (Word) node);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_cond(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;

	MR_TRACE_CALL_MERCURY(
		node = (MR_Trace_Node) MR_DD_construct_cond_node(
					(Word) prev,
					(String) event_info->MR_event_path);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_then(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		next;
	MR_Trace_Node		cond;
	const char		*path = event_info->MR_event_path;

	/*
	** Search through current contour for a matching COND event.
	*/
	next = prev;
	while (!MR_trace_matching_cond(path, next))
	{
		next = MR_trace_step_left_in_contour(next);
	}
	cond = next;
	MR_decl_checkpoint_match(cond);
	
	MR_TRACE_CALL_MERCURY(
		MR_DD_cond_node_set_status((Word) cond,
					MR_TRACE_STATUS_SUCCEEDED);
		node = (MR_Trace_Node) MR_DD_construct_then_node(
					(Word) prev,
					(Word) cond);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_else(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		cond;
	const char		*path = event_info->MR_event_path;

	/*
	** Search through previous contour for a matching COND event.
	*/
	if (MR_trace_matching_cond(path, prev))
	{
		cond = prev;
	}
	else
	{
		MR_Trace_Node		next;

		next = prev;
		while (!MR_trace_matching_cond(path, next))
		{
			next = MR_trace_step_left_in_contour(next);
		}
		cond = next;
	}
	MR_decl_checkpoint_match(cond);
	
	MR_TRACE_CALL_MERCURY(
		MR_DD_cond_node_set_status((Word) cond,
					MR_TRACE_STATUS_FAILED);
		node = (MR_Trace_Node) MR_DD_construct_else_node(
					(Word) prev,
					(Word) cond);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_neg_enter(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;

	MR_TRACE_CALL_MERCURY(
		node = (MR_Trace_Node) MR_DD_construct_neg_node(
					(Word) prev,
					(String) event_info->MR_event_path);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_neg_success(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		nege;
	const char		*path = event_info->MR_event_path;

	/*
	** Search through previous contour for a matching NEGE event.
	*/
	if (MR_trace_matching_neg(path, prev))
	{
		nege = MR_trace_current_node;
	}
	else
	{
		MR_Trace_Node		next;

		next = prev;
		while (!MR_trace_matching_neg(path, next))
		{
			next = MR_trace_step_left_in_contour(next);
		}
		nege = next;
	}
	MR_decl_checkpoint_match(nege);
	
	MR_TRACE_CALL_MERCURY(
		MR_DD_neg_node_set_status((Word) nege,
					MR_TRACE_STATUS_SUCCEEDED);
		node = (MR_Trace_Node) MR_DD_construct_neg_succ_node(
						(Word) prev,
						(Word) nege);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_neg_failure(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	MR_Trace_Node		next;

	/*
	** Search through current contour for a matching NEGE event.
	*/
	next = prev;
	while (!MR_trace_matching_neg(event_info->MR_event_path, next))
	{
		next = MR_trace_step_left_in_contour(next);
	}
	MR_decl_checkpoint_match(next);
	
	MR_TRACE_CALL_MERCURY(
		MR_DD_neg_node_set_status((Word) next,
					MR_TRACE_STATUS_FAILED);
		node = (MR_Trace_Node) MR_DD_construct_neg_fail_node(
						(Word) prev,
						(Word) next);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_switch(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;

	MR_TRACE_CALL_MERCURY(
		node = (MR_Trace_Node) MR_DD_construct_switch_node(
					(Word) prev,
					(String) event_info->MR_event_path);
	);
	return node;
}

static	MR_Trace_Node
MR_trace_decl_disj(MR_Event_Info *event_info, MR_Trace_Node prev)
{
	MR_Trace_Node		node;
	const char		*path = event_info->MR_event_path;

	if (MR_trace_first_disjunct(event_info))
	{
		MR_TRACE_CALL_MERCURY(
			node = (MR_Trace_Node) MR_DD_construct_first_disj_node(
					(Word) prev,
					(String) path);
		);
	}
	else
	{
		MR_Trace_Node		next;
		MR_Trace_Node		first;

		/*
		** Search through previous nodes for a matching DISJ event.
		*/
		next = MR_trace_find_prev_contour(prev);
		while (!MR_trace_matching_disj(path, next))
		{
			next = MR_trace_step_left_in_contour(next);
		}
		MR_decl_checkpoint_match(next);

		/*
		** Find the first disj event of this disjunction.
		*/
		first = MR_trace_node_first_disj(next);
		if (first == (MR_Trace_Node) NULL)
		{
			first = next;
		}

		MR_TRACE_CALL_MERCURY(
			node = (MR_Trace_Node) MR_DD_construct_later_disj_node(
						MR_trace_node_store,
						(Word) prev,
						(String) path,
						(Word) first);
		);
	}

	return node;
}

#ifdef MR_USE_DECL_STACK_SLOT

static	MR_Trace_Node
MR_trace_decl_get_slot(const MR_Stack_Layout_Entry *entry, Word *saved_regs)
{
	int			decl_slot;
	Word			*saved_sp;
	Word			*saved_curfr;
	MR_Trace_Node		node;
	
	decl_slot = entry->MR_sle_maybe_decl_debug;
	
	if (MR_DETISM_DET_STACK(entry->MR_sle_detism)) {
		saved_sp = (Word *) MR_saved_sp(saved_regs);
		node = (MR_Trace_Node) MR_based_stackvar(saved_sp, decl_slot);
	} else {
		saved_curfr = (Word *) MR_saved_curfr(saved_regs);
		node = (MR_Trace_Node) MR_based_framevar(saved_curfr,
							decl_slot);
	}
	
	return node;
}

static	void
MR_trace_decl_set_slot(const MR_Stack_Layout_Entry *entry,
		Word *saved_regs, MR_Trace_Node node)
{
	int			decl_slot;
	Word			*saved_sp;
	Word			*saved_curfr;
	
	decl_slot = entry->MR_sle_maybe_decl_debug;
	
	if (MR_DETISM_DET_STACK(entry->MR_sle_detism)) {
		saved_sp = (Word *) MR_saved_sp(saved_regs);
		MR_based_stackvar(saved_sp, decl_slot) = (Word) node;
	} else {
		saved_curfr = (Word *) MR_saved_curfr(saved_regs);
		MR_based_framevar(saved_curfr, decl_slot) = (Word) node;
	}
}

#endif /* MR_USE_DECL_STACK_SLOT */

static	MR_Trace_Node
MR_trace_matching_call(MR_Trace_Node node)
{
	MR_Trace_Node		next;

	/*
	** Search through contour for any CALL event.  Since there
	** is only one CALL event which can be reached, we assume it
	** is the correct one.
	*/
	next = node;
	while (MR_trace_node_port(next) != MR_PORT_CALL)
	{
		next = MR_trace_step_left_in_contour(next);
	}
	return next;
}

static	bool
MR_trace_first_disjunct(MR_Event_Info *event_info)
{
	const char		*path;

	/*
	** Return TRUE iff the last component of the path is "d1;".
	*/
	path = event_info->MR_event_path;
	while (*path)
	{
		if (MR_string_equal(path, "d1;"))
		{
			return TRUE;
		}
		path++;
	}

	return FALSE;
}
	
static	bool
MR_trace_matching_cond(const char *path, MR_Trace_Node node)
{
	MR_Trace_Port		port;
	const char		*node_path;

	MR_TRACE_CALL_MERCURY(
		port = (MR_Trace_Port) MR_DD_trace_node_port(node);
	);
	if (port != MR_PORT_COND)
	{
		return FALSE;
	}
	node_path = MR_trace_node_path(node);

	return MR_trace_same_construct(path, node_path);
}

static	bool
MR_trace_matching_neg(const char *path, MR_Trace_Node node)
{
	MR_Trace_Port		port;
	const char		*node_path;

	MR_TRACE_CALL_MERCURY(
		port = (MR_Trace_Port) MR_DD_trace_node_port(node);
	);
	if (port != MR_PORT_NEG_ENTER) {
		return FALSE;
	}
	node_path = MR_trace_node_path(node);

	return MR_trace_same_construct(path, node_path);
}

static	bool
MR_trace_matching_disj(const char *path, MR_Trace_Node node)
{
	MR_Trace_Port		port;
	const char		*node_path;

	MR_TRACE_CALL_MERCURY(
		port = (MR_Trace_Port) MR_DD_trace_node_port(node);
	);
	if (port == MR_PORT_DISJ) {
		node_path = MR_trace_node_path(node);
		return MR_trace_same_construct(path, node_path);
	} else {
		return FALSE;
	}
}

static	bool
MR_trace_same_construct(const char *p1, const char *p2)
{
	/*
	** Checks if the two arguments represent goals in the same
	** construct.  If both strings are identical up to the last
	** component, return TRUE, otherwise return FALSE.
	** If the arguments point to identical strings, return TRUE.
	*/
	while (*p1 == *p2) {
		if (*p1 == '\0' && *p2 == '\0') {
			return TRUE;	/* They are identical. */
		}
		if (*p1 == '\0' || *p2 == '\0') {
			return FALSE;	/* Different number of elements. */
		}

		p1++;
		p2++;
	}

	/*
	** If there is exactly one component left in each string, then
	** the goal paths match, otherwise they don't.
	*/
	return MR_trace_single_component(p1) && MR_trace_single_component(p2);
}

static	bool
MR_trace_single_component(const char *path)
{
	while (*path != ';') {
		if (*path == '\0') {
			return FALSE;
		}
		path++;
	}
	path++;
	return (*path == '\0');
}

static	Word
MR_decl_make_atom(const MR_Stack_Layout_Label *layout, Word *saved_regs,
		MR_Trace_Port port)
{
	ConstString			name;
	Word				arity;
	Word				atom;
	int				i;
	const MR_Stack_Layout_Vars	*vars;
	int				arg_count;
	MR_TypeInfoParams		type_params;
	const MR_Stack_Layout_Entry	*entry = layout->MR_sll_entry;

	MR_trace_init_point_vars(layout, saved_regs, port);

	name = MR_decl_atom_name(entry);
	if (MR_ENTRY_LAYOUT_COMPILER_GENERATED(layout->MR_sll_entry)) {
		arity = entry->MR_sle_comp.MR_comp_arity;
	} else {
		arity = entry->MR_sle_user.MR_user_arity;
	}
	MR_TRACE_CALL_MERCURY(
		atom = MR_DD_construct_trace_atom((String) name, (Word) arity);
	);

	arg_count = MR_trace_var_count();
	for (i = 1; i <= arg_count; i++) {
		Word		arg;
		MR_TypeInfo	arg_type;
		Word		arg_value;
		int		arg_pos;
		const char	*problem;

		problem = MR_trace_return_var_info(i, NULL, &arg_type,
					&arg_value);
		if (problem != NULL) {
			MR_fatal_error(problem);
		}

		problem = MR_trace_headvar_num(i, &arg_pos);
		if (problem != NULL) {
			MR_fatal_error(problem);
		}

		MR_TRACE_USE_HP(
			tag_incr_hp(arg, MR_mktag(0), 2);
		);
		MR_field(MR_mktag(0), arg, UNIV_OFFSET_FOR_TYPEINFO) =
				(Word) arg_type;
		MR_field(MR_mktag(0), arg, UNIV_OFFSET_FOR_DATA) =
				arg_value;

		MR_TRACE_CALL_MERCURY(
			atom = MR_DD_add_trace_atom_arg(atom,
						(Word) arg_pos, arg);
		);
	}

	return atom;
}

static	ConstString
MR_decl_atom_name(const MR_Stack_Layout_Entry *entry)
{
	ConstString		name;

	if (MR_ENTRY_LAYOUT_HAS_PROC_ID(entry)) {
		if (MR_ENTRY_LAYOUT_COMPILER_GENERATED(entry)) {
			MR_TRACE_USE_HP(
				MR_make_aligned_string(name, "<<internal>>");
			);
		} else {
			name = entry->MR_sle_proc_id.MR_proc_user.MR_user_name;
		}
	} else {
		MR_TRACE_USE_HP(
			MR_make_aligned_string(name, "<<unknown>>");
		);
	}

	return name;
}

static	void
MR_trace_decl_ensure_init(void)
{
	static bool		done = FALSE;
	static MercuryFile	mdb_in;
	static MercuryFile	mdb_out;

	mdb_in.file = MR_mdb_in;
	mdb_in.line_number = 1;
	mdb_out.file = MR_mdb_out;
	mdb_out.line_number = 1;

	if (! done) {
		MR_TRACE_CALL_MERCURY(
			MR_trace_node_store = 0;
			MR_DD_decl_diagnosis_state_init(
					(Word) &mdb_in,
					(Word) &mdb_out,
					&MR_trace_front_end_state);
		);
		done = TRUE;
	}
}

bool
MR_trace_start_decl_debug(const char *outfile, MR_Trace_Cmd_Info *cmd,
		MR_Event_Info *event_info, MR_Event_Details *event_details,
		Code **jumpaddr)
{
	MR_Stack_Layout_Entry 	*entry;
	FILE			*out;
	Unsigned		depth_limit;
	const char		*message;

	entry = event_info->MR_event_sll->MR_sll_entry;
	if (!MR_ENTRY_LAYOUT_HAS_EXEC_TRACE(entry)) {
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err, "mdb: cannot start declarative debugging, "
				"because this procedure was not\n"
				"compiled with execution tracing enabled.\n");
		return FALSE;
	}

	if (MR_ENTRY_LAYOUT_COMPILER_GENERATED(entry)) {
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err, "mdb: cannot start declarative debugging "
				"at compiler generated procedures.\n");
		return FALSE;
	}

#ifdef MR_USE_DECL_STACK_SLOT
	if (entry->MR_sle_maybe_decl_debug < 1) {
		/* No slots are reserved for declarative debugging */
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err, "mdb: cannot start declarative debugging, "
				"because this procedure was not\n"
				"compiled with stack slots reserved.\n");
		return FALSE;
	}
#endif /* MR_USE_DECL_STACK_SLOT */

	if (outfile == (const char *) NULL) {
		/* Normal debugging mode */
		MR_trace_decl_mode = MR_TRACE_DECL_DEBUG;
	} else {
		/* Test mode */
		out = fopen(outfile, "w");
		if (out == NULL) {
			fflush(MR_mdb_out);
			fprintf(MR_mdb_err, "mdb: cannot open file `%s' "
					"for output: %s.\n",
					outfile, strerror(errno));
			return FALSE;
		} else {
			MR_trace_decl_mode = MR_TRACE_DECL_DEBUG_TEST;
			MR_trace_store_file = out;
		}
	}

	MR_trace_decl_ensure_init();
	depth_limit = event_info->MR_call_depth + MR_EDT_DEPTH_STEP_SIZE;
	message = MR_trace_start_collecting(event_info->MR_event_number,
			event_info->MR_call_seqno, depth_limit, cmd,
			event_info, event_details, jumpaddr);

	if (message == NULL) {
		return TRUE;
	} else {
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err,
			"mdb: failed to start collecting events:\n%s\n",
			message);

		return FALSE;
	}
}

static	Code *
MR_trace_restart_decl_debug(Unsigned event, Unsigned seqno,
		MR_Trace_Cmd_Info *cmd, MR_Event_Info *event_info,
		MR_Event_Details *event_details)
{
	Unsigned		depth_limit;
	const char		*message;
	Code			*jumpaddr;

	depth_limit = MR_edt_max_depth + MR_EDT_DEPTH_STEP_SIZE;
	message = MR_trace_start_collecting(event, seqno, depth_limit,
			cmd, event_info, event_details, &jumpaddr);

	if (message != NULL) {
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err, "mdb: diagnosis aborted:\n%s\n", message);
		MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
		MR_trace_enabled = TRUE;
		return MR_trace_event_internal(cmd, TRUE, event_info);
	}

	return jumpaddr;
}

static	const char *
MR_trace_start_collecting(Unsigned event, Unsigned seqno, Unsigned maxdepth,
		MR_Trace_Cmd_Info *cmd, MR_Event_Info *event_info,
		MR_Event_Details *event_details, Code **jumpaddr)
{
	const char		*message;

	/*
	** Go back to an event before the topmost call.
	*/
	message = MR_trace_retry(event_info, event_details, jumpaddr);
	if (message != NULL) {
		return message;
	}

	/*
	** Start collecting the trace from the desired call, with the
	** desired depth bound.
	*/
	MR_edt_last_event = event;
	MR_edt_inside = FALSE;
	MR_edt_start_seqno = seqno;
	MR_edt_max_depth = maxdepth;
	MR_trace_current_node = (MR_Trace_Node) NULL;

	/*
	** Restore globals from the saved copies.
	*/
        MR_trace_call_seqno = event_details->MR_call_seqno;
	MR_trace_call_depth = event_details->MR_call_depth;
	MR_trace_event_number = event_details->MR_event_number;

	/*
	** Single step through every event.
	*/
	cmd->MR_trace_cmd = MR_CMD_GOTO;
	cmd->MR_trace_stop_event = 0;
	cmd->MR_trace_strict = TRUE;
	cmd->MR_trace_print_level = MR_PRINT_LEVEL_NONE;
	cmd->MR_trace_must_check = FALSE;

	MR_trace_enabled = TRUE;
	return NULL;
}

static	Code *
MR_decl_diagnosis(MR_Trace_Node root, MR_Trace_Cmd_Info *cmd,
		MR_Event_Info *event_info, MR_Event_Details *event_details)
{
	Word			response;
	bool			bug_found;
	bool			require_subtree;
	Unsigned		bug_event;
	Unsigned		final_event;
	Unsigned		topmost_seqno;

#if 0
	/*
	** This is a quick and dirty way to debug the front end.
	*/
	MR_trace_enabled = TRUE;
#endif

	MR_TRACE_CALL_MERCURY(
		MR_DD_decl_diagnosis(MR_trace_node_store, root, &response,
				MR_trace_front_end_state,
				&MR_trace_front_end_state
			);
		bug_found = MR_DD_diagnoser_bug_found(response,
				(Word *) &bug_event);
		require_subtree = MR_DD_diagnoser_require_subtree(response,
				(Word *) &final_event,
				(Word *) &topmost_seqno);
	);

	if (bug_found) {
		return MR_decl_handle_bug_found(bug_event, cmd,
				event_info, event_details);
	}

	if (require_subtree) {
		/*
		** Front end requires a subtree to be made explicit.
		** Restart the declarative debugger with deeper
		** depth limit.
		*/
		return MR_trace_restart_decl_debug(final_event, topmost_seqno,
				cmd, event_info, event_details);
	}

	/*
	** No bug found.  Return to the procedural debugger at the
	** current event, which was the event it was left from.
	*/
	MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
	MR_trace_enabled = TRUE;
	return MR_trace_event_internal(cmd, TRUE, event_info);
}

static	Code *
MR_decl_handle_bug_found(Unsigned bug_event, MR_Trace_Cmd_Info *cmd,
		MR_Event_Info *event_info, MR_Event_Details *event_details)
{
	const char		*message;
	Code			*jumpaddr;

	/*
	** Perform a retry to get to somewhere before the
	** bug event.  Then set the command to go to the bug
	** event and return to interactive mode.
	*/
	message = MR_trace_retry(event_info, event_details, &jumpaddr);
	if (message != NULL) {
		fflush(MR_mdb_out);
		fprintf(MR_mdb_err, "mdb: diagnosis aborted:\n%s\n", message);
		MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
		MR_trace_enabled = TRUE;
		return MR_trace_event_internal(cmd, TRUE, event_info);
	}

	cmd->MR_trace_cmd = MR_CMD_GOTO;
	cmd->MR_trace_stop_event = bug_event;
	cmd->MR_trace_print_level = MR_PRINT_LEVEL_NONE;
	cmd->MR_trace_strict = TRUE;
	cmd->MR_trace_must_check = FALSE;
	MR_trace_decl_mode = MR_TRACE_INTERACTIVE;
	MR_trace_enabled = TRUE;
	return jumpaddr;
}

static	void
MR_decl_diagnosis_test(MR_Trace_Node root)
{
	MercuryFile		stream;

	stream.file = MR_trace_store_file;
	stream.line_number = 1;

	MR_TRACE_CALL_MERCURY(
		MR_DD_save_trace((Word) &stream, MR_trace_node_store, root);
	);

	fclose(MR_trace_store_file);
}

static	String
MR_trace_node_path(MR_Trace_Node node)
{
	String			path;

	MR_trace_node_store++;
	MR_TRACE_CALL_MERCURY(
		path = MR_DD_trace_node_path(MR_trace_node_store, (Word) node);
	);
	return path;
}

static	MR_Trace_Port
MR_trace_node_port(MR_Trace_Node node)
{
	MR_Trace_Port		port;

	MR_TRACE_CALL_MERCURY(
		port = (MR_Trace_Port) MR_DD_trace_node_port((Word) node);
	);
	return port;
}

static	Unsigned
MR_trace_node_seqno(MR_Trace_Node node)
{
	Unsigned		seqno;

	MR_trace_node_store++;
	MR_TRACE_CALL_MERCURY(
		if (!MR_DD_trace_node_seqno(MR_trace_node_store,
					(Word) node,
					(Word *) &seqno))
		{
			MR_fatal_error("MR_trace_node_seqno: "
				"not an interface event");
		}
	);
	return seqno;
}

static	MR_Trace_Node
MR_trace_node_first_disj(MR_Trace_Node node)
{
	MR_Trace_Node		first;

	MR_TRACE_CALL_MERCURY(
		if (!MR_DD_trace_node_first_disj((Word) node, (Word *) &first))
		{
			MR_fatal_error("MR_trace_node_first_disj: "
				"not a DISJ event");
		}
	);
	return first;
}

static	MR_Trace_Node
MR_trace_step_left_in_contour(MR_Trace_Node node)
{
	MR_Trace_Node		next;

	MR_decl_checkpoint_step(node);

	MR_trace_node_store++;
	MR_TRACE_CALL_MERCURY(
		next = (MR_Trace_Node) MR_DD_step_left_in_contour(
						MR_trace_node_store, node);
	);
	return next;
}

static	MR_Trace_Node
MR_trace_find_prev_contour(MR_Trace_Node node)
{
	MR_Trace_Node		next;

	MR_decl_checkpoint_find(node);

	MR_trace_node_store++;
	MR_TRACE_CALL_MERCURY(
		next = (MR_Trace_Node) MR_DD_find_prev_contour(
						MR_trace_node_store, node);
	);
	return next;
}

#ifdef MR_DEBUG_DD_BACK_END

static	void
MR_decl_checkpoint_event_imp(const char *str, MR_Event_Info *event_info)
{
	fprintf(MR_mdb_out, "DD %s %ld: #%ld %ld %s ",
			str,
			(long) event_info->MR_event_number,
			(long) event_info->MR_call_seqno,
			(long) event_info->MR_call_depth,
			MR_port_names[event_info->MR_trace_port]);
	MR_print_proc_id(MR_mdb_out, event_info->MR_event_sll->MR_sll_entry);
	fprintf(MR_mdb_out, "\n");
}

static	void
MR_decl_checkpoint_loc(const char *str, MR_Trace_Node node)
{
	MercuryFile		mdb_out;

	mdb_out.file = MR_mdb_out;
	mdb_out.line_number = 1;

	fprintf(MR_mdb_out, "DD %s: %ld ", str, (long) node);
	MR_TRACE_CALL_MERCURY(
		MR_DD_print_trace_node((Word) &mdb_out, (Word) node);
	);
	fprintf(MR_mdb_out, "\n");
}

#endif /* MR_DEBUG_DD_BACK_END */

#endif /* defined(MR_USE_DECLARATIVE_DEBUGGER) */
