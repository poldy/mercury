/*
** Copyright (C) 2002 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_trace_completion.c
**
** Main author: stayl
**
** Command line completion for mdb.
*/

#include "mercury_memory.h"
#include "mercury_std.h"
#include "mercury_array_macros.h"
#include "mercury_trace_completion.h"
#include "mercury_trace_internal.h"
#include "mercury_trace_alias.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef MR_NO_USE_READLINE
  #ifdef MR_HAVE_READLINE_READLINE
    #include <readline/readline.h>
  #else
    extern char *rl_line_buffer;
    extern int rl_point;
    extern char *filename_completion_function(char *word, int state);
  #endif
#endif

	/*
	** Complete on NULL terminated array of strings.
	** The strings will not be `free'd.
	*/
static  MR_Completer_List *MR_trace_string_array_completer(
				const char *const *strings);

static  char *MR_trace_completer_list_next(const char *word,
		size_t word_len, MR_Completer_List **list);
static	void MR_trace_free_completer_list(MR_Completer_List *completer_list);

static	char *MR_prepend_string(char *completion, MR_Completer_Data *data);

/*---------------------------------------------------------------------------*/
/*
** Called by Readline when the user requests completion.
** Examine Readline's input buffer to work out which completers
** should be used, then apply them.
** Readline passes zero for `state' on the first call, and non-zero
** on subsequent calls.
*/

char *MR_trace_line_completer(const char *passed_word, int state)
{
#ifdef MR_NO_USE_READLINE
    return NULL;
#else
    static MR_Completer_List	*completer_list;
    static char			*word;
    static size_t		word_len;
    char			*completion;

    /*
    ** If `state' is 0, this is the first call for this `word',
    ** so set up the list of completers.
    */
    if (state == 0) {
	char *line;
	char *command_end;
	char *command_start;
	char *insertion_point;
	char *semicolon;

	MR_trace_free_completer_list(completer_list);
	completer_list = NULL;
	if (word != NULL) {
		MR_free(word);
	}

	line = rl_line_buffer;
	insertion_point = rl_line_buffer + rl_point;

	/*
	** There may be multiple commands in the line.
	** Skip to the one we are trying to complete.
	*/
	semicolon = strchr(line, ';');	
	while (semicolon != NULL && semicolon < insertion_point) {
		line = semicolon + 1;
		semicolon = strchr(line, ';');	
	}
	
	/* Skip space or a number at the beginning of the command. */
	while (line < insertion_point &&
			(MR_isspace(*line) || MR_isdigit(*line)))
	{
		line++;
	}

	/* Find the end of the command. */
	command_start = line;
	command_end = line;
	while (command_end < insertion_point && !MR_isspace(*command_end)) {
		command_end++;
	}

	if (command_end == insertion_point) {
		/*
		** We're completing the command itself.
		*/

		int			num_digits;
		char			*digits;
		MR_Completer_List	*command_completer;
		MR_Completer_List	*alias_completer;

		/*
		** Strip off any number preceding the command
		** (it will need to be added back later).
		*/
		num_digits = 0;
		while (MR_isdigit(passed_word[num_digits])) {
			num_digits++;
		} 
		word = MR_copy_string(passed_word + num_digits);
		word_len = strlen(word);

		/*
		** Set up completers for commands and aliases.
		*/
		command_completer = MR_trace_command_completer(word, word_len);
		alias_completer = MR_trace_alias_completer(word, word_len);

		completer_list = command_completer;
		completer_list->MR_completer_list_next = alias_completer;

		/*
		** Add back the preceding number to the completions.
		*/
		if (num_digits != 0) {
			digits = MR_malloc(num_digits + 1);
			strncpy(digits, passed_word, num_digits);
			digits[num_digits] = '\0';
			completer_list =
				MR_trace_map_completer(MR_prepend_string,
					digits, MR_free_func, completer_list);
		}
	} else {
		/*
		** We're completing an argument of the command.
		*/
		#define MR_MAX_COMMAND_NAME_LEN 256
		char command[MR_MAX_COMMAND_NAME_LEN];
		char *expanded_command;
		int command_len;
		char **words;
		int word_count;
		MR_Make_Completer command_completer;
		const char *const *command_fixed_args;
		MR_Completer_List *arg_completer;

		command_len = command_end - command_start;
		if (command_len >= MR_MAX_COMMAND_NAME_LEN) {
			/* The string is too long to be a command. */
			return NULL;
		} else {
			strncpy(command, command_start, command_len);
			command[command_len] = '\0';
		}

		/* Expand aliases. */
		if (MR_trace_lookup_alias(command, &words, &word_count)) {
			if (word_count == 0) {
				return NULL;
			} else {
				expanded_command = words[0];
			}
		} else {
			expanded_command = command;	
		}

		if (! MR_trace_command_completion_info(expanded_command,
			&command_completer, &command_fixed_args))
		{
			return NULL;
		}

		/* Set up a completer for the fixed argument strings. */
		completer_list = NULL;
		if (command_fixed_args != NULL) {
			completer_list = MR_trace_string_array_completer(
				command_fixed_args);
		}

		word = MR_copy_string(passed_word);
		word_len = strlen(word);

		/* Set up a completer for the non-fixed argument strings. */
		arg_completer = (*command_completer)(word, word_len);
		if (completer_list == NULL) {
			completer_list = arg_completer;
		} else {
			completer_list->MR_completer_list_next = arg_completer;
		}
	}
    }
    completion = MR_trace_completer_list_next(word, word_len, &completer_list);
    if (completion == NULL) {
	    MR_trace_free_completer_list(completer_list);
	    MR_free(word);
	    word = NULL;
    }
    return completion;
#endif /* ! MR_NO_USE_READLINE */
}

