/*
** Copyright (C) 1998 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_trace_browse.c
**
** Main author: fjh
**
** This file provides the C interface to browser/browse.m.
*/

/*
** Some header files refer to files automatically generated by the Mercury
** compiler for modules in the browser and library directories.
**
** XXX figure out how to prevent these names from encroaching on the user's
** name space.
*/

#include "mercury_imp.h"
#include "mercury_trace_browse.h"
#include "mercury_trace_util.h"
#include "mercury_deep_copy.h"
#include "browse.h"
#include "std_util.h"
#include <stdio.h>

static	Word		MR_trace_browser_state;
static	Word		MR_trace_browser_state_type;

static	void		MR_trace_browse_ensure_init(void);

void
MR_trace_browse(Word type_info, Word value)
{
	MR_trace_browse_ensure_init();
	MR_TRACE_CALL_MERCURY(
		ML_BROWSE_browse(type_info, value, MR_trace_browser_state,
			&MR_trace_browser_state);
	);
	MR_trace_browser_state = MR_make_permanent(MR_trace_browser_state,
				(Word *) MR_trace_browser_state_type);
}

void
MR_trace_print(Word type_info, Word value)
{
	MR_trace_browse_ensure_init();
	MR_TRACE_CALL_MERCURY(
		ML_BROWSE_print(type_info, value, MR_trace_browser_state);
	);
}

static void
MR_trace_browse_ensure_init(void)
{
	static	bool	done = FALSE;
	Word		typeinfo_type;

	if (! done) {
		MR_TRACE_CALL_MERCURY(
			ML_get_type_info_for_type_info(&typeinfo_type);
			ML_BROWSE_browser_state_type(
				&MR_trace_browser_state_type);
			ML_BROWSE_init_state(&MR_trace_browser_state);
		);

		MR_trace_browser_state_type = MR_make_permanent(
					MR_trace_browser_state_type,
					(Word *) typeinfo_type);
		MR_trace_browser_state = MR_make_permanent(
					MR_trace_browser_state,
					(Word *) MR_trace_browser_state_type);
		done = TRUE;
	}
}
