%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2006-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prog_event.m.
% Author: zs.
%
% This module defines the database of information the compiler has about
% events other than the built-in set of execution tracing events.
%
%-----------------------------------------------------------------------------%

:- module parse_tree.prog_event.
:- interface.

:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_event.

:- import_module io.
:- import_module list.

    % read_event_set(FileName, EventSetName, EventSpecMap, ErrorSpecs, !IO):
    %
    % Read in a set of event specifications from FileName, and return them
    % in EventSetName and EventSpecMap. Set ErrorSpecs to a list of all the
    % errors discovered during the process.
    %
:- pred read_event_set(string::in, string::out, event_spec_map::out,
    list(error_spec)::out, io::di, io::uo) is det.

    % Return a description of the given event set.
    %
:- func derive_event_set_data(event_set) = event_set_data.

    % Given an event name, returns its number.
    %
:- pred event_number(event_spec_map::in, string::in, int::out) is semidet.

    % Given an event name, returns the attributes of the event.
    %
:- pred event_attributes(event_spec_map::in, string::in,
    list(event_attribute)::out) is semidet.

    % Given an event name, returns the types of the arguments of the event.
    %
:- pred event_arg_types(event_spec_map::in, string::in, list(mer_type)::out)
    is semidet.

    % Given an event name, returns the modes of the arguments of the event.
    %
:- pred event_arg_modes(event_spec_map::in, string::in, list(mer_mode)::out)
    is semidet.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module libs.file_util.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.builtin_lib_types.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_type.

:- import_module assoc_list.
:- import_module bimap.
:- import_module digraph.
:- import_module int.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.

read_event_set(SpecsFileName, EventSetName, EventSpecMap, ErrorSpecs, !IO) :-
    % Currently, we convert the event specification file into a Mercury term
    % by using the yacc parser in the trace directory to create a C data
    % structure to represent its contents, writing out that data structure
    % as a Mercury term to a file (TermFileName), and then reading in the term
    % from that file.
    %
    % This is a clumsy approach, since it requires access to the C code in the
    % trace directory (via the event_spec library) and a temporary file.
    % Using Mercury scanners and parsers generated by mscangen and mparsegen
    % respectively would be a much better and more direct approach, but
    % those tools are not yet mature enough. When they are, we should switch
    % to using them.

    open_temp_input(TermFileResult, read_specs_file(SpecsFileName), !IO),
    (
        TermFileResult = ok({TermFileName, TermStream}),
        io.read(TermStream, TermReadRes, !IO),
        (
            TermReadRes = ok(EventSetTerm),
            EventSetTerm = event_set_spec(EventSetName,
                EventSpecsTerm),
            convert_list_to_spec_map(SpecsFileName, EventSpecsTerm,
                map.init, EventSpecMap, [], ErrorSpecs)
        ;
            TermReadRes = eof,
            EventSetName = "",
            EventSpecMap = map.init,
            Pieces = [words("eof in term specification file"), nl],
            ErrorSpec = error_spec(severity_error,
                phase_term_to_parse_tree,
                [error_msg(no, do_not_treat_as_first, 0,
                    [always(Pieces)])]),
            ErrorSpecs = [ErrorSpec]
        ;
            TermReadRes = error(TermReadMsg, LineNumber),
            EventSetName = "",
            EventSpecMap = map.init,
            Pieces = [words(TermReadMsg), nl],
            ErrorSpec = error_spec(severity_error,
                phase_term_to_parse_tree,
                [simple_msg(context(TermFileName, LineNumber),
                    [always(Pieces)])]),
            ErrorSpecs = [ErrorSpec]
        ),
        io.close_input(TermStream, !IO),
        io.remove_file(TermFileName, _RemoveRes, !IO)
    ;
        TermFileResult = error(ErrorMessage),
        EventSetName = "",
        EventSpecMap = map.init,
        Pieces = [words(ErrorMessage), nl],
        ErrorSpec = error_spec(severity_error,
            phase_term_to_parse_tree,
            [error_msg(no, do_not_treat_as_first, 0,
                [always(Pieces)])]),
        ErrorSpecs = [ErrorSpec]
    ).

:- pred read_specs_file(string::in, string::in, maybe_error::out,
    io::di, io::uo) is det.

read_specs_file(SpecsFile, TermFile, Result, !IO) :-
    read_specs_file_2(SpecsFile, TermFile, Problem, !IO),
    ( if Problem = "" then
        Result = ok
    else
        Result = error(Problem)
    ).