static char *
MR_prepend_string(char *string, MR_Completer_Data *data)
{
	char	*string_to_prepend;
	int	string_to_prepend_len;
	char	*result;

	string_to_prepend = (char *) *data;
	string_to_prepend_len = strlen(string_to_prepend);
	result = MR_malloc(string_to_prepend_len + strlen(string) + 1);	
	strcpy(result, string_to_prepend);
	strcpy(result + string_to_prepend_len, string);
	MR_free(string);
	return result;
}

/*---------------------------------------------------------------------------*/

static char *
MR_trace_completer_list_next(const char *word, size_t word_len,
		MR_Completer_List **list)
{
	MR_Completer_List	*current_completer;
	char			*result;

	if (list == NULL) {
		return NULL;
	}

	while (1) {
		current_completer = *list;
		if (!current_completer) {
			return NULL;
		}
		result = (current_completer->MR_completer_func)(word, word_len,
				&(current_completer->MR_completer_func_data));
		if (result != NULL) {
			return result;
		} else {
			*list = current_completer->MR_completer_list_next;
			(current_completer->MR_free_completer_func_data)(
				current_completer->MR_completer_func_data);
			MR_free(current_completer);
		}
	}
}

static void
MR_trace_free_completer_list(MR_Completer_List *completer_list)
{
	MR_Completer_List *tmp_list;
	while (completer_list != NULL) {
		tmp_list = completer_list;
		completer_list = completer_list->MR_completer_list_next;
		(tmp_list->MR_free_completer_func_data)(
				tmp_list->MR_completer_func_data);
		MR_free(tmp_list);
	}
}

/*---------------------------------------------------------------------------*/
/* No completions. */

MR_Completer_List *
MR_trace_null_completer(const char *word, size_t word_len)
{
	return NULL;
}

/*---------------------------------------------------------------------------*/
/* Complete on the labels of a sorted array. */

typedef struct {
	MR_Get_Slot_Name	MR_sorted_array_get_slot_name;
	int			MR_sorted_array_current_offset;
	int			MR_sorted_array_size;
} MR_Sorted_Array_Completer_Data;

static	char *MR_trace_sorted_array_completer_next(const char *word,
		size_t word_length, MR_Completer_Data *data);