:- pragma foreign_decl("C",
"
#include ""mercury_event_spec.h""
#include <stdio.h>

MR_String   read_specs_file_2(MR_AllocSiteInfoPtr alloc_id,
                MR_String specs_file_name, MR_String term_file_name);
MR_String   read_specs_file_3(MR_AllocSiteInfoPtr alloc_id,
                MR_String specs_file_name, MR_String term_file_name,
                int spec_fd);
MR_String   read_specs_file_4(MR_AllocSiteInfoPtr alloc_id,
                MR_String specs_file_name, MR_String term_file_name,
                int spec_fd, size_t size, char *spec_buf);
").

:- pred read_specs_file_2(string::in, string::in, string::out,
    io::di, io::uo) is det.
:- pragma no_determinism_warning(read_specs_file_2/5).

:- pragma foreign_proc("C",
    read_specs_file_2(SpecsFileName::in, TermFileName::in, Problem::out,
        _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure, tabled_for_io, thread_safe],
"
    // We need to save/restore MR_hp so that we can allocate the return
    // value on Mercury's heap if necessary.
    MR_save_transient_hp();
    Problem = read_specs_file_2(MR_ALLOC_ID, SpecsFileName, TermFileName);
    MR_restore_transient_hp();
").

read_specs_file_2(_, _, _, _, _) :-
    unexpected($file, $pred, "non-C backend").

:- pragma foreign_code("C", "

MR_String
read_specs_file_2(MR_AllocSiteInfoPtr alloc_id, MR_String specs_file_name,
    MR_String term_file_name)
{
    int         spec_fd;
    MR_String   problem;
    char        errbuf[MR_STRERROR_BUF_SIZE];

    // There are race conditions between opening the file, stat'ing the file
    // and reading the contents of the file, but the Unix API doesn't really
    // allow these race conditions to be resolved.

    spec_fd = open(specs_file_name, O_RDONLY);
    if (spec_fd < 0) {
        problem = MR_make_string(alloc_id, ""could not open %s: %s"",
            specs_file_name, MR_strerror(errno, errbuf, sizeof(errbuf)));
    } else {
        problem = read_specs_file_3(alloc_id, specs_file_name,
            term_file_name, spec_fd);
        (void) close(spec_fd);
    }
    return problem;
}

MR_String
read_specs_file_3(MR_AllocSiteInfoPtr alloc_id, MR_String specs_file_name,
    MR_String term_file_name, int spec_fd)
{
    struct stat stat_buf;
    MR_String   problem;

    if (fstat(spec_fd, &stat_buf) != 0) {
        problem = MR_make_string(alloc_id, ""could not stat %s"",
            specs_file_name);
    } else {
        char        *spec_buf;

        spec_buf = malloc(stat_buf.st_size + 1);
        if (spec_buf == NULL) {
            problem = MR_make_string(alloc_id,
                ""could not allocate memory for a copy of %s"",
                specs_file_name);
        } else {
            problem = read_specs_file_4(alloc_id, specs_file_name,
                term_file_name, spec_fd, stat_buf.st_size, spec_buf);
            free(spec_buf);
        }
    }
    return problem;
}

MR_String
read_specs_file_4(MR_AllocSiteInfoPtr alloc_id, MR_String specs_file_name,
    MR_String term_file_name, int spec_fd, size_t size, char *spec_buf)
{
    size_t      num_bytes_read;
    MR_String   problem;

    // XXX We don't handle successful but partial reads.
    do {
        num_bytes_read = read(spec_fd, spec_buf, size);
    } while (num_bytes_read == -1 && MR_is_eintr(errno));
    if (num_bytes_read != size) {
        problem = MR_make_string(alloc_id, ""could not read in %s"",
            specs_file_name);
    } else {
        MR_EventSet event_set;

        // NULL terminate the string we have read in.
        spec_buf[num_bytes_read] = '\\0';
        event_set = MR_read_event_set(specs_file_name, spec_buf);
        if (event_set == NULL) {
            problem = MR_make_string(alloc_id, ""could not parse %s"",
                specs_file_name);
        } else {
            FILE *term_fp;
            char errbuf[MR_STRERROR_BUF_SIZE];

            term_fp = fopen(term_file_name, ""w"");
            if (term_fp == NULL) {
                problem = MR_make_string(alloc_id, ""could not open %s: %s"",
                    term_file_name,
                    MR_strerror(errno, errbuf, sizeof(errbuf)));
            } else {
                MR_print_event_set(term_fp, event_set);
                fclose(term_fp);

                // Our caller tests Problem against the empty string, not NULL.
                problem = MR_make_string(alloc_id, """");
            }
        }
    }
    return problem;
}
").

%-----------------------------------------------------------------------------%

:- type event_set_spec
    --->    event_set_spec(
                event_set_name      :: string,
                event_set_specs     :: list(event_spec_term)
            ).

:- type event_spec_term
    --->    event_spec_term(
                event_name          :: string,
                event_num           :: int,
                event_linenumber    :: int,
                event_attrs         :: list(event_attr_term)
            ).

:- type event_attr_term
    --->    event_attr_term(
                attr_name           :: string,
                attr_linenum        :: int,
                attr_type           :: event_attr_type
            ).

:- type event_attr_synth_call_term
    --->    event_attr_synth_call_term(
                func_attr_name  :: string,
                arg_attr_names  :: list(string)
            ).

:- type event_attr_function_kind
    --->    event_attr_pure_function
    ;       event_attr_impure_function.

:- type event_attr_type
    --->    event_attr_type_ordinary(
                event_attr_type_term
            )
    ;       event_attr_type_synthesized(
                event_attr_type_term,
                event_attr_synth_call_term
            )
    ;       event_attr_type_function(
                event_attr_function_kind
            ).

:- type event_attr_type_term
    --->    event_attr_type_term(
                string,
                list(event_attr_type_term)
            ).

:- pred convert_list_to_spec_map(string::in, list(event_spec_term)::in,
    event_spec_map::in, event_spec_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

convert_list_to_spec_map(_, [], !EventSpecMap, !ErrorSpecs).
convert_list_to_spec_map(FileName, [SpecTerm | SpecTerms],
        !EventSpecMap, !ErrorSpecs) :-
    convert_term_to_spec_map(FileName, SpecTerm, !EventSpecMap, !ErrorSpecs),
    convert_list_to_spec_map(FileName, SpecTerms, !EventSpecMap, !ErrorSpecs).

:- pred convert_term_to_spec_map(string::in, event_spec_term::in,
    event_spec_map::in, event_spec_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

convert_term_to_spec_map(FileName, SpecTerm, !EventSpecMap, !ErrorSpecs) :-
    SpecTerm = event_spec_term(EventName, EventNumber, EventLineNumber,
        AttrTerms),

    % We convert the event_spec_term we have read in to the event_spec_map
    % table entry we need in three stages.
    %
    % Stage 1 is done by build_plain_type_map. This records the types of all
    % of the ordinary and synthesized attributes in AttrTypeMap0, builds up
    % KeyMap, which maps each attribute name to its digraph_key in DepRel0,
    % and builds DepRel0, which at the end of stage 1 just contains one key
    % for each attribute with no relationships between them.
    %
    % Stage 2 is done by build_dep_map. This inserts into DepRel all the
    % dependencies of synthesized attributes on the attributes they are
    % synthesized from (including the attribute that provides the function).
    % It also computes the types of the function attributes that are used
    % to synthesize one or more other attributes.
    %
    % Stage 3, implemented by convert_terms_to_attrs, is the final pass.
    % It does the data format conversion, and performs the last checks.

    build_plain_type_map(EventName, FileName, EventLineNumber, AttrTerms,
        0, map.init, _AttrNumMap, map.init, AttrNameMap,
        map.init, AttrTypeMap0, bimap.init, KeyMap,
        digraph.init, DepRel0, !ErrorSpecs),
    build_dep_map(EventName, FileName, AttrNameMap, KeyMap, AttrTerms,
        AttrTypeMap0, AttrTypeMap, DepRel0, DepRel, !ErrorSpecs),
    convert_terms_to_attrs(EventName, FileName, AttrNameMap,
        AttrTypeMap, 0, AttrTerms, [], RevAttrs, !ErrorSpecs),
    ( if digraph.tsort(DepRel, AllAttrNameOrder) then
        % There is an order for computing the synthesized attributes.
        keep_only_synth_attr_nums(AttrNameMap, AllAttrNameOrder,
            SynthAttrNumOrder)
    else
        % It would be nice to print a list of the attributes involved in the
        % (one or more) circular dependencies detected by digraph.tsort,
        % but at present digraph.m does not have any predicates that can
        % report the information we would need for that.
        Pieces = [words("Circular dependency among"),
            words("the synthesized attributes of event"),
            quote(EventName), suffix("."), nl],
        CircErrorSpec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(context(FileName, EventLineNumber),
                [always(Pieces)])]),
        !:ErrorSpecs = [CircErrorSpec | !.ErrorSpecs],
        SynthAttrNumOrder = []
    ),
    list.reverse(RevAttrs, Attrs),
    EventSpec = event_spec(EventNumber, EventName, EventLineNumber,
        Attrs, SynthAttrNumOrder),
    ( if map.search(!.EventSpecMap, EventName, OldEventSpec) then
        OldLineNumber = OldEventSpec ^ event_spec_linenum,
        Pieces1 = [words("Duplicate event specification for event"),
            quote(EventName), suffix("."), nl],
        Pieces2 = [words("The previous event specification is here."), nl],
        DuplErrorSpec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(context(FileName, EventLineNumber), [always(Pieces1)]),
            simple_msg(context(FileName, OldLineNumber), [always(Pieces2)])]),
        !:ErrorSpecs = [DuplErrorSpec | !.ErrorSpecs]
    else
        map.det_insert(EventName, EventSpec, !EventSpecMap)
    ).

:- pred keep_only_synth_attr_nums(attr_name_map::in, list(string)::in,
    list(int)::out) is det.

keep_only_synth_attr_nums(_, [], []).
keep_only_synth_attr_nums(AttrMap, [AttrName | AttrNames], SynthAttrNums) :-
    keep_only_synth_attr_nums(AttrMap, AttrNames, SynthAttrNumsTail),
    map.lookup(AttrMap, AttrName, attr_info(AttrNum, _, _, AttrType)),
    (
        ( AttrType = event_attr_type_ordinary(_)
        ; AttrType = event_attr_type_function(_)
        ),
        SynthAttrNums = SynthAttrNumsTail
    ;
        AttrType = event_attr_type_synthesized(_, _),
        SynthAttrNums = [AttrNum | SynthAttrNumsTail]
    ).

:- type attr_info
    --->    attr_info(
                attr_info_number        :: int,
                attr_info_name          :: string,
                attr_info_linenumber    :: int,
                attr_info_type          :: event_attr_type
            ).

:- func attr_info_number(attr_info) = int.

    % Given an attribute number, return information about that attribute.
:- type attr_num_map == map(int, attr_info).

    % Given an attribute name, return information about that attribute.
:- type attr_name_map == map(string, attr_info).

    % Given an attribute number, return that attribute's type.
:- type attr_type_map == map(string, mer_type).

    % The dependency relation has a node for each attribute. The links between
    % nodes represent the dependency of one attribute on another.
    %
    % The attr_key_map maps the name of each attribute to its key in
    % attr_dep_rel.
:- type attr_dep_rel == digraph(string).
:- type attr_key == digraph_key(string).
:- type attr_key_map == bimap(string, attr_key).

    % See the big comment in convert_term_to_spec_map for the documentation
    % of this predicate.
    %
:- pred build_plain_type_map(string::in, string::in, int::in,
    list(event_attr_term)::in, int::in, attr_num_map::in, attr_num_map::out,
    attr_name_map::in, attr_name_map::out,
    attr_type_map::in, attr_type_map::out,
    attr_key_map::in, attr_key_map::out, attr_dep_rel::in, attr_dep_rel::out,
    list(error_spec)::in, list(error_spec)::out) is det.

build_plain_type_map(_, _, _, [], _, !AttrNumMap, !AttrNameMap, !AttrTypeMap,
        !KeyMap, !DepRel, !ErrorSpecs).
build_plain_type_map(EventName, FileName, EventLineNumber,
        [AttrTerm | AttrTerms], AttrNum, !AttrNumMap, !AttrNameMap,
        !AttrTypeMap, !KeyMap, !DepRel, !ErrorSpecs) :-
    AttrTerm = event_attr_term(AttrName, AttrLineNumber, AttrTypeTerm),
    AttrInfo = attr_info(AttrNum, AttrName, AttrLineNumber, AttrTypeTerm),
    map.det_insert(AttrNum, AttrInfo, !AttrNumMap),
    digraph.add_vertex(AttrName, AttrKey, !DepRel),
    ( if bimap.insert(AttrName, AttrKey, !KeyMap) then
        map.det_insert(AttrName, AttrInfo, !AttrNameMap)
    else
        Pieces = [words("Event"), quote(EventName),
            words("has more than one attribute named"),
            quote(AttrName), suffix("."), nl],
        ErrorSpec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(context(FileName, EventLineNumber),
                [always(Pieces)])]),
        !:ErrorSpecs = [ErrorSpec | !.ErrorSpecs]
    ),
    (
        ( AttrTypeTerm = event_attr_type_ordinary(TypeTerm)
        ; AttrTypeTerm = event_attr_type_synthesized(TypeTerm, _SynthCall)
        ),
        Type = convert_term_to_type(TypeTerm),
        ( if map.search(!.AttrTypeMap, AttrName, _OldType) then
            % The error message has already been generated above.
            true
        else
            map.det_insert(AttrName, Type, !AttrTypeMap)
        )
    ;
        AttrTypeTerm = event_attr_type_function(_)
    ),
    build_plain_type_map(EventName, FileName, EventLineNumber, AttrTerms,
        AttrNum + 1, !AttrNumMap, !AttrNameMap, !AttrTypeMap, !KeyMap, !DepRel,
        !ErrorSpecs).

    % See the big comment in convert_term_to_spec_map for the documentation
    % of this predicate.
    %
:- pred build_dep_map(string::in, string::in,
    attr_name_map::in, attr_key_map::in, list(event_attr_term)::in,
    attr_type_map::in, attr_type_map::out, attr_dep_rel::in, attr_dep_rel::out,
    list(error_spec)::in, list(error_spec)::out) is det.

build_dep_map(_, _, _, _, [], !AttrTypeMap, !DepRel, !ErrorSpecs).
build_dep_map(EventName, FileName, AttrNameMap, KeyMap, [AttrTerm | AttrTerms],
        !AttrTypeMap, !DepRel, !ErrorSpecs) :-
    AttrTerm = event_attr_term(AttrName, AttrLineNumber, AttrTypeTerm),
    bimap.lookup(KeyMap, AttrName, AttrKey),
    (
        AttrTypeTerm = event_attr_type_synthesized(_TypeTerm, SynthCallTerm),
        SynthCallTerm = event_attr_synth_call_term(FuncAttrName, ArgAttrNames),
        record_arg_dependencies(EventName, FileName, AttrLineNumber, KeyMap,
            AttrName, AttrKey, ArgAttrNames, !DepRel, [], AttrErrorSpecs),
        (
            AttrErrorSpecs = [_ | _],
            % We still record the fact that FuncAttrName is used, to prevent
            % us from generating error messages saying that it is unused.
            map.det_insert(FuncAttrName, void_type, !AttrTypeMap),
            !:ErrorSpecs = AttrErrorSpecs ++ !.ErrorSpecs
        ;
            AttrErrorSpecs = [],
            ( if map.search(!.AttrTypeMap, AttrName, AttrType) then
                ArgTypes = list.map(map.lookup(!.AttrTypeMap), ArgAttrNames),
                ( if
                    map.search(AttrNameMap, FuncAttrName, FuncAttrInfo),
                    FuncAttrInfo ^ attr_info_type =
                        event_attr_type_function(FuncAttrPurity)
                then
                    (
                        FuncAttrPurity = event_attr_pure_function,
                        FuncPurity = purity_pure
                    ;
                        FuncAttrPurity = event_attr_impure_function,
                        FuncPurity = purity_impure
                    ),
                    construct_higher_order_func_type(FuncPurity, lambda_normal,
                        ArgTypes, AttrType, FuncAttrType),
                    ( if
                        map.search(!.AttrTypeMap, FuncAttrName,
                            OldFuncAttrType)
                    then
                        ( if FuncAttrType = OldFuncAttrType then
                            % AttrTypeMap already contains the correct info.
                            true
                        else
                            FuncAttrLineNumber =
                                FuncAttrInfo ^ attr_info_linenumber,
                            % XXX Maybe we should give the types themselves.
                            Pieces = [words("Attribute"), quote(FuncAttrName),
                                words("is assigned inconsistent types"),
                                words("by synthesized attributes."), nl],
                            ErrorSpec = error_spec(severity_error,
                                phase_term_to_parse_tree,
                                [simple_msg(
                                    context(FileName, FuncAttrLineNumber),
                                    [always(Pieces)])]),
                            !:ErrorSpecs = [ErrorSpec | !.ErrorSpecs]
                        )
                    else
                        map.det_insert(FuncAttrName, FuncAttrType,
                            !AttrTypeMap)
                    )
                else
                    Pieces = [words("Attribute"), quote(AttrName),
                        words("cannot be synthesized"),
                        words("by non-function attribute"),
                        quote(FuncAttrName), suffix("."), nl],
                    ErrorSpec = error_spec(severity_error,
                        phase_term_to_parse_tree,
                        [simple_msg(context(FileName, AttrLineNumber),
                            [always(Pieces)])]),
                    !:ErrorSpecs = [ErrorSpec | !.ErrorSpecs]
                )
            else
                % The error message was already generated in the previous pass.
                true
            )
        )
    ;
        AttrTypeTerm = event_attr_type_ordinary(_TypeTerm)
    ;
        AttrTypeTerm = event_attr_type_function(_)
    ),
    build_dep_map(EventName, FileName, AttrNameMap, KeyMap, AttrTerms,
        !AttrTypeMap, !DepRel, !ErrorSpecs).

:- pred record_arg_dependencies(string::in, string::in, int::in,
    attr_key_map::in, string::in, attr_key::in,
    list(string)::in, attr_dep_rel::in, attr_dep_rel::out,
    list(error_spec)::in, list(error_spec)::out) is det.

record_arg_dependencies(_, _, _, _, _, _, [], !DepRel, !ErrorSpecs).
record_arg_dependencies(EventName, FileName, AttrLineNumber, KeyMap,
        SynthAttrName, SynthAttrKey, [AttrName | AttrNames],
        !DepRel, !ErrorSpecs) :-
    ( if bimap.search(KeyMap, AttrName, AttrKey) then
        digraph.add_edge(AttrKey, SynthAttrKey, !DepRel)
    else
        Pieces = [words("Attribute"), quote(SynthAttrName),
            words("of event"), quote(EventName),
            words("uses nonexistent attribute"), quote(AttrName),
            words("in its synthesis."), nl],
        ErrorSpec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(context(FileName, AttrLineNumber), [always(Pieces)])]),
        !:ErrorSpecs = [ErrorSpec | !.ErrorSpecs]
    ),
    record_arg_dependencies(EventName, FileName, AttrLineNumber, KeyMap,
        SynthAttrName, SynthAttrKey, AttrNames, !DepRel, !ErrorSpecs).

    % See the big comment in convert_term_to_spec_map for the documentation
    % of this predicate.
    %
:- pred convert_terms_to_attrs(string::in, string::in, attr_name_map::in,
    attr_type_map::in, int::in, list(event_attr_term)::in,
    list(event_attribute)::in, list(event_attribute)::out,
    list(error_spec)::in, list(error_spec)::out) is det.

convert_terms_to_attrs(_, _, _, _, _, [], !RevAttrs, !ErrorSpecs).
convert_terms_to_attrs(EventName, FileName, AttrNameMap,
        AttrTypeMap, AttrNum, [AttrTerm | AttrTerms], !RevAttrs,
        !ErrorSpecs) :-
    AttrTerm = event_attr_term(AttrName, AttrLineNumber, AttrTypeTerm),
    (
        AttrTypeTerm = event_attr_type_ordinary(_),
        map.lookup(AttrTypeMap, AttrName, AttrType),
        EventAttr = event_attribute(AttrNum, AttrName, AttrType, in_mode, no),
        !:RevAttrs = [EventAttr | !.RevAttrs]
    ;
        AttrTypeTerm = event_attr_type_synthesized(_, SynthCallTerm),
        map.lookup(AttrTypeMap, AttrName, AttrType),
        SynthCallTerm = event_attr_synth_call_term(FuncAttrName, ArgAttrNames),
        ( if
            FuncAttrInfo = map.search(AttrNameMap, FuncAttrName),
            FuncAttrNum = FuncAttrInfo ^ attr_info_number,
            list.map(map.search(AttrNameMap), ArgAttrNames, ArgAttrInfos)
        then
            ArgAttrNums = list.map(attr_info_number, ArgAttrInfos),
            ArgAttrNameNums = assoc_list.from_corresponding_lists(ArgAttrNames,
                ArgAttrNums),
            compute_prev_synth_attr_order(AttrNameMap, AttrName,
                set.init, set.init, _, PrevSynthAttrOrder),
            SynthCall = event_attr_synth_call(FuncAttrName - FuncAttrNum,
                ArgAttrNameNums, PrevSynthAttrOrder),
            EventAttr = event_attribute(AttrNum, AttrName, AttrType, in_mode,
                yes(SynthCall)),
            !:RevAttrs = [EventAttr | !.RevAttrs]
        else
            % The error that caused the map search failure has already had
            % an error message generated for it.
            true
        )
    ;
        AttrTypeTerm = event_attr_type_function(_),
        ( if map.search(AttrTypeMap, AttrName, AttrType) then
            EventAttr = event_attribute(AttrNum, AttrName, AttrType, in_mode,
                no),
            !:RevAttrs = [EventAttr | !.RevAttrs]
        else
            Pieces = [words("Event"), quote(EventName),
                words("does not use the function attribute"),
                quote(AttrName), suffix("."), nl],
            ErrorSpec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(context(FileName, AttrLineNumber),
                    [always(Pieces)])]),
            !:ErrorSpecs = [ErrorSpec | !.ErrorSpecs]
        )
    ),
    convert_terms_to_attrs(EventName, FileName, AttrNameMap, AttrTypeMap,
        AttrNum + 1, AttrTerms, !RevAttrs, !ErrorSpecs).

:- func convert_term_to_type(event_attr_type_term) = mer_type.

convert_term_to_type(Term) = Type :-
    Term = event_attr_type_term(Name, Args),
    ( if
        Args = [],
        builtin_type_to_string(BuiltinType, Name)
    then
        Type = builtin_type(BuiltinType)
    else
        SymName = string_to_sym_name(Name),
        ArgTypes = list.map(convert_term_to_type, Args),
        Type = defined_type(SymName, ArgTypes, kind_star)
    ).

%-----------------------------------------------------------------------------%

:- pred compute_prev_synth_attr_order(attr_name_map::in, string::in,
    set(string)::in, set(string)::in, set(string)::out, list(int)::out) is det.

compute_prev_synth_attr_order(AttrNameMap, AttrName, Ancestors,
        !AlreadyComputed, PrevSynthOrder) :-
    ( if set.member(AttrName, Ancestors) then
        % There is a circularity among the dependencies, which means that
        % PrevSynthOrder won't actually be used.
        PrevSynthOrder = []
    else
        ( if map.search(AttrNameMap, AttrName, AttrInfo) then
            AttrTerm = AttrInfo ^ attr_info_type,
            (
                ( AttrTerm = event_attr_type_ordinary(_)
                ; AttrTerm = event_attr_type_function(_)
                ),
                PrevSynthOrder = []
            ;
                AttrTerm = event_attr_type_synthesized(_, SynthCall),
                SynthCall = event_attr_synth_call_term(FuncAttrName,
                    ArgAttrNames),
                set.insert(AttrName, Ancestors, SubAncestors),
                compute_prev_synth_attr_order_for_args(AttrNameMap,
                    [FuncAttrName | ArgAttrNames], SubAncestors,
                    !AlreadyComputed, SubPrevSynthOrder),
                set.insert(AttrName, !AlreadyComputed),
                % This append at the end makes our algorithm O(n^2),
                % but since n will always be small, this doesn't matter.
                AttrNum = AttrInfo ^ attr_info_number,
                PrevSynthOrder = SubPrevSynthOrder ++ [AttrNum]
            )
        else
            % An error has occurred somewhere, which means that
            % PrevSynthOrder won't actually be used.
            PrevSynthOrder = []
        )
    ).

:- pred compute_prev_synth_attr_order_for_args(attr_name_map::in,
    list(string)::in, set(string)::in, set(string)::in, set(string)::out,
    list(int)::out) is det.

compute_prev_synth_attr_order_for_args(_AttrNameMap, [],
        _Ancestors, !AlreadyComputed, []).
compute_prev_synth_attr_order_for_args(AttrNameMap, [ArgName | ArgNames],
        Ancestors, !AlreadyComputed, PrevSynthOrder) :-
    compute_prev_synth_attr_order(AttrNameMap, ArgName,
        Ancestors, !AlreadyComputed, PrevSynthOrderArg),
    compute_prev_synth_attr_order_for_args(AttrNameMap, ArgNames,
        Ancestors, !AlreadyComputed, PrevSynthOrderArgs),
    PrevSynthOrder = PrevSynthOrderArg ++ PrevSynthOrderArgs.

%-----------------------------------------------------------------------------%

derive_event_set_data(EventSet) = EventSetData :-
    EventSet = event_set(EventSetName, EventSpecMap),
    map.values(EventSpecMap, EventSpecList),
    list.sort(compare_event_specs_by_num, EventSpecList, SortedEventSpecList),
    EventDescStrings = list.map(describe_event_spec, SortedEventSpecList),
    string.append_list(EventDescStrings, EventDescs),
    Desc = "event set " ++ EventSetName ++ "\n" ++ EventDescs,
    list.foldl(update_max_num_attr, EventSpecList, -1, MaxNumAttr),
    EventSetData = event_set_data(EventSetName, Desc, SortedEventSpecList,
        MaxNumAttr).

:- pred update_max_num_attr(event_spec::in, int::in, int::out) is det.

update_max_num_attr(Spec, !MaxNumAttr) :-
    AllAttrs = Spec ^ event_spec_attrs,
    list.length(AllAttrs, NumAttr),
    !:MaxNumAttr = int.max(!.MaxNumAttr, NumAttr).

:- pred compare_event_specs_by_num(event_spec::in, event_spec::in,
    comparison_result::out) is det.

compare_event_specs_by_num(SpecA, SpecB, Result) :-
    compare(Result, SpecA ^ event_spec_num, SpecB ^ event_spec_num).

:- func describe_event_spec(event_spec) = string.

describe_event_spec(Spec) = Desc :-
    Spec = event_spec(_EventNumber, EventName, _EventLineNumber,
        Attrs, _SynthAttrNumOrder),
    AttrDescs = string.join_list(",\n", list.map(describe_event_attr, Attrs)),
    Desc = "event " ++ EventName ++ "(" ++ AttrDescs ++ ")\n".

:- func describe_event_attr(event_attribute) = string.

describe_event_attr(Attr) = Desc :-
    Attr = event_attribute(_Num, Name, Type, _Mode, MaybeSynthCall),
    TypeDesc = describe_attr_type(Type),
    (
        MaybeSynthCall = no,
        SynthCallDesc = ""
    ;
        MaybeSynthCall = yes(SynthCall),
        SynthCall = event_attr_synth_call(FuncAttrNameNum, ArgAttrNameNums,
            _Order),
        ArgAttrDesc = string.join_list(", ", assoc_list.keys(ArgAttrNameNums)),
        SynthCallDesc = " synthesized by " ++
            fst(FuncAttrNameNum) ++ "(" ++ ArgAttrDesc ++ ")"
    ),
    Desc = Name ++ ": " ++ TypeDesc ++ SynthCallDesc.

:- func describe_attr_type(mer_type) = string.

describe_attr_type(Type) = Desc :-
    (
        Type = defined_type(SymName, ArgTypes, Kind),
        expect(unify(Kind, kind_star), $module, $pred, "not kind_star"),
        (
            ArgTypes = [],
            ArgTypeDescs = ""
        ;
            ArgTypes = [_ | _],
            ArgTypeDescs = "(" ++
                string.join_list(", ", list.map(describe_attr_type, ArgTypes))
                ++ ")"
        ),
        Desc = sym_name_to_string(SymName) ++ ArgTypeDescs
    ;
        Type = builtin_type(BuiltinType),
        builtin_type_to_string(BuiltinType, Desc)
    ;
        Type = higher_order_type(_, _, _, _, _),
        Desc = "function"
    ;
        ( Type = type_variable(_, _)
        ; Type = tuple_type(_, _)
        ; Type = apply_n_type(_, _, _)
        ; Type = kinded_type(_, _)
        ),
        unexpected($module, $pred, "type not constructed by prog_event")
    ).

%-----------------------------------------------------------------------------%

event_number(EventSpecMap, EventName, EventNumber) :-
    map.search(EventSpecMap, EventName, EventSpec),
    EventNumber = EventSpec ^ event_spec_num.

event_attributes(EventSpecMap, EventName, Attributes) :-
    map.search(EventSpecMap, EventName, EventSpec),
    Attributes = EventSpec ^ event_spec_attrs.

event_arg_types(EventSpecMap, EventName, ArgTypes) :-
    event_attributes(EventSpecMap, EventName, Attributes),
    list.filter_map(project_event_arg_type, Attributes, ArgTypes).

event_arg_modes(EventSpecMap, EventName, ArgModes) :-
    event_attributes(EventSpecMap, EventName, Attributes),
    list.filter_map(project_event_arg_mode, Attributes, ArgModes).

:- pred project_event_arg_type(event_attribute::in, mer_type::out) is semidet.

project_event_arg_type(Attribute, Attribute ^ attr_type) :-
    Attribute ^ attr_maybe_synth_call = no.

:- pred project_event_arg_mode(event_attribute::in, mer_mode::out) is semidet.

project_event_arg_mode(Attribute, Attribute ^ attr_mode) :-
    Attribute ^ attr_maybe_synth_call = no.

%-----------------------------------------------------------------------------%
:- end_module parse_tree.prog_event.
%-----------------------------------------------------------------------------%