MR_Completer_List *
MR_trace_sorted_array_completer(const char *word, size_t word_length,
		int array_size, MR_Get_Slot_Name get_slot_name)
{
	MR_Completer_List		*completer;
	MR_bool				found;
	int				slot;
	MR_Sorted_Array_Completer_Data	*data;

	/*
	** Find the slot containing the first possible match,
	** optimizing for the common case where we are finding
	** all elements in the array.
	*/
	if (word_length == 0) {
		found = (array_size != 0);
		slot = 0;
	} else {
		MR_find_first_match(array_size, slot, found,
			strncmp(get_slot_name(slot), word, word_length)); 
	}

	if (found) {
		data = MR_NEW(MR_Sorted_Array_Completer_Data);
		data->MR_sorted_array_get_slot_name = get_slot_name;
		data->MR_sorted_array_current_offset = slot;
		data->MR_sorted_array_size = array_size;
		(completer) = MR_new_completer_elem(
			MR_trace_sorted_array_completer_next,
			(MR_Completer_Data) data, MR_free_func);
	} else {
		(completer) = NULL;
	}
	return completer;
}

static char *
MR_trace_sorted_array_completer_next(const char *word,
	size_t word_length, MR_Completer_Data *completer_data)
{
	MR_Sorted_Array_Completer_Data *data;
	char *completion;

	data = (MR_Sorted_Array_Completer_Data *) *completer_data;
	
	if (data->MR_sorted_array_current_offset
			< data->MR_sorted_array_size)
	{
		completion = data->MR_sorted_array_get_slot_name(
				data->MR_sorted_array_current_offset);
		if (MR_strneq(completion, word, word_length)) {
			data->MR_sorted_array_current_offset++;
			return MR_copy_string(completion);
		} else {
			return NULL;
		}
	} else {
		return NULL;
	}
}

/*---------------------------------------------------------------------------*/
/* Complete on the elements of an unsorted array of strings. */

typedef struct MR_String_Array_Completer_Data_struct {
	char			**MR_string_array;
	int			MR_string_array_current_offset;
} MR_String_Array_Completer_Data;

static  char *MR_trace_string_array_completer_next(const char *word,
		size_t word_len, MR_Completer_Data *data);

static MR_Completer_List *
MR_trace_string_array_completer(const char *const *strings)
{
	MR_String_Array_Completer_Data *data;
	data = MR_NEW(MR_String_Array_Completer_Data);
	data->MR_string_array = (char **) strings;
	data->MR_string_array_current_offset = 0;
	return MR_new_completer_elem(&MR_trace_string_array_completer_next,
		(MR_Completer_Data) data, MR_free_func);
}

static char *
MR_trace_string_array_completer_next(const char *word, size_t word_len,
		MR_Completer_Data *data)
{
	MR_String_Array_Completer_Data *completer_data;
	char *result;

	completer_data = (MR_String_Array_Completer_Data *) *data;

	while (1) {
		result = completer_data->MR_string_array[
			completer_data->MR_string_array_current_offset];
		completer_data->MR_string_array_current_offset++;
		if (result == NULL) {
			return NULL;
		} else {
			if (strncmp(result, word, word_len) == 0) {
				return MR_copy_string(result);
			}
		}
	}
}

/*---------------------------------------------------------------------------*/
/* Use Readline's filename completer. */

static  char *MR_trace_filename_completer_next(const char *word,
		size_t word_len, MR_Completer_Data *);

MR_Completer_List *
MR_trace_filename_completer(const char *word, size_t word_len)
{
	return MR_new_completer_elem(&MR_trace_filename_completer_next,
		(MR_Completer_Data) 0, MR_trace_no_free);
}

static char *
MR_trace_filename_completer_next(const char *word, size_t word_len,
		MR_Completer_Data *data)
{
	int state;
	state = (int) *data;
	*data = (MR_Completer_Data) 1;
	return filename_completion_function((char *) word, state);
}

/*---------------------------------------------------------------------------*/
/* Apply a filter to the output of a completer. */

typedef struct {
	MR_Completer_Filter	MR_filter_func;
	MR_Completer_Data	MR_filter_data;
	MR_Free_Completer_Data	MR_filter_free_data;
	MR_Completer_List *	MR_filter_list;
} MR_Filter_Completer_Data;

static  char *MR_trace_filter_completer_next(const char *word,
		size_t word_len, MR_Completer_Data *);
static	void MR_trace_free_filter_completer_data(MR_Completer_Data data);

MR_Completer_List *
MR_trace_filter_completer(MR_Completer_Filter filter,
			MR_Completer_Data filter_data,
			MR_Free_Completer_Data free_filter_data,
			MR_Completer_List *list)
{
	MR_Filter_Completer_Data *data;

	data = MR_NEW(MR_Filter_Completer_Data);
	data->MR_filter_func = filter;
	data->MR_filter_data = filter_data;
	data->MR_filter_free_data = free_filter_data;
	data->MR_filter_list = list;
	return MR_new_completer_elem(MR_trace_filter_completer_next,
		(MR_Completer_Data) data, MR_trace_free_filter_completer_data);
}

static char *
MR_trace_filter_completer_next(const char *word, size_t word_len,
		MR_Completer_Data *completer_data)
{
	MR_Filter_Completer_Data *data;
	char *completion;

	data = (MR_Filter_Completer_Data *) *completer_data;
	while (1) {
		completion = MR_trace_completer_list_next(word, word_len,
				&data->MR_filter_list);
		if (completion == NULL) {
			return NULL;
		} else if (data->MR_filter_func(completion,
				&(data->MR_filter_data)))
		{
			return completion;
		} else {
			MR_free(completion);
		}
	}
}

static void
MR_trace_free_filter_completer_data(MR_Completer_Data completer_data)
{
	MR_Filter_Completer_Data *data;

	data = (MR_Filter_Completer_Data *) completer_data;
	data->MR_filter_free_data(data->MR_filter_data);
	MR_trace_free_completer_list(data->MR_filter_list);
	MR_free(data);
}

/*---------------------------------------------------------------------------*/
/* Apply a mapping function to the output of a completer. */

typedef struct {
	MR_Completer_Map	MR_map_func;
	MR_Completer_Data	MR_map_data;
	MR_Free_Completer_Data	MR_map_free_data;
	MR_Completer_List *	MR_map_list;
} MR_Map_Completer_Data;

static  char *MR_trace_map_completer_next(const char *word,
		size_t word_len, MR_Completer_Data *);
static	void MR_trace_free_map_completer_data(MR_Completer_Data data);

MR_Completer_List *
MR_trace_map_completer(MR_Completer_Map map, MR_Completer_Data map_data,
			MR_Free_Completer_Data free_data,
			MR_Completer_List *list)
{
	MR_Map_Completer_Data *data;

	data = MR_NEW(MR_Map_Completer_Data);
	data->MR_map_func = map;
	data->MR_map_data = map_data;
	data->MR_map_free_data = free_data;
	data->MR_map_list = list;
	return MR_new_completer_elem(MR_trace_map_completer_next,
		(MR_Completer_Data) data, MR_trace_free_map_completer_data);
}

static char *
MR_trace_map_completer_next(const char *word, size_t word_len,
		MR_Completer_Data *completer_data)
{
	MR_Map_Completer_Data	*data;
	char			*completion;

	data = (MR_Map_Completer_Data *) *completer_data;
	completion = MR_trace_completer_list_next(word, word_len,
				&data->MR_map_list);
	if (completion == NULL) {
		return NULL;
	} else {
		return data->MR_map_func(completion, &(data->MR_map_data));
	}
}

static void
MR_trace_free_map_completer_data(MR_Completer_Data completer_data)
{
	MR_Map_Completer_Data *data;

	data = (MR_Map_Completer_Data *) completer_data;
	data->MR_map_free_data(data->MR_map_data);
	MR_trace_free_completer_list(data->MR_map_list);
	MR_free(data);
}

/*---------------------------------------------------------------------------*/

MR_Completer_List *
MR_new_completer_elem(MR_Completer completer, MR_Completer_Data data,
		MR_Free_Completer_Data free_data)
{
	MR_Completer_List *result;
	result = MR_NEW(MR_Completer_List);
	result->MR_completer_func = completer;
	result->MR_completer_func_data = data;
	result->MR_free_completer_func_data = free_data;
	result->MR_completer_list_next = NULL;
	return result;
}

void
MR_trace_no_free(MR_Completer_Data data)
{
}

