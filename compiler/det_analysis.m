%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: det_analysis.m - the determinism analysis pass.
% Main authors: conway, fjh, zs.
%
% This pass has three components:
%
% - Segregate the procedures into those that have determinism declarations,
%   and those that don't.
%
% - A step of performing a local inference pass on each procedure
%   without a determinism declaration is iterated until a fixpoint is reached.
%
% - A checking step is performed on all the procedures that have determinism
%   declarations to ensure that they are at least as deterministic as their
%   declaration. This uses a form of the local inference pass.
%
% If we are to avoid global inference for predicates with declarations, then
% it must be an error, not just a warning, if the determinism checking step
% detects that the determinism annotation was wrong.  If we were to issue just
% a warning, then we would have to override the determinism annotation, and
% that would force us to re-check the inferred determinism for all calling
% predicates.
%
% Alternately, we could leave it as a warning, but then we would have to
% _make_ the predicate deterministic (or semideterministic) by inserting
% run-time checking code which calls error/1 if the predicate really isn't
% deterministic (semideterministic).
%
% Determinism has three components:
%
%   whether a goal can fail
%   whether a goal has more than one possible solution
%   whether a goal occurs in a context where only the first solution
%       is required
%
% The first two components are synthesized attributes: they are inferred
% bottom-up. The last component is an inherited attribute: it is propagated
% top-down.
%
%-----------------------------------------------------------------------------%

:- module check_hlds.det_analysis.
:- interface.

:- import_module check_hlds.det_report.
:- import_module check_hlds.det_util.
:- import_module hlds.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.instmap.
:- import_module parse_tree.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.

:- import_module list.
:- import_module maybe.

%-----------------------------------------------------------------------------%

    % Perform determinism inference for local predicates with no determinism
    % declarations, and determinism checking for all other predicates.
    %
:- pred determinism_pass(module_info::in, module_info::out,
    list(error_spec)::out) is det.

    % Check the determinism of a single procedure (only works if the
    % determinism of the procedures it calls has already been inferred).
    %
:- pred determinism_check_proc(proc_id::in, pred_id::in,
    module_info::in, module_info::out, list(error_spec)::out) is det.

    % Infer the determinism of a procedure.
    %
:- pred det_infer_proc(pred_id::in, proc_id::in,
    module_info::in, module_info::out, determinism::out, determinism::out,
    list(error_spec)::in, list(error_spec)::out) is det.

:- type pess_info
    --->    pess_info(prog_vars, prog_context).
            % short for promise_equivalent_solution_sets_info

    % Infers the determinism of `Goal0' and returns this in `Detism'.
    % It annotates the goal and all its subgoals with their determinism
    % and returns the annotated goal in `Goal'.
    %
:- pred det_infer_goal(hlds_goal::in, hlds_goal::out, instmap::in,
    soln_context::in, list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

    % Work out how many solutions are needed for a given determinism.
    %
:- pred det_get_soln_context(determinism::in, soln_context::out) is det.

:- type soln_context
    --->    all_solns
    ;       first_soln.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.format_call.
:- import_module check_hlds.modecheck_call.
:- import_module check_hlds.type_util.
:- import_module hlds.code_model.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_error_util.
:- import_module hlds.hlds_out.
:- import_module hlds.hlds_out.hlds_out_util.
:- import_module hlds.pred_table.
:- import_module libs.
:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.set_of_var.

:- import_module assoc_list.
:- import_module bool.
:- import_module io.
:- import_module map.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.

%-----------------------------------------------------------------------------%

determinism_pass(!ModuleInfo, Specs) :-
    module_info_get_valid_predids(PredIds, !ModuleInfo),
    determinism_declarations(!.ModuleInfo, PredIds,
        DeclaredProcs, UndeclaredProcs, NoInferProcs),
    list.foldl(set_non_inferred_proc_determinism, NoInferProcs, !ModuleInfo),
    module_info_get_globals(!.ModuleInfo, Globals),
    globals.lookup_bool_option(Globals, verbose, Verbose),
    globals.lookup_bool_option(Globals, debug_det, Debug),
    (
        UndeclaredProcs = [],
        InferenceSpecs = []
    ;
        UndeclaredProcs = [_ | _],
        trace [io(!IO)] (
            maybe_write_string(Verbose, "% Doing determinism inference...\n",
                !IO)
        ),
        global_inference_pass(!ModuleInfo, UndeclaredProcs, Debug,
            InferenceSpecs),
        trace [io(!IO)] (
            maybe_write_string(Verbose, "% done.\n", !IO)
        )
    ),
    trace [io(!IO)] (
        maybe_write_string(Verbose, "% Doing determinism checking...\n", !IO)
    ),
    global_final_pass(!ModuleInfo, UndeclaredProcs, DeclaredProcs, Debug,
        FinalSpecs),
    Specs = InferenceSpecs ++ FinalSpecs,
    trace [io(!IO)] (
        maybe_write_string(Verbose, "% done.\n", !IO)
    ).

determinism_check_proc(ProcId, PredId, !ModuleInfo, Specs) :-
    module_info_get_globals(!.ModuleInfo, Globals),
    globals.lookup_bool_option(Globals, debug_det, Debug),
    global_final_pass(!ModuleInfo, [], [proc(PredId, ProcId)], Debug, Specs).

%-----------------------------------------------------------------------------%

:- pred global_inference_pass(module_info::in, module_info::out,
    pred_proc_list::in, bool::in, list(error_spec)::out) is det.

    % Iterate until a fixpoint is reached. This can be expensive if a module
    % has many predicates with undeclared determinisms. If this ever becomes
    % a problem, we should switch to doing iterations only on strongly
    % connected components of the dependency graph.
    %
global_inference_pass(!ModuleInfo, ProcList, Debug, Specs) :-
    global_inference_single_pass(ProcList, Debug, !ModuleInfo, [], Specs1,
        unchanged, Changed),
    trace [io(!IO)] (
        maybe_write_string(Debug, "% Inference pass complete\n", !IO)
    ),
    (
        Changed = changed,
        % We have not yet arrived at a fixpoint. Therefore the messages in
        % Specs1 are based on possibly non-final determinisms of some
        % procedures, which means that it is NOT safe to return them
        % to be printed. Instead, we will compute them again from more
        % up-to-date determinism information.
        global_inference_pass(!ModuleInfo, ProcList, Debug, Specs)
    ;
        Changed = unchanged,
        % We have arrived at a fixpoint. Therefore all the messages we have
        % are based on the final determinisms of all procedures, which means
        % it is safe to return them to be printed.
        Specs = Specs1
    ).

:- pred global_inference_single_pass(pred_proc_list::in, bool::in,
    module_info::in, module_info::out,
    list(error_spec)::in, list(error_spec)::out,
    maybe_changed::in, maybe_changed::out) is det.

global_inference_single_pass([], _, !ModuleInfo, !Specs, !Changed).
global_inference_single_pass([proc(PredId, ProcId) | PredProcs], Debug,
        !ModuleInfo, !Specs, !Changed) :-
    det_infer_proc(PredId, ProcId, !ModuleInfo, OldDetism, NewDetism, !Specs),
    ( NewDetism = OldDetism ->
        ChangeStr = "old"
    ;
        ChangeStr = "new",
        !:Changed = changed
    ),
    (
        Debug = yes,
        trace [io(!IO)] (
            io.write_string("% Inferred " ++ ChangeStr ++ " detism ", !IO),
            mercury_output_det(NewDetism, !IO),
            io.write_string(" for ", !IO),
            write_pred_proc_id_pair(!.ModuleInfo, PredId, ProcId, !IO),
            io.write_string("\n", !IO)
        )
    ;
        Debug = no
    ),
    global_inference_single_pass(PredProcs, Debug, !ModuleInfo, !Specs,
        !Changed).

:- pred global_final_pass(module_info::in, module_info::out,
    pred_proc_list::in, pred_proc_list::in, bool::in,
    list(error_spec)::out) is det.

global_final_pass(!ModuleInfo, UndeclaredProcs, DeclaredProcs, Debug,
        !:Specs) :-
    % We have already iterated global_inference_single_pass to a fixpoint
    % on the undeclared procs.
    global_inference_single_pass(DeclaredProcs, Debug, !ModuleInfo,
        [], !:Specs, unchanged, _),
    global_checking_pass(UndeclaredProcs ++ DeclaredProcs, !ModuleInfo,
        !Specs).

%-----------------------------------------------------------------------------%

det_infer_proc(PredId, ProcId, !ModuleInfo, OldDetism, NewDetism, !Specs) :-
    % Get the proc_info structure for this procedure.
    module_info_get_preds(!.ModuleInfo, PredTable0),
    map.lookup(PredTable0, PredId, PredInfo0),
    pred_info_get_procedures(PredInfo0, ProcTable0),
    map.lookup(ProcTable0, ProcId, ProcInfo0),

    % Remember the old inferred determinism of this procedure.
    proc_info_get_inferred_determinism(ProcInfo0, OldDetism),

    % Work out whether or not the procedure occurs in a single-solution
    % context. Currently we only assume so if the predicate has an explicit
    % determinism declaration that says so.
    det_get_soln_context(OldDetism, OldInferredSolnContext),
    proc_info_get_declared_determinism(ProcInfo0, MaybeDeclaredDetism),
    (
        MaybeDeclaredDetism = yes(DeclaredDetism),
        det_get_soln_context(DeclaredDetism, DeclaredSolnContext)
    ;
        MaybeDeclaredDetism = no,
        DeclaredSolnContext = all_solns
    ),
    (
        ( DeclaredSolnContext = first_soln
        ; OldInferredSolnContext = first_soln
        )
    ->
        SolnContext = first_soln
    ;
        SolnContext = all_solns
    ),

    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring procedure ", !IO),
        io.write(PredId, !IO),
        io.write_string("/", !IO),
        io.write(ProcId, !IO),
        io.nl(!IO)
    ),

    % Infer the determinism of the goal.
    proc_info_get_goal(ProcInfo0, Goal0),
    proc_info_get_initial_instmap(ProcInfo0, !.ModuleInfo, InstMap0),
    proc_info_get_vartypes(ProcInfo0, VarTypes),
    det_info_init(!.ModuleInfo, VarTypes, PredId, ProcId,
        pess_extra_vars_report, !.Specs, DetInfo0),
    det_infer_goal(Goal0, Goal, InstMap0, SolnContext, [], no,
        InferDetism, _,  DetInfo0, DetInfo),
    det_info_get_module_info(DetInfo, !:ModuleInfo),
    det_info_get_error_specs(DetInfo, !:Specs),
    det_info_get_has_format_call(DetInfo, HasFormatCalls),
    det_info_get_has_req_scope(DetInfo, HasRequireScope),

    % Take the worst of the old and inferred detisms. This is needed to prevent
    % loops on p :- not(p), at least if the initial assumed detism is det.
    % This may also be needed to ensure that we don't change the interface
    % determinism of procedures, if we are re-running determinism analysis.

    determinism_components(OldDetism, OldCanFail, OldMaxSoln),
    determinism_components(InferDetism, InferCanFail, InferMaxSoln),
    det_switch_canfail(OldCanFail, InferCanFail, CanFail),
    det_switch_maxsoln(OldMaxSoln, InferMaxSoln, MaxSoln),
    determinism_components(TentativeDetism, CanFail, MaxSoln),

    % Now see if the evaluation model can change the detism.
    proc_info_get_eval_method(ProcInfo0, EvalMethod),
    NewDetism = eval_method_change_determinism(EvalMethod, TentativeDetism),
    (
        proc_info_has_io_state_pair(!.ModuleInfo, ProcInfo0, _InArg, _OutArg),
        (
            MaybeDeclaredDetism = yes(ToBeCheckedDetism)
        ;
            MaybeDeclaredDetism = no,
            ToBeCheckedDetism = NewDetism
        ),
        determinism_to_code_model(ToBeCheckedDetism, ToBeCheckedCodeModel),
        ToBeCheckedCodeModel \= model_det
    ->
        proc_info_get_context(ProcInfo0, ProcContext),
        IOStateProcPieces = describe_one_proc_name_mode(!.ModuleInfo,
            should_not_module_qualify, proc(PredId, ProcId)),
        IOStatePieces = [words("In")] ++ IOStateProcPieces ++ [suffix(":"), nl,
            words("error: invalid determinism for a predicate"),
            words("with I/O state arguments.")],
        IOStateVerbosePieces = [words("Valid determinisms are "),
            words("det, cc_multi and erroneous.")],
        IOStateSpec = error_spec(severity_error, phase_detism_check,
            [simple_msg(ProcContext,
                [always(IOStatePieces), verbose_only(IOStateVerbosePieces)])]),
        !:Specs = [IOStateSpec | !.Specs]
    ;
        true
    ),

    % Check to make sure that if this procedure is exported via a pragma
    % foreign_export declaration then the determinism is not multi or nondet -
    % pragma exported procs that have been declared to have these determinisms
    % should have been picked up in make_hlds, so this is just to catch those
    % whose determinisms need to be inferred.
    module_info_get_pragma_exported_procs(!.ModuleInfo, ExportedProcs),
    (
        list.member(pragma_exported_proc(_, PredId, ProcId, _, _),
            ExportedProcs),
        ( NewDetism = detism_multi
        ; NewDetism = detism_non
        )
    ->
        (
            get_exported_proc_context(ExportedProcs, PredId, ProcId,
                PragmaContext)
        ->
            ExportPieces = [words("Error: "),
                fixed("`:- pragma foreign_export' declaration"),
                words("for a procedure that has a determinism of"),
                fixed(determinism_to_string(NewDetism) ++ ".")],
            ExportSpec = error_spec(severity_error, phase_detism_check,
                [simple_msg(PragmaContext, [always(ExportPieces)])]),
            !:Specs = [ExportSpec | !.Specs]
        ;
            unexpected($module, $pred,
                "Cannot find proc in table of pragma foreign_exported procs")
        )
    ;
        true
    ),

    % Save the newly inferred information.
    proc_info_set_goal(Goal, ProcInfo0, ProcInfo1),
    proc_info_set_inferred_determinism(NewDetism, ProcInfo1, ProcInfo),

    % Put back the new proc_info structure.
    map.det_update(ProcId, ProcInfo, ProcTable0, ProcTable),
    pred_info_set_procedures(ProcTable, PredInfo0, PredInfo1),

    pred_info_get_markers(PredInfo1, Markers1),
    (
        HasFormatCalls = does_not_contain_format_call,
        Markers2 = Markers1
    ;
        HasFormatCalls = contains_format_call,
        add_marker(marker_has_format_call, Markers1, Markers2)
    ),
    (
        HasRequireScope = does_not_contain_require_scope,
        Markers = Markers2
    ;
        HasRequireScope = contains_require_scope,
        add_marker(marker_has_require_scope, Markers2, Markers)
    ),
    pred_info_set_markers(Markers, PredInfo1, PredInfo),

    map.det_update(PredId, PredInfo, PredTable0, PredTable),
    module_info_set_preds(PredTable, !ModuleInfo).

:- pred get_exported_proc_context(list(pragma_exported_proc)::in,
    pred_id::in, proc_id::in, prog_context::out) is semidet.

get_exported_proc_context([Proc | Procs], PredId, ProcId, Context) :-
    ( Proc = pragma_exported_proc(_, PredId, ProcId, _, Context0) ->
        Context = Context0
    ;
        get_exported_proc_context(Procs, PredId, ProcId, Context)
    ).

%-----------------------------------------------------------------------------%

det_infer_goal(Goal0, Goal, InstMap0, !.SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, Detism, GoalFailingContexts, !DetInfo) :-
    Goal0 = hlds_goal(_, GoalInfo0),
    NonLocalVars = goal_info_get_nonlocals(GoalInfo0),
    InstmapDelta = goal_info_get_instmap_delta(GoalInfo0),

    % If a pure or semipure goal has no output variables, then the goal
    % is in a single-solution context.
    (
        det_no_output_vars(NonLocalVars, InstMap0, InstmapDelta, !.DetInfo),
        Purity = goal_info_get_purity(GoalInfo0),
        (
            Purity = purity_impure
        =>
            goal_info_has_feature(GoalInfo0,
                feature_not_impure_for_determinism)
        )
    ->
        AddPruning = yes,
        !:SolnContext = first_soln
    ;
        AddPruning = no
    ),

    det_infer_goal_1(Goal0, Goal, InstMap0, !.SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, AddPruning, Detism, GoalFailingContexts,
        !DetInfo).

:- pred det_infer_goal_1(hlds_goal::in, hlds_goal::out, instmap::in,
    soln_context::in, list(failing_context)::in, maybe(pess_info)::in,
    bool::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_goal_1(Goal0, Goal, InstMap0, !.SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, AddPruning, Detism, GoalFailingContexts,
        !DetInfo) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    InstmapDelta = goal_info_get_instmap_delta(GoalInfo0),

    (
        GoalExpr0 = scope(ScopeReason, _),
        (
            % Some other part of the compiler has determined that we need
            % to keep the cut represented by this quantification. This can
            % happen e.g. when deep profiling adds impure code to the goal
            % inside the scope; it doesn't want to change the behavior of
            % the scope, even though the addition of impurity would make
            % the if-then-else treat it differently.

            ScopeReason = commit(force_pruning)
        ;
            % If all solutions are promised to be equivalent according to the
            % relevant equality theory, we want to prune away all but one
            % of those solutions.

            ScopeReason = promise_solutions(_, PromiseEqvSolnsKind),
            promise_eqv_solutions_kind_prunes(PromiseEqvSolnsKind) = yes
        )
    ->
        Prune = yes
    ;
        Prune = AddPruning
    ),

    det_infer_goal_2(GoalExpr0, GoalExpr1, GoalInfo0, InstMap0, !.SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        InternalDetism0, GoalFailingContexts, !DetInfo),

    determinism_components(InternalDetism0, InternalCanFail, InternalSolns0),
    (
        % If mode analysis notices that a goal cannot succeed,
        % then determinism analysis should notice this too.

        instmap_delta_is_unreachable(InstmapDelta)
    ->
        InternalSolns = at_most_zero
    ;
        InternalSolns = InternalSolns0
    ),
    (
        ( InternalSolns = at_most_many
        ; InternalSolns = at_most_many_cc
        ),
        Prune = yes
    ->
        Solns = at_most_one
    ;
        % If a goal with multiple solutions occurs in a single-solution
        % context, then we will need to do pruning.

        InternalSolns = at_most_many,
        !.SolnContext = first_soln
    ->
        Solns = at_most_many_cc
    ;
        Solns = InternalSolns
    ),
    determinism_components(Detism, InternalCanFail, Solns),
    goal_info_set_determinism(Detism, GoalInfo0, GoalInfo),

    % The code generators assume that conjunctions containing multi or nondet
    % goals and if-then-elses containing multi or nondet conditions can only
    % occur inside other multi or nondet goals. simplify.m modifies the code
    % to make these invariants hold. Determinism analysis can be rerun after
    % simplification, and without this code here the invariants would not hold
    % after determinism analysis (the number of solutions of the inner goal
    % would be changed back from at_most_many to at_most_one or at_most_zero).
    (
        % If-then-elses that are det or semidet may nevertheless contain nondet
        % or multidet conditions. If this happens, the if-then-else must be put
        % inside a `scope' to appease the code generator. (Both the MLDS and
        % LLDS back-ends rely on this.)

        GoalExpr1 = if_then_else(_, hlds_goal(_, CondInfo), _, _),
        CondDetism = goal_info_get_determinism(CondInfo),
        determinism_components(CondDetism, _, at_most_many),
        Solns \= at_most_many
    ->
        FinalInternalSolns = at_most_many
    ;
        % Conjunctions that cannot produce solutions may nevertheless contain
        % nondet and multidet goals. If this happens, the conjunction is put
        % inside a scope goal to appease the code generator.

        GoalExpr1 = conj(plain_conj, ConjGoals),
        Solns = at_most_zero,
        some [ConjGoalInfo] (
            list.member(hlds_goal(_, ConjGoalInfo), ConjGoals),
            ConjGoalDetism = goal_info_get_determinism(ConjGoalInfo),
            determinism_components(ConjGoalDetism, _, at_most_many)
        )
    ->
        FinalInternalSolns = at_most_many
    ;
        FinalInternalSolns = InternalSolns
    ),
    determinism_components(FinalInternalDetism, InternalCanFail,
        FinalInternalSolns),

    % See how we should introduce the commit operator, if one is needed.
    (
        % Do we need a commit?
        Detism \= FinalInternalDetism,

        % Disjunctions, we want to use a semidet or cc_nondet disjunction
        % which avoids creating a choice point at all, rather than wrapping
        % a some [] around a nondet disj, which would create a choice point
        % and then prune it.
        GoalExpr1 \= disj(_),

        % Do we already have a commit?
        GoalExpr1 \= scope(_, _)
    ->
        % A commit is needed - we must introduce an explicit `commit' so that
        % the code generator knows to insert the appropriate code for pruning.
        goal_info_set_determinism(FinalInternalDetism, GoalInfo0, InnerInfo),
        GoalExpr = scope(commit(dont_force_pruning),
            hlds_goal(GoalExpr1, InnerInfo))
    ;
        % Either no commit is needed, or a `scope' is already present.
        GoalExpr = GoalExpr1
    ),
    Goal = hlds_goal(GoalExpr, GoalInfo).

:- func promise_eqv_solutions_kind_prunes(promise_solutions_kind) = bool.

promise_eqv_solutions_kind_prunes(equivalent_solutions) = yes.
promise_eqv_solutions_kind_prunes(equivalent_solution_sets) = no.
promise_eqv_solutions_kind_prunes(equivalent_solution_sets_arbitrary) = yes.

%-----------------------------------------------------------------------------%

:- pred det_infer_goal_2(hlds_goal_expr::in, hlds_goal_expr::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_goal_2(GoalExpr0, GoalExpr, GoalInfo, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets, Detism,
        GoalFailingContexts, !DetInfo) :-
    (
        GoalExpr0 = conj(ConjType, Goals0),
        (
            ConjType = plain_conj,
            % The determinism of a conjunction is the worst case of the
            % determinism of the goals of that conjuction.
            det_infer_conj(Goals0, Goals, InstMap0, SolnContext,
                RightFailingContexts, MaybePromiseEqvSolutionSets,
                Detism, [], GoalFailingContexts, !DetInfo)
        ;
            ConjType = parallel_conj,
            det_infer_par_conj(Goals0, Goals, GoalInfo, InstMap0, SolnContext,
                RightFailingContexts, MaybePromiseEqvSolutionSets,
                Detism, GoalFailingContexts, !DetInfo)
        ),
        GoalExpr = conj(ConjType, Goals)
    ;
        GoalExpr0 = disj(Goals0),
        det_infer_disj(Goals0, Goals, GoalInfo, InstMap0, SolnContext,
            RightFailingContexts, MaybePromiseEqvSolutionSets,
            Detism, GoalFailingContexts, !DetInfo),
        GoalExpr = disj(Goals)
    ;
        GoalExpr0 = switch(Var, SwitchCanFail, Cases0),
        trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
            io.write_string("inferring switch on ", !IO),
            io.write(Var, !IO),
            io.nl(!IO)
        ),
        det_infer_switch(Var, SwitchCanFail, Cases0, Cases, GoalInfo, InstMap0,
            SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
            Detism, GoalFailingContexts, !DetInfo),
        trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
            io.write_string("done inferring switch on ", !IO),
            io.write(Var, !IO),
            io.nl(!IO)
        ),
        GoalExpr = switch(Var, SwitchCanFail, Cases)
    ;
        GoalExpr0 = plain_call(PredId, ProcId0, Args, Builtin, UnifyContext,
            Name),
        det_infer_call(PredId, ProcId0, ProcId, Args, GoalInfo, SolnContext,
            RightFailingContexts, Detism, GoalFailingContexts, !DetInfo),
        GoalExpr = plain_call(PredId, ProcId, Args, Builtin, UnifyContext,
            Name)
    ;
        GoalExpr0 = generic_call(GenericCall, _ArgVars, _Modes, CallDetism),
        det_infer_generic_call(GenericCall, CallDetism, GoalInfo, SolnContext,
            RightFailingContexts, Detism, GoalFailingContexts, !DetInfo),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = unify(LHS, RHS0, Mode, Unify, UnifyContext),
        det_infer_unify(LHS, RHS0, Unify, UnifyContext, RHS, GoalInfo,
            InstMap0, SolnContext, RightFailingContexts, Detism,
            GoalFailingContexts, !DetInfo),
        GoalExpr = unify(LHS, RHS, Mode, Unify, UnifyContext)
    ;
        GoalExpr0 = if_then_else(Vars, Cond0, Then0, Else0),
        det_infer_if_then_else(Cond0, Cond, Then0, Then, Else0, Else,
            InstMap0, SolnContext, RightFailingContexts,
            MaybePromiseEqvSolutionSets, Detism, GoalFailingContexts,
            !DetInfo),
        GoalExpr = if_then_else(Vars, Cond, Then, Else)
    ;
        GoalExpr0 = negation(Goal0),
        det_infer_not(Goal0, Goal, GoalInfo, InstMap0,
            MaybePromiseEqvSolutionSets, Detism, GoalFailingContexts,
            !DetInfo),
        GoalExpr = negation(Goal)
    ;
        GoalExpr0 = scope(Reason, Goal0),
        det_infer_scope(Reason, Goal0, Goal, GoalInfo, InstMap0, SolnContext,
            RightFailingContexts, MaybePromiseEqvSolutionSets, Detism,
            GoalFailingContexts, !DetInfo),
        GoalExpr = scope(Reason, Goal)
    ;
        GoalExpr0 = call_foreign_proc(Attributes, PredId, ProcId,
            _Args, _ExtraArgs, _MaybeTraceRuntimeCond, PragmaCode),
        det_infer_foreign_proc(Attributes, PredId, ProcId, PragmaCode,
            GoalInfo, SolnContext, RightFailingContexts, Detism,
            GoalFailingContexts, !DetInfo),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = shorthand(ShortHand0),
        (
            ShortHand0 = atomic_goal(GoalType, Inner, Outer, Vars, MainGoal0,
                OrElseGoals0, OrElseInners),
            det_infer_atomic(MainGoal0, MainGoal, OrElseGoals0, OrElseGoals,
                InstMap0, SolnContext, RightFailingContexts,
                MaybePromiseEqvSolutionSets, Detism, !DetInfo),
            GoalFailingContexts = [],
            ShortHand = atomic_goal(GoalType, Inner, Outer, Vars, MainGoal,
                OrElseGoals, OrElseInners)
        ;
            ShortHand0 = try_goal(MaybeIO, ResultVar, TryGoal0),
            % Don't allow det_infer_goal_1 to insert a commit scope around the
            % code that's standing in place for the code we'll actually create
            % for a try goal.
            det_infer_goal_1(TryGoal0, TryGoal, InstMap0, SolnContext,
                RightFailingContexts, MaybePromiseEqvSolutionSets, no, Detism,
                GoalFailingContexts, !DetInfo),
            ShortHand = try_goal(MaybeIO, ResultVar, TryGoal)
        ;
            ShortHand0 = bi_implication(_, _),
            % These should have been expanded out by now.
            unexpected($module, $pred, "bi_implication")
        ),
        GoalExpr = shorthand(ShortHand)
    ).

%-----------------------------------------------------------------------------%

:- pred det_infer_conj(list(hlds_goal)::in, list(hlds_goal)::out, instmap::in,
    soln_context::in, list(failing_context)::in, maybe(pess_info)::in,
    determinism::out,
    list(failing_context)::in, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_conj([], [], _InstMap0, _SolnContext, _RightFailingContexts,
        _MaybePromiseEqvSolutionSets, detism_det,
        !ConjFailingContexts, !DetInfo).
det_infer_conj([Goal0 | Goals0], [Goal | Goals], InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets, Detism,
        !ConjFailingContexts, !DetInfo) :-
    % We should look to see when we get to a not_reached point
    % and optimize away the remaining elements of the conjunction.
    % But that optimization is done in the code generator anyway.

    % We infer the determinisms right-to-left, so that we can propagate
    % the SolnContext properly.

    % First, process the second and subsequent conjuncts.
    update_instmap(Goal0, InstMap0, InstMap1),
    det_infer_conj(Goals0, Goals, InstMap1, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        TailDetism, !ConjFailingContexts, !DetInfo),
    determinism_components(TailDetism, TailCanFail, _TailMaxSolns),

    % Next, work out whether the first conjunct is in a first_soln context
    % or not. We obviously need all its solutions if we need all the solutions
    % of the conjunction. However, even if we need only the first solution
    % of the conjunction, we may need to generate more than one solution
    % of the first conjunct if the later conjuncts may possibly fail.
    (
        TailCanFail = cannot_fail,
        SolnContext = first_soln
    ->
        HeadSolnContext = first_soln
    ;
        HeadSolnContext = all_solns
    ),
    % Process the first conjunct.
    det_infer_goal(Goal0, Goal, InstMap0, HeadSolnContext,
        !.ConjFailingContexts ++ RightFailingContexts,
        MaybePromiseEqvSolutionSets, HeadDetism, GoalFailingContexts,
        !DetInfo),

    % Finally combine the results computed above.
    det_conjunction_detism(HeadDetism, TailDetism, Detism),
    !:ConjFailingContexts = GoalFailingContexts ++ !.ConjFailingContexts.

:- pred det_infer_par_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_par_conj(Goals0, Goals, GoalInfo, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, GoalFailingContexts, !DetInfo) :-
    det_infer_par_conj_goals(Goals0, Goals, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, [], GoalFailingContexts, !DetInfo),
    (
        determinism_components(Detism, CanFail, Solns),
        CanFail = cannot_fail,
        Solns \= at_most_many
    ->
        true
    ;
        Context = goal_info_get_context(GoalInfo),
        determinism_components(Detism, CanFail, MaxSoln),
        (
            CanFail = can_fail,
            First = "Error: parallel conjunct may fail."
        ;
            CanFail = cannot_fail,
            (
                MaxSoln = at_most_many,
                First = "Error: parallel conjunct may have multiple solutions."
            ;
                ( MaxSoln = at_most_zero
                ; MaxSoln = at_most_one
                ; MaxSoln = at_most_many_cc
                ),
                unexpected($module, $pred,
                    "strange determinism error for parallel conjunction")
            )
        ),
        Rest = "The current implementation supports only "
            ++ "single-solution non-failing parallel conjunctions.",
        Pieces = [words(First), words(Rest)],
        det_diagnose_conj(Goals, InstMap0, detism_det, [], !DetInfo, GoalMsgs),
        sort_error_msgs(GoalMsgs, SortedGoalMsgs),
        Spec = error_spec(severity_error, phase_detism_check,
            [simple_msg(Context, [always(Pieces)])] ++ SortedGoalMsgs),
        det_info_add_error_spec(Spec, !DetInfo)
    ).

:- pred det_infer_par_conj_goals(list(hlds_goal)::in, list(hlds_goal)::out,
    instmap::in, soln_context::in, list(failing_context)::in,
    maybe(pess_info)::in, determinism::out,
    list(failing_context)::in, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_par_conj_goals([], [], _InstMap0, _SolnContext,
        _RightFailingContexts, _MaybePromiseEqvSolutionSets,
        detism_det, !ConjFailingContexts, !DetInfo).
det_infer_par_conj_goals([Goal0 | Goals0], [Goal | Goals], InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, !ConjFailingContexts, !DetInfo) :-
    det_infer_goal(Goal0, Goal, InstMap0, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, HeadDetism, GoalFailingContexts,
        !DetInfo),
    determinism_components(HeadDetism, HeadCanFail, HeadMaxSolns),

    det_infer_par_conj_goals(Goals0, Goals, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        TailDetism, !ConjFailingContexts, !DetInfo),
    determinism_components(TailDetism, TailCanFail, TailMaxSolns),

    det_conjunction_maxsoln(HeadMaxSolns, TailMaxSolns, MaxSolns),
    det_conjunction_canfail(HeadCanFail, TailCanFail, CanFail),
    determinism_components(Detism, CanFail, MaxSolns),
    !:ConjFailingContexts = GoalFailingContexts ++ !.ConjFailingContexts.

:- pred det_infer_disj(list(hlds_goal)::in, list(hlds_goal)::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_disj(Goals0, Goals, GoalInfo, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, GoalFailingContexts, !DetInfo) :-
    det_infer_disj_goals(Goals0, Goals, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        can_fail, at_most_zero, Detism, [], GoalFailingContexts0,
        !DetInfo),
    (
        Goals = [],
        Context = goal_info_get_context(GoalInfo),
        FailingContext = failing_context(Context, fail_goal),
        GoalFailingContexts = [FailingContext | GoalFailingContexts0]
    ;
        Goals = [_ | _],
        GoalFailingContexts = GoalFailingContexts0
    ).

:- pred det_infer_disj_goals(list(hlds_goal)::in, list(hlds_goal)::out,
    instmap::in, soln_context::in, list(failing_context)::in,
    maybe(pess_info)::in, can_fail::in, soln_count::in,
    determinism::out, list(failing_context)::in, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_disj_goals([], [], _InstMap0, _SolnContext, _RightFailingContexts,
        _MaybePromiseEqvSolutionSets, CanFail, MaxSolns, Detism,
        !DisjFailingContexts, !DetInfo) :-
    determinism_components(Detism, CanFail, MaxSolns).
det_infer_disj_goals([Goal0 | Goals0], [Goal | Goals], InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        !.CanFail, !.MaxSolns, Detism, !DisjFailingContexts, !DetInfo) :-
    det_infer_goal(Goal0, Goal, InstMap0, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, FirstDetism, GoalFailingContexts,
        !DetInfo),
    determinism_components(FirstDetism, FirstCanFail, FirstMaxSolns),
    Goal = hlds_goal(_, GoalInfo),
    % If a disjunct cannot succeed but is marked with the
    % preserve_backtrack_into feature, treat it as being able to succeed
    % when computing the max number of solutions of the disjunction as a
    % whole, *provided* that some earlier disjuct could succeed. The idea
    % is that ( marked failure ; det ) should be treated as det, since all
    % backtracking is local within it, while disjunctions of the form
    % ( det ; marked failure ) should be treated as multi, since we want
    % to be able to backtrack to the second disjunct from *outside*
    % the disjunction. This is useful for program transformation that want
    % to get control on exits to and redos into model_non procedures.
    % Deep profiling is one such transformation.
    (
        !.MaxSolns \= at_most_zero,
        FirstMaxSolns = at_most_zero,
        goal_info_has_feature(GoalInfo, feature_preserve_backtrack_into)
    ->
        AdjFirstMaxSolns = at_most_one
    ;
        AdjFirstMaxSolns = FirstMaxSolns
    ),
    det_disjunction_canfail(!.CanFail, FirstCanFail, !:CanFail),
    det_disjunction_maxsoln(!.MaxSolns, AdjFirstMaxSolns, !:MaxSolns),
    % In single-solution contexts, convert at_most_many to at_most_many_cc.
    (
        SolnContext = first_soln,
        !.MaxSolns = at_most_many
    ->
        !:MaxSolns = at_most_many_cc
    ;
        true
    ),
    det_infer_disj_goals(Goals0, Goals, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        !.CanFail, !.MaxSolns, Detism, !DisjFailingContexts, !DetInfo),
    !:DisjFailingContexts = GoalFailingContexts ++ !.DisjFailingContexts.

%-----------------------------------------------------------------------------%

:- pred det_infer_switch(prog_var::in, can_fail::in,
    list(case)::in, list(case)::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_switch(Var, SwitchCanFail, Cases0, Cases, GoalInfo, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, GoalFailingContexts, !DetInfo) :-
    % The determinism of a switch is the worst of the determinism of each
    % of the cases. Also, if only a subset of the constructors are handled,
    % then it is semideterministic or worse - this is determined
    % in switch_detection.m and handled via the SwitchCanFail field.

    det_infer_switch_cases(Cases0, Cases, Var, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        cannot_fail, at_most_zero, CasesDetism, [], GoalFailingContexts0,
        !DetInfo),
    determinism_components(CasesDetism, CasesCanFail, CasesSolns),
    % The switch variable tests are in a first_soln context if and only
    % if the switch goal as a whole was in a first_soln context and the
    % cases cannot fail.
    (
        CasesCanFail = cannot_fail,
        SolnContext = first_soln
    ->
        SwitchSolnContext = first_soln
    ;
        SwitchSolnContext = all_solns
    ),
    ExaminesRep = yes,
    det_check_for_noncanonical_type(Var, ExaminesRep, SwitchCanFail,
        SwitchSolnContext, GoalFailingContexts0, RightFailingContexts,
        GoalInfo, ccuc_switch, SwitchSolns, !DetInfo),
    det_conjunction_canfail(SwitchCanFail, CasesCanFail, CanFail),
    det_conjunction_maxsoln(SwitchSolns, CasesSolns, NumSolns),
    determinism_components(Detism, CanFail, NumSolns),
    (
        SwitchCanFail = can_fail,
        SwitchContext = goal_info_get_context(GoalInfo),
        FailingContext = failing_context(SwitchContext,
            incomplete_switch(Var)),
        GoalFailingContexts = [FailingContext | GoalFailingContexts0]
    ;
        SwitchCanFail = cannot_fail,
        GoalFailingContexts = GoalFailingContexts0
    ).

:- pred det_infer_switch_cases(list(case)::in, list(case)::out, prog_var::in,
    instmap::in, soln_context::in, list(failing_context)::in,
    maybe(pess_info)::in, can_fail::in, soln_count::in,
    determinism::out, list(failing_context)::in, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_switch_cases([], [], _Var, _InstMap0, _SolnContext,
        _RightFailingContexts, _MaybePromiseEqvSolutionSets,
        CanFail, MaxSolns, Detism, !SwitchFailingContexts, !DetInfo) :-
    determinism_components(Detism, CanFail, MaxSolns).
det_infer_switch_cases([Case0 | Cases0], [Case | Cases], Var, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        !.CanFail, !.MaxSolns, Detism, !SwitchFailingContexts,
        !DetInfo) :-
    % Technically, we should update the instmap to reflect the knowledge that
    % the var is bound to this particular constructor, but we wouldn't use
    % that information here anyway, so we don't bother.
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    det_info_get_module_info(!.DetInfo, ModuleInfo0),
    det_info_get_vartypes(!.DetInfo, VarTypes),
    map.lookup(VarTypes, Var, VarType),
    bind_var_to_functors(Var, VarType, MainConsId, OtherConsIds,
        InstMap0, InstMap1, ModuleInfo0, ModuleInfo),
    det_info_set_module_info(ModuleInfo, !DetInfo),
    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring switch case for ", !IO),
        io.write(Var, !IO),
        io.write_string(" with main cons id ", !IO),
        io.write(MainConsId, !IO),
        io.nl(!IO)
    ),
    det_infer_goal(Goal0, Goal, InstMap1, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, FirstDetism, GoalFailingContexts,
        !DetInfo),
    Case = case(MainConsId, OtherConsIds, Goal),
    determinism_components(FirstDetism, FirstCanFail, FirstMaxSolns),
    det_switch_canfail(!.CanFail, FirstCanFail, !:CanFail),
    det_switch_maxsoln(!.MaxSolns, FirstMaxSolns, !:MaxSolns),
    det_infer_switch_cases(Cases0, Cases, Var, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets,
        !.CanFail, !.MaxSolns, Detism, !SwitchFailingContexts,
        !DetInfo),
    !:SwitchFailingContexts = GoalFailingContexts ++ !.SwitchFailingContexts.

%-----------------------------------------------------------------------------%

:- pred det_infer_call(pred_id::in, proc_id::in, proc_id::out,
    list(prog_var)::in, hlds_goal_info::in, soln_context::in,
    list(failing_context)::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_call(PredId, ProcId0, ProcId, Args, GoalInfo, SolnContext,
        RightFailingContexts, Detism, GoalFailingContexts, !DetInfo) :-
    % For calls, just look up the determinism entry associated with
    % the called predicate.
    % This is the point at which annotations start changing
    % when we iterate to fixpoint for global determinism inference.
    det_lookup_pred_info_and_detism(!.DetInfo, PredId, ProcId0,
        CalleePredInfo, Detism0),

    % We do the following so that simplify.m knows whether to invoke
    % format_call.m *without* first having to traverse the procedure body.
    det_info_get_module_info(!.DetInfo, ModuleInfo),
    CalleeModuleName = pred_info_module(CalleePredInfo),
    CalleeName = pred_info_name(CalleePredInfo),
    ( is_format_call(CalleeModuleName, CalleeName, Args) ->
        det_info_set_has_format_call(!DetInfo)
    ;
        true
    ),

    % Make sure we don't try to call a committed-choice pred
    % from a non-committed-choice context.
    determinism_components(Detism0, CanFail, NumSolns),
    (
        NumSolns = at_most_many_cc,
        SolnContext = all_solns
    ->
        (
            det_find_matching_non_cc_mode(!.DetInfo, PredId, ProcId0,
                ProcIdPrime)
        ->
            ProcId = ProcIdPrime,
            determinism_components(Detism, CanFail, at_most_many)
        ;
            GoalContext = goal_info_get_context(GoalInfo),
            det_get_proc_info(!.DetInfo, ProcInfo),
            proc_info_get_varset(ProcInfo, VarSet),
            PredPieces = describe_one_pred_name(ModuleInfo,
                should_module_qualify, PredId),
            FirstPieces = [words("Error: call to")] ++ PredPieces ++
                [words("with determinism"),
                quote(mercury_det_to_string(Detism0)),
                words("occurs in a context which requires all solutions."),
                nl],
            ContextMsgs = failing_contexts_description(ModuleInfo, VarSet,
                RightFailingContexts),
            Spec = error_spec(severity_error, phase_detism_check,
                [simple_msg(GoalContext, [always(FirstPieces)])] ++
                ContextMsgs),
            det_info_add_error_spec(Spec, !DetInfo),

            ProcId = ProcId0,
            % Code elsewhere relies on the assumption that
            % SolnContext = all_solns => NumSolns \= at_most_many_cc,
            % so we need to enforce that here.
            determinism_components(Detism, CanFail, at_most_many)
        )
    ;
        ProcId = ProcId0,
        Detism = Detism0
    ),
    (
        CanFail = can_fail,
        Context = goal_info_get_context(GoalInfo),
        FailingContext = failing_context(Context, call_goal(PredId, ProcId)),
        GoalFailingContexts = [FailingContext]
    ;
        CanFail = cannot_fail,
        GoalFailingContexts = []
    ).

:- pred det_infer_generic_call(generic_call::in, determinism::in,
    hlds_goal_info::in, soln_context::in,
    list(failing_context)::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_generic_call(GenericCall, CallDetism, GoalInfo,
        SolnContext, RightFailingContexts, Detism, GoalFailingContexts,
        !DetInfo) :-
    determinism_components(CallDetism, CanFail, NumSolns),
    Context = goal_info_get_context(GoalInfo),
    (
        NumSolns = at_most_many_cc,
        SolnContext = all_solns
    ->
        % This error can only occur for higher-order calls.
        % Class method calls are only introduced by polymorphism.
        det_get_proc_info(!.DetInfo, ProcInfo),
        proc_info_get_varset(ProcInfo, VarSet),
        FirstPieces = [words("Error: higher-order call to predicate with"),
            words("determinism"), quote(mercury_det_to_string(CallDetism)),
            words("occurs in a context which requires all solutions."), nl],
        det_info_get_module_info(!.DetInfo, ModuleInfo),
        ContextMsgs = failing_contexts_description(ModuleInfo, VarSet,
            RightFailingContexts),
        Spec = error_spec(severity_error, phase_detism_check,
            [simple_msg(Context, [always(FirstPieces)])] ++ ContextMsgs),
        det_info_add_error_spec(Spec, !DetInfo),

        % Code elsewhere relies on the assumption that
        % SolnContext = all_soln => NumSolns \= at_most_many_cc,
        % so we need to enforce that here.
        determinism_components(Detism, CanFail, at_most_many)
    ;
        Detism = CallDetism
    ),
    (
        CanFail = can_fail,
        FailingContext = failing_context(Context,
            generic_call_goal(GenericCall)),
        GoalFailingContexts = [FailingContext]
    ;
        CanFail = cannot_fail,
        GoalFailingContexts = []
    ).

:- pred det_infer_foreign_proc(pragma_foreign_proc_attributes::in,
    pred_id::in, proc_id::in, pragma_foreign_code_impl::in,
    hlds_goal_info::in, soln_context::in,
    list(failing_context)::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_foreign_proc(Attributes, PredId, ProcId, _PragmaCode,
        GoalInfo, SolnContext, RightFailingContexts,
        Detism, GoalFailingContexts, !DetInfo) :-
    % Foreign_procs are handled in the same way as predicate calls.

    det_info_get_module_info(!.DetInfo, ModuleInfo),
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, _, ProcInfo),
    proc_info_get_declared_determinism(ProcInfo, MaybeDetism),
    (
        MaybeDetism = yes(Detism0),
        determinism_components(Detism0, CanFail, NumSolns0),
        (
            get_may_throw_exception(Attributes) =
                proc_will_not_throw_exception,
            Detism0 = detism_erroneous
        ->
            proc_info_get_context(ProcInfo, ProcContext),
            WillNotThrowProcPieces = describe_one_proc_name_mode(ModuleInfo,
                should_not_module_qualify, proc(PredId, ProcId)),
            WillNotThrowPieces = WillNotThrowProcPieces ++
                [words("has determinism erroneous but also has"),
                words("foreign clauses that have a"),
                fixed("`will_not_throw_exception' attribute."),
                words("This attribute cannot be applied"),
                words("to erroneous procedures.")],
            WillNotThrowSpec = error_spec(severity_error, phase_detism_check,
                [simple_msg(ProcContext, [always(WillNotThrowPieces)])]),
            det_info_add_error_spec(WillNotThrowSpec, !DetInfo)
        ;
            true
        ),
        (
            NumSolns0 = at_most_many_cc,
            SolnContext = all_solns
        ->
            GoalContext = goal_info_get_context(GoalInfo),
            proc_info_get_varset(ProcInfo, VarSet),
            WrongContextPredPieces = describe_one_pred_name(ModuleInfo,
                should_module_qualify, PredId),
            WrongContextFirstPieces = [words("Error: call to")] ++
                WrongContextPredPieces ++
                [words("with determinism"),
                quote(mercury_det_to_string(Detism0)),
                words("occurs in a context which requires all solutions."),
                nl],
            ContextMsgs = failing_contexts_description(ModuleInfo, VarSet,
                RightFailingContexts),
            Spec = error_spec(severity_error, phase_detism_check,
                [simple_msg(GoalContext, [always(WrongContextFirstPieces)])] ++
                ContextMsgs),
            det_info_add_error_spec(Spec, !DetInfo),
            NumSolns = at_most_many
        ;
            NumSolns = NumSolns0
        ),
        determinism_components(Detism, CanFail, NumSolns),
        (
            CanFail = can_fail,
            Context = goal_info_get_context(GoalInfo),
            FailingContext = failing_context(Context,
                call_goal(PredId, ProcId)),
            GoalFailingContexts = [FailingContext]
        ;
            CanFail = cannot_fail,
            GoalFailingContexts = []
        )
    ;
        MaybeDetism = no,
        proc_info_get_context(ProcInfo, Context),
        ProcPieces = describe_one_proc_name_mode(ModuleInfo,
            should_not_module_qualify, proc(PredId, ProcId)),
        Pieces = [words("In")] ++ ProcPieces ++ [suffix(":"), nl,
            words("error: `:- pragma foreign_proc(...)'"),
            words("for a procedure without a determinism declaration.")],
        Spec = error_spec(severity_error, phase_detism_check,
            [simple_msg(Context, [always(Pieces)])]),
        det_info_add_error_spec(Spec, !DetInfo),
        Detism = detism_erroneous,
        GoalFailingContexts = []
    ).

%-----------------------------------------------------------------------------%

:- pred det_infer_unify(prog_var::in, unify_rhs::in,
    unification::in, unify_context::in, unify_rhs::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_unify(LHS, RHS0, Unify, UnifyContext, RHS, GoalInfo, InstMap0,
        SolnContext, RightFailingContexts, Detism, GoalFailingContexts,
        !DetInfo) :-
    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring unification ", !IO),
        io.write(LHS, !IO),
        io.write_string(" = ", !IO),
        io.write(RHS0, !IO),
        io.nl(!IO),
        io.write(Unify, !IO),
        io.nl(!IO)
    ),
    % Unifications are either deterministic or semideterministic.
    (
        RHS0 = rhs_lambda_goal(Purity, Groundness, PredOrFunc, EvalMethod,
            NonLocalVars, Vars, Modes, LambdaDeclaredDet, Goal0),
        ( determinism_components(LambdaDeclaredDet, _, at_most_many_cc) ->
            LambdaSolnContext = first_soln
        ;
            LambdaSolnContext = all_solns
        ),
        det_info_get_module_info(!.DetInfo, ModuleInfo),
        instmap.pre_lambda_update(ModuleInfo, Vars, Modes, InstMap0, InstMap1),
        det_infer_goal(Goal0, Goal, InstMap1, LambdaSolnContext, [],
            no, LambdaInferredDet, _LambdaFailingContexts, !DetInfo),
        det_check_lambda(LambdaDeclaredDet, LambdaInferredDet,
            Goal, GoalInfo, InstMap1, !DetInfo),
        RHS = rhs_lambda_goal(Purity, Groundness, PredOrFunc, EvalMethod,
            NonLocalVars, Vars, Modes, LambdaDeclaredDet, Goal)
    ;
        ( RHS0 = rhs_var(_)
        ; RHS0 = rhs_functor(_, _, _)
        ),
        RHS = RHS0
    ),
    det_infer_unify_canfail(Unify, UnifyCanFail),
    det_infer_unify_examines_rep(Unify, ExaminesRepresentation),
    det_check_for_noncanonical_type(LHS, ExaminesRepresentation,
        UnifyCanFail, SolnContext, RightFailingContexts, [], GoalInfo,
        ccuc_unify(UnifyContext), UnifyNumSolns, !DetInfo),
    determinism_components(Detism, UnifyCanFail, UnifyNumSolns),
    (
        UnifyCanFail = can_fail,
        Context = goal_info_get_context(GoalInfo),
        (
            Unify = construct(_, _, _, _, _, _, _),
            unexpected($module, $pred, "can_fail construct")
        ;
            Unify = assign(_, _),
            unexpected($module, $pred, "can_fail assign")
        ;
            Unify = complicated_unify(_, _, _),
            (
                RHS = rhs_var(RHSVar),
                FailingGoal = test_goal(LHS, RHSVar)
            ;
                RHS = rhs_functor(ConsId, _, _),
                FailingGoal = deconstruct_goal(LHS, ConsId)
            ;
                RHS = rhs_lambda_goal(_, _, _, _, _, _, _, _, _),
                unexpected($module, $pred,
                    "complicated_unify but no fail context")
            ),
            FailingContext = failing_context(Context, FailingGoal),
            GoalFailingContexts = [FailingContext]
        ;
            Unify = deconstruct(Var, ConsId, _, _, _, _),
            FailingGoal = deconstruct_goal(Var, ConsId),
            FailingContext = failing_context(Context, FailingGoal),
            GoalFailingContexts = [FailingContext]
        ;
            Unify = simple_test(Var1, Var2),
            FailingGoal = test_goal(Var1, Var2),
            FailingContext = failing_context(Context, FailingGoal),
            GoalFailingContexts = [FailingContext]
        )
    ;
        UnifyCanFail = cannot_fail,
        GoalFailingContexts = []
    ).

%-----------------------------------------------------------------------------%

:- pred det_infer_if_then_else(hlds_goal::in, hlds_goal::out,
    hlds_goal::in, hlds_goal::out, hlds_goal::in, hlds_goal::out,
    instmap::in, soln_context::in, list(failing_context)::in,
    maybe(pess_info)::in, determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_if_then_else(Cond0, Cond, Then0, Then, Else0, Else, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        Detism, GoalFailingContexts, !DetInfo) :-
    % We process the goal right-to-left, doing the `then' before the
    % condition of the if-then-else, so that we can propagate the
    % SolnContext correctly.

    % First process the `then' part.
    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring condition\n", !IO)
    ),
    update_instmap(Cond0, InstMap0, InstMap1),
    det_infer_goal(Then0, Then, InstMap1, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, ThenDetism, ThenFailingContexts,
        !DetInfo),
    determinism_components(ThenDetism, ThenCanFail, ThenMaxSoln),

    % Next, work out the right soln_context to use for the condition.
    % The condition is in a first_soln context if and only if the goal as
    % a whole was in a first_soln context and the `then' part cannot fail.
    (
        ThenCanFail = cannot_fail,
        SolnContext = first_soln
    ->
        CondSolnContext = first_soln
    ;
        CondSolnContext = all_solns
    ),
    % Process the `condition' part,
    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring then-part\n", !IO)
    ),
    det_infer_goal(Cond0, Cond, InstMap0, CondSolnContext,
        ThenFailingContexts ++ RightFailingContexts,
        MaybePromiseEqvSolutionSets, CondDetism, _CondFailingContexts,
        !DetInfo),
    determinism_components(CondDetism, CondCanFail, CondMaxSoln),

    % Process the `else' part.
    trace [compiletime(flag("debug-det-analysis-progress")), io(!IO)] (
        io.write_string("inferring else-part\n", !IO)
    ),
    det_infer_goal(Else0, Else, InstMap0, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets, ElseDetism, ElseFailingContexts,
        !DetInfo),
    determinism_components(ElseDetism, ElseCanFail, ElseMaxSoln),

    % Finally combine the results from the three parts.
    (
        CondCanFail = cannot_fail,
        % A -> B ; C is equivalent to A, B if A cannot fail
        det_conjunction_detism(CondDetism, ThenDetism, Detism)
    ;
        CondCanFail = can_fail,
        (
            CondMaxSoln = at_most_zero,
            % A -> B ; C is equivalent to ~A, C if A cannot succeed
            det_negation_det(CondDetism, MaybeNegDetism),
            (
                MaybeNegDetism = no,
                unexpected($module, $pred,
                    "cannot find determinism of negated condition")
            ;
                MaybeNegDetism = yes(NegDetism)
            ),
            det_conjunction_detism(NegDetism, ElseDetism, Detism)
        ;
            ( CondMaxSoln = at_most_one
            ; CondMaxSoln = at_most_many
            ; CondMaxSoln = at_most_many_cc
            ),
            det_conjunction_maxsoln(CondMaxSoln, ThenMaxSoln, CTMaxSoln),
            det_switch_maxsoln(CTMaxSoln, ElseMaxSoln, MaxSoln),
            det_switch_canfail(ThenCanFail, ElseCanFail, CanFail),
            determinism_components(Detism, CanFail, MaxSoln)
        )
    ),
    % Failing contexts in the condition are ignored, since they can't lead
    % to failure of the if-then-else as a whole without one or more failing
    % contexts in the then part or the else part.
    GoalFailingContexts = ThenFailingContexts ++ ElseFailingContexts.

:- pred det_infer_not(hlds_goal::in, hlds_goal::out, hlds_goal_info::in,
    instmap::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_not(Goal0, Goal, GoalInfo, InstMap0, MaybePromiseEqvSolutionSets,
        Detism, GoalFailingContexts, !DetInfo) :-
    % Negations are almost always semideterministic. It is an error for
    % a negation to further instantiate any non-local variable. Such errors
    % will be reported by the mode analysis.
    %
    % Question: should we warn about the negation of goals that either
    % cannot succeed or cannot fail?
    % Answer: yes, probably, but it's not a high priority.
    det_infer_goal(Goal0, Goal, InstMap0, first_soln, [],
        MaybePromiseEqvSolutionSets, NegDetism, _NegatedGoalCanFail,
        !DetInfo),
    det_negation_det(NegDetism, MaybeDetism),
    (
        MaybeDetism = no,
        unexpected($module, $pred,
            "inappropriate determinism inside a negation")
    ;
        MaybeDetism = yes(Detism)
    ),
    determinism_components(Detism, CanFail, _),
    (
        CanFail = can_fail,
        Context = goal_info_get_context(GoalInfo),
        GoalFailingContexts = [failing_context(Context, negated_goal)]
    ;
        CanFail = cannot_fail,
        GoalFailingContexts = []
    ).

%-----------------------------------------------------------------------------%

:- pred det_infer_atomic(hlds_goal::in, hlds_goal::out,
    list(hlds_goal)::in, list(hlds_goal)::out, instmap::in,
    soln_context::in, list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, det_info::in, det_info::out) is det.

det_infer_atomic(MainGoal0, MainGoal, OrElseGoals0, OrElseGoals, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets0,
        Detism, !DetInfo) :-
    det_infer_atomic_goal(MainGoal0, MainGoal, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets0,
        MainDetism, !DetInfo),
    (
        OrElseGoals0 = [],
        OrElseGoals = [],
        Detism = MainDetism
    ;
        OrElseGoals0 = [_ | _],
        determinism_components(MainDetism, MainCanFail, MainMaxSolns),
        det_infer_orelse_goals(OrElseGoals0, OrElseGoals, InstMap0,
            SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets0,
            MainCanFail, CanFail, MainMaxSolns, MaxSolns0, !DetInfo),
        (
            MaxSolns0 = at_most_zero,
            MaxSolns = at_most_zero
        ;
            MaxSolns0 = at_most_one,
            % The final solution is given by the main goal or one of the
            % orelse goals; whichever succeeds first. This effectively makes
            % the atomic scope commit to the first of several possible
            % solutions.
            MaxSolns = at_most_many_cc
        ;
            MaxSolns0 = at_most_many_cc,
            MaxSolns = at_most_many_cc
        ;
            MaxSolns0 = at_most_many,
            MaxSolns = at_most_many
        ),
        determinism_components(Detism, CanFail, MaxSolns)
    ).

:- pred det_infer_atomic_goal(hlds_goal::in, hlds_goal::out, instmap::in,
    soln_context::in, list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, det_info::in, det_info::out) is det.

det_infer_atomic_goal(Goal0, Goal, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets0,
        Detism, !DetInfo) :-
    det_infer_goal(Goal0, Goal, InstMap0, SolnContext, RightFailingContexts,
        MaybePromiseEqvSolutionSets0, Detism, GoalFailingContexts,
        !DetInfo),
    (
        ( Detism = detism_det
        ; Detism = detism_cc_multi
        ; Detism = detism_erroneous
        ),
        % XXX STM Detism = detism_cc_multi            % <== TMP
        expect(unify(GoalFailingContexts, []), $module, $pred,
            "GoalFailingContexts != []")
    ;
        ( Detism = detism_semi
        ; Detism = detism_multi
        ; Detism = detism_non
        ; Detism = detism_cc_non
        ; Detism = detism_failure
        ),
        Goal0 = hlds_goal(_, GoalInfo0),
        Context = goal_info_get_context(GoalInfo0),
        DetismStr = determinism_to_string(Detism),
        Pieces = [words("Error: atomic goal has determinism"),
            quote(DetismStr), suffix(","),
            words("should be det or cc_multi.")],
        Spec = error_spec(severity_error, phase_detism_check,
            [simple_msg(Context, [always(Pieces)])]),
        det_info_add_error_spec(Spec, !DetInfo)
    ).

:- pred det_infer_orelse_goals(list(hlds_goal)::in, list(hlds_goal)::out,
    instmap::in, soln_context::in, list(failing_context)::in,
    maybe(pess_info)::in,
    can_fail::in, can_fail::out, soln_count::in, soln_count::out,
    det_info::in, det_info::out) is det.

det_infer_orelse_goals([], [], _InstMap0,
        _SolnContext, _RightFailingContexts, _MaybePromiseEqvSolutionSets,
        !CanFail, !MaxSolns, !DetInfo).
det_infer_orelse_goals([Goal0 | Goals0], [Goal | Goals], InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        !CanFail, !MaxSolns, !DetInfo) :-
    det_infer_atomic_goal(Goal0, Goal, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        FirstDetism, !DetInfo),
    determinism_components(FirstDetism, FirstCanFail, FirstMaxSolns),
    det_switch_canfail(!.CanFail, FirstCanFail, !:CanFail),
    det_switch_maxsoln(!.MaxSolns, FirstMaxSolns, !:MaxSolns),
    det_infer_orelse_goals(Goals0, Goals, InstMap0,
        SolnContext, RightFailingContexts, MaybePromiseEqvSolutionSets,
        !CanFail, !MaxSolns, !DetInfo).

%-----------------------------------------------------------------------------%

:- pred det_infer_scope(scope_reason::in, hlds_goal::in, hlds_goal::out,
    hlds_goal_info::in, instmap::in, soln_context::in,
    list(failing_context)::in, maybe(pess_info)::in,
    determinism::out, list(failing_context)::out,
    det_info::in, det_info::out) is det.

det_infer_scope(Reason, Goal0, Goal, GoalInfo, InstMap0, SolnContext,
        RightFailingContexts, MaybePromiseEqvSolutionSets0, Detism,
        GoalFailingContexts, !DetInfo) :-
    % Existential quantification may require a cut to throw away solutions,
    % but we cannot rely on explicit quantification to detect this.
    % Therefore cuts are handled in det_infer_goal.
    (
        Reason = promise_solutions(Vars, Kind),
        det_get_proc_info(!.DetInfo, ProcInfo),
        proc_info_get_varset(ProcInfo, VarSet),

        Context = goal_info_get_context(GoalInfo),
        (
            Kind = equivalent_solutions,
            SolnContextToUse = first_soln,
            MaybePromiseEqvSolutionSets = MaybePromiseEqvSolutionSets0
        ;
            Kind = equivalent_solution_sets,
            SolnContextToUse = SolnContext,
            (
                MaybePromiseEqvSolutionSets0 = no,
                MaybePromiseEqvSolutionSets = yes(pess_info(Vars, Context))
            ;
                MaybePromiseEqvSolutionSets0 = yes(PESSInfo),
                PESSInfo = pess_info(OuterVars, OuterContext),
                NestedPieces = [words("Error: "),
                    words("`promise_equivalent_solution_sets' scope"),
                    words("is nested inside another.")],
                NestedOuterPieces = [words("This is the outer"),
                    words("`promise_equivalent_solution_sets' scope.")],
                NestedSeverity = severity_conditional(warn_simple_code, yes,
                    severity_warning, no),
                NestedSpec = error_spec(NestedSeverity, phase_detism_check,
                    [simple_msg(Context,
                        [option_is_set(warn_simple_code, yes,
                            [always(NestedPieces)])]),
                    simple_msg(OuterContext,
                        [option_is_set(warn_simple_code, yes,
                            [always(NestedOuterPieces)])])
                    ]),
                det_info_add_error_spec(NestedSpec, !DetInfo),
                AllVars = set_of_var.list_to_set(OuterVars ++ Vars),
                MaybePromiseEqvSolutionSets =
                    yes(pess_info(set_of_var.to_sorted_list(AllVars),
                        OuterContext))
            )
        ;
            Kind = equivalent_solution_sets_arbitrary,
            (
                MaybePromiseEqvSolutionSets0 = no,
                ArbitraryPieces = [words("Error: "),
                    words("this `arbitrary' scope is not nested inside"),
                    words("a `promise_equivalent_solution_sets' scope.")],
                ArbitrarySpec = error_spec(severity_error, phase_detism_check,
                    [simple_msg(Context, [always(ArbitraryPieces)])]),
                det_info_add_error_spec(ArbitrarySpec, !DetInfo)
            ;
                MaybePromiseEqvSolutionSets0 = yes(pess_info(OldVars,
                    PromiseContext)),
                OverlapVars = set_of_var.intersect(
                    set_of_var.list_to_set(OldVars),
                    set_of_var.list_to_set(Vars)),
                ( set_of_var.is_empty(OverlapVars) ->
                    true
                ;
                    OverlapVarNames = list.map(
                        lookup_var_name_in_varset(VarSet),
                        set_of_var.to_sorted_list(OverlapVars)),
                    (
                        OverlapVarNames = [],
                        unexpected($module, $pred,
                            "arbitrary_promise_overlap empty")
                    ;
                        OverlapVarNames = [_],
                        OverlapVarStr = "the variable"
                    ;
                        OverlapVarNames = [_, _ | _],
                        OverlapVarStr = "the following variables:"
                    ),
                    OverlapPieces = [words("Error: "),
                        words("this `arbitrary' scope and the"),
                        words("`promise_equivalent_solution_sets' scope"),
                        words("it is nested inside overlap on"),
                        words(OverlapVarStr)] ++
                        list_to_pieces(OverlapVarNames) ++ [suffix(".")],
                    OverlapPromisePieces = [words("This is the outer "),
                        words("`promise_equivalent_solution_sets' scope.")],
                    OverlapSpec = error_spec(severity_error,
                        phase_detism_check,
                        [simple_msg(Context, [always(OverlapPieces)]),
                        simple_msg(PromiseContext,
                            [always(OverlapPromisePieces)])]),
                    det_info_add_error_spec(OverlapSpec, !DetInfo)
                )
            ),
            MaybePromiseEqvSolutionSets = no,
            SolnContextToUse = first_soln
        ),
        InstmapDelta = goal_info_get_instmap_delta(GoalInfo),
        instmap_delta_changed_vars(InstmapDelta, ChangedVars),
        det_info_get_module_info(!.DetInfo, ModuleInfo),
        % BoundVars must include both vars whose inst has changed and vars
        % with inst any which may have been further constrained by the goal.
        set_of_var.divide(var_is_ground_in_instmap(ModuleInfo, InstMap0),
            ChangedVars, _GroundAtStartVars, GroundBoundVars),
        NonLocalVars = goal_info_get_nonlocals(GoalInfo),
        AnyBoundVars = set_of_var.filter(
            var_is_any_in_instmap(ModuleInfo, InstMap0),
            NonLocalVars),
        BoundVars0 = set_of_var.union(GroundBoundVars, AnyBoundVars),
        proc_info_get_vartypes(ProcInfo, VarTypes),
        BoundVars = remove_typeinfo_vars_from_set_of_var(VarTypes, BoundVars0),

        % Which vars were bound inside the scope but not listed
        % in the promise_equivalent_solution{s,_sets} or arbitrary scope?
        set_of_var.difference(BoundVars, set_of_var.list_to_set(Vars),
            MissingVars),
        ( set_of_var.is_empty(MissingVars) ->
            true
        ;
            MissingVarNames = list.map(lookup_var_name_in_varset(VarSet),
                set_of_var.to_sorted_list(MissingVars)),
            MissingKindStr = promise_solutions_kind_str(Kind),
            (
                MissingVarNames = [],
                unexpected($module, $pred,
                    "promise_solutions_missing_vars empty")
            ;
                MissingVarNames = [_],
                MissingListStr = "a variable that is not listed:"
            ;
                MissingVarNames = [_, _ | _],
                MissingListStr = "some variables that are not listed:"
            ),
            (
                set_of_var.member(MissingVars, MissingVar),
                set_of_var.member(AnyBoundVars, MissingVar)
            ->
                BindsWords = "goal may constrain"
            ;
                BindsWords = "goal binds"
            ),
            MissingPieces = [words("Error: the"), quote(MissingKindStr),
                words(BindsWords), words(MissingListStr)]
                ++ list_to_pieces(MissingVarNames) ++ [suffix(".")],
            MissingSpec = error_spec(severity_error, phase_detism_check,
                [simple_msg(Context, [always(MissingPieces)])]),
            det_info_add_error_spec(MissingSpec, !DetInfo)
        ),
        % Which vars were listed in the promise_equivalent_solutions
        % but not bound inside the scope?
        set_of_var.difference(set_of_var.list_to_set(Vars),
            BoundVars, ExtraVars),
        det_info_get_pess_extra_vars(!.DetInfo, IgnoreExtraVars),
        (
            ( set_of_var.is_empty(ExtraVars)
            ; IgnoreExtraVars = pess_extra_vars_ignore
            )
        ->
            true
        ;
            ExtraVarNames = list.map(lookup_var_name_in_varset(VarSet),
                set_of_var.to_sorted_list(ExtraVars)),
            ExtraKindStr = promise_solutions_kind_str(Kind),
            (
                ExtraVarNames = [],
                unexpected($module, $pred,
                    "promise_solutions_extra_vars empty")
            ;
                ExtraVarNames = [_],
                ExtraListStr = "an extra variable:"
            ;
                ExtraVarNames = [_, _ | _],
                ExtraListStr = "some extra variables:"
            ),
            ExtraPieces = [words("Error: the"), quote(ExtraKindStr),
                words("goal lists"), words(ExtraListStr)] ++
                list_to_pieces(ExtraVarNames) ++ [suffix(".")],
            ExtraSpec = error_spec(severity_error, phase_detism_check,
                [simple_msg(Context, [always(ExtraPieces)])]),
            det_info_add_error_spec(ExtraSpec, !DetInfo)
        ),
        det_infer_goal(Goal0, Goal, InstMap0, SolnContextToUse,
            RightFailingContexts, MaybePromiseEqvSolutionSets, Detism,
            GoalFailingContexts, !DetInfo)
    ;
        Reason = trace_goal(_, _, _, _, _),
        det_infer_goal(Goal0, Goal, InstMap0, SolnContext,
            RightFailingContexts, MaybePromiseEqvSolutionSets0,
            Detism0, GoalFailingContexts, !DetInfo),
        (
            % Since the trace goal may not be enabled, it would be incorrect
            % to say that it ALWAYS aborts. That is why we convert a detism
            % of detism_erroneous inside the scope to detism_det outside the 
            % scope.
            (
                Detism0 = detism_det,
                Detism1 = detism_det
            ;
                Detism0 = detism_cc_multi,
                Detism1 = detism_cc_multi
            ;
                Detism0 = detism_erroneous,
                Detism1 = detism_det
            )
        ->
            Detism = Detism1
        ;
            Detism = Detism0,
            Context = goal_info_get_context(GoalInfo),
            DetismStr = determinism_to_string(Detism),
            Pieces = [words("Error: trace goal has determinism"),
                quote(DetismStr), suffix(","),
                words("should be det or cc_multi.")],
            Spec = error_spec(severity_error, phase_detism_check,
                [simple_msg(Context, [always(Pieces)])]),
            det_info_add_error_spec(Spec, !DetInfo)
        )
    ;
        ( Reason = exist_quant(_)
        ; Reason = promise_purity(_)
        ; Reason = commit(_)
        ; Reason = barrier(_)
        ),
        det_infer_goal(Goal0, Goal, InstMap0, SolnContext,
            RightFailingContexts, MaybePromiseEqvSolutionSets0,
            Detism, GoalFailingContexts, !DetInfo)
    ;
        ( Reason = require_complete_switch(_)
        ; Reason = require_detism(_)
        ),
        det_info_set_has_req_scope(!DetInfo),
        det_infer_goal(Goal0, Goal, InstMap0, SolnContext,
            RightFailingContexts, MaybePromiseEqvSolutionSets0,
            Detism, GoalFailingContexts, !DetInfo)
    ;
        Reason = from_ground_term(_, FromGroundTermKind),
        (
            FromGroundTermKind = from_ground_term_construct,
            Goal = Goal0,
            Detism = detism_det,
            GoalFailingContexts = []
        ;
            ( FromGroundTermKind = from_ground_term_deconstruct
            ; FromGroundTermKind = from_ground_term_other
            ),
            det_infer_goal(Goal0, Goal, InstMap0, SolnContext,
                RightFailingContexts, MaybePromiseEqvSolutionSets0,
                Detism, GoalFailingContexts, !DetInfo)
        ;
            FromGroundTermKind = from_ground_term_initial,
            unexpected($module, $pred, "from_ground_term_initial")
        )
    ).

%-----------------------------------------------------------------------------%

    % det_find_matching_non_cc_mode(DetInfo, PredId, ProcId0, ProcId):
    %
    % Search for a mode of the given predicate that is identical to the mode
    % ProcId0, except that its determinism is non-cc whereas ProcId0's detism
    % is cc. Let ProcId be the first such mode.
    %
:- pred det_find_matching_non_cc_mode(det_info::in, pred_id::in, proc_id::in,
    proc_id::out) is semidet.

det_find_matching_non_cc_mode(DetInfo, PredId, !ProcId) :-
    det_info_get_module_info(DetInfo, ModuleInfo),
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    pred_info_get_procedures(PredInfo, ProcTable),
    map.to_assoc_list(ProcTable, ProcList),
    det_find_matching_non_cc_mode_2(ProcList, ModuleInfo, PredInfo, !ProcId).

:- pred det_find_matching_non_cc_mode_2(assoc_list(proc_id, proc_info)::in,
    module_info::in, pred_info::in, proc_id::in, proc_id::out) is semidet.

det_find_matching_non_cc_mode_2([TestProcId - ProcInfo | Rest],
        ModuleInfo, PredInfo, !ProcId) :-
    (
        TestProcId \= !.ProcId,
        proc_info_interface_determinism(ProcInfo, Detism),
        determinism_components(Detism, _CanFail, MaxSoln),
        MaxSoln = at_most_many,
        modes_are_identical_bar_cc(!.ProcId, TestProcId, PredInfo, ModuleInfo)
    ->
        !:ProcId = TestProcId
    ;
        det_find_matching_non_cc_mode_2(Rest, ModuleInfo, PredInfo, !ProcId)
    ).

%-----------------------------------------------------------------------------%

:- pred det_check_for_noncanonical_type(prog_var::in, bool::in, can_fail::in,
    soln_context::in, list(failing_context)::in, list(failing_context)::in,
    hlds_goal_info::in, cc_unify_context::in, soln_count::out,
    det_info::in, det_info::out) is det.

det_check_for_noncanonical_type(Var, ExaminesRepresentation, CanFail,
        SolnContext, FailingContextsA, FailingContextsB, GoalInfo, GoalContext,
        NumSolns, !DetInfo) :-
    (
        % Check for unifications that attempt to examine the representation
        % of a type that does not have a single representation for each
        % abstract value.

        ExaminesRepresentation = yes,
        det_get_proc_info(!.DetInfo, ProcInfo),
        proc_info_get_vartypes(ProcInfo, VarTypes),
        map.lookup(VarTypes, Var, Type),
        det_type_has_user_defined_equality_pred(!.DetInfo, Type)
    ->
        (
            CanFail = can_fail,
            Context = goal_info_get_context(GoalInfo),
            proc_info_get_varset(ProcInfo, VarSet),
            (
                GoalContext = ccuc_switch,
                VarStr = mercury_var_to_string(VarSet, no, Var),
                Pieces0 = [words("In switch on variable"), quote(VarStr),
                    suffix(":"), nl]
            ;
                GoalContext = ccuc_unify(UnifyContext),
                unify_context_to_pieces(UnifyContext, [], Pieces0)
            ),
            (
                Pieces0 = [],
                ErrorMsg = "Error:"
            ;
                Pieces0 = [_ | _],
                ErrorMsg = "error:"
            ),
            Pieces1 = [words(ErrorMsg),
                words("unification for non-canonical type"),
                top_ctor_of_type(Type),
                words("is not guaranteed to succeed.")],
            VerbosePieces = [words("Since the type has a user-defined"),
                words("equality predicate, I must presume that"),
                words("there is more than one possible concrete"),
                words("representation for each abstract value"),
                words("of this type. The success of this unification"),
                words("might depend on the choice of concrete"),
                words("representation. Figuring out whether there is"),
                words("a solution to this unification would require"),
                words("backtracking over all possible"),
                words("representations, but I'm not going to do that"),
                words("implicitly. (If that's really what you want,"),
                words("you must do it explicitly.)")],
            Spec = error_spec(severity_error, phase_detism_check,
                [simple_msg(Context,
                    [always(Pieces0 ++ Pieces1),
                    verbose_only(VerbosePieces)])]),
            det_info_add_error_spec(Spec, !DetInfo)
        ;
            CanFail = cannot_fail,
            (
                SolnContext = all_solns,
                Context = goal_info_get_context(GoalInfo),
                proc_info_get_varset(ProcInfo, VarSet),
                (
                    GoalContext = ccuc_switch,
                    VarStr = mercury_var_to_string(VarSet, no, Var),
                    Pieces0 = [words("In switch on variable"), quote(VarStr),
                        suffix(":"), nl]
                ;
                    GoalContext = ccuc_unify(UnifyContext),
                    unify_context_first_to_pieces(is_first, _,
                        UnifyContext, [], Pieces0)
                ),
                (
                    Pieces0 = [],
                    ErrorMsg = "Error:"
                ;
                    Pieces0 = [_ | _],
                    ErrorMsg = "error:"
                ),
                Pieces1 = [words(ErrorMsg),
                    words("unification for non-canonical type"),
                    top_ctor_of_type(Type),
                    words("occurs in a context which requires all solutions."),
                    nl],
                VerbosePieces = [words("Since the type has a user-defined"),
                    words("equality predicate, I must presume that"),
                    words("there is more than one possible concrete"),
                    words("representation for each abstract value"),
                    words("of this type. The results of this unification"),
                    words("might depend on the choice of concrete"),
                    words("representation. Finding all possible"),
                    words("solutions to this unification would require"),
                    words("backtracking over all possible"),
                    words("representations, but I'm not going to do that"),
                    words("implicitly. (If that's really what you want,"),
                    words("you must do it explicitly.)")],
                det_info_get_module_info(!.DetInfo, ModuleInfo),
                ContextMsgs = failing_contexts_description(ModuleInfo, VarSet,
                    FailingContextsA ++ FailingContextsB),
                Spec = error_spec(severity_error, phase_detism_check,
                    [simple_msg(Context,
                        [always(Pieces0 ++ Pieces1),
                        verbose_only(VerbosePieces)])]
                    ++ ContextMsgs),
                det_info_add_error_spec(Spec, !DetInfo)
            ;
                SolnContext = first_soln
            )
        ),
        (
            SolnContext = first_soln,
            NumSolns = at_most_many_cc
        ;
            SolnContext = all_solns,
            NumSolns = at_most_many
        )
    ;
        NumSolns = at_most_one
    ).

    % Return true iff the principal type constructor of the given type
    % has user-defined equality.
    %
:- pred det_type_has_user_defined_equality_pred(det_info::in,
    mer_type::in) is semidet.

det_type_has_user_defined_equality_pred(DetInfo, Type) :-
    det_info_get_module_info(DetInfo, ModuleInfo),
    type_has_user_defined_equality_pred(ModuleInfo, Type, _).

    % Return yes iff the results of the specified unification might depend
    % on the concrete representation of the abstract values involved.
    %
:- pred det_infer_unify_examines_rep(unification::in, bool::out) is det.

det_infer_unify_examines_rep(assign(_, _), no).
det_infer_unify_examines_rep(construct(_, _, _, _, _, _, _), no).
det_infer_unify_examines_rep(deconstruct(_, _, _, _, _, _), yes).
det_infer_unify_examines_rep(simple_test(_, _), yes).
    % Some complicated modes of complicated unifications _do_
    % examine the representation...
    % but we will catch those by reporting errors in the
    % compiler-generated code for the complicated unification.
det_infer_unify_examines_rep(complicated_unify(_, _, _), no).

    % Deconstruction unifications cannot fail if the type only has one
    % constructor, or if the variable is known to be already bound
    % to the appropriate functor.
    %
    % This is handled (modulo bugs) by modes.m, which sets the appropriate
    % field in the deconstruct(...) to can_fail for those deconstruction
    % unifications which might fail. But switch_detection.m may set it back
    % to cannot_fail again, if it moves the functor test into a switch instead.
    %
:- pred det_infer_unify_canfail(unification::in, can_fail::out) is det.

det_infer_unify_canfail(deconstruct(_, _, _, _, CanFail, _), CanFail).
det_infer_unify_canfail(assign(_, _), cannot_fail).
det_infer_unify_canfail(construct(_, _, _, _, _, _, _), cannot_fail).
det_infer_unify_canfail(simple_test(_, _), can_fail).
det_infer_unify_canfail(complicated_unify(_, CanFail, _), CanFail).

%-----------------------------------------------------------------------------%

det_get_soln_context(DeclaredDetism, SolnContext) :-
    ( determinism_components(DeclaredDetism, _, at_most_many_cc) ->
        SolnContext = first_soln
    ;
        SolnContext = all_solns
    ).

%-----------------------------------------------------------------------------%

    % Determinism_declarations takes a module_info as input and returns
    % three lists of procedure ids:
    %
    % - DeclaredProcs holds the procedures that have declarations that need
    %   to be checked.
    %
    % - UndeclaredProcs holds the procedures that don't have declarations
    %   whose determinism needs to be inferred.
    %
    % - NoInferProcs holds the procedures whose determinism is already
    %   known, and which should not be processed further.
    %
:- pred determinism_declarations(module_info::in, list(pred_id)::in,
    pred_proc_list::out, pred_proc_list::out, pred_proc_list::out) is det.

determinism_declarations(ModuleInfo, PredIds,
        DeclaredProcs, UndeclaredProcs, NoInferProcs) :-
    get_all_pred_procs(ModuleInfo, PredIds, PredProcs),
    segregate_procs(ModuleInfo, PredProcs,
        DeclaredProcs, UndeclaredProcs, NoInferProcs).

    % Get_all_pred_procs returns a list of all the procedure ids for that
    % module (except class methods, which do not need to be checked since
    % we generate the code ourselves).
    %
:- pred get_all_pred_procs(module_info::in, list(pred_id)::in,
    pred_proc_list::out) is det.

get_all_pred_procs(ModuleInfo, PredIds, PredProcs) :-
    module_info_get_preds(ModuleInfo, PredTable),
    get_all_pred_procs_2(PredTable, PredIds, [], PredProcs).

:- pred get_all_pred_procs_2(pred_table::in, list(pred_id)::in,
    pred_proc_list::in, pred_proc_list::out) is det.

get_all_pred_procs_2(_PredTable, [], !PredProcs).
get_all_pred_procs_2(PredTable, [PredId | PredIds], !PredProcs) :-
    map.lookup(PredTable, PredId, Pred),
    ProcIds = pred_info_procids(Pred),
    fold_pred_modes(PredId, ProcIds, !PredProcs),
    get_all_pred_procs_2(PredTable, PredIds, !PredProcs).

:- pred fold_pred_modes(pred_id::in, list(proc_id)::in, pred_proc_list::in,
    pred_proc_list::out) is det.

fold_pred_modes(_PredId, [], !PredProcs).
fold_pred_modes(PredId, [ProcId | ProcIds], !PredProcs) :-
    !:PredProcs = [proc(PredId, ProcId) | !.PredProcs],
    fold_pred_modes(PredId, ProcIds, !PredProcs).

    % segregate_procs(ModuleInfo, PredProcs,
    %   DeclaredProcs, UndeclaredProcs, NoInferProcs):
    %
    % The predicate partitions the pred_proc_ids in PredProcs into three
    % categories:
    %
    % - DeclaredProcs holds the procedures that have declarations that need
    %   to be checked.
    %
    % - UndeclaredProcs holds the procedures that don't have declarations
    %   whose determinism needs to be inferred.
    %
    % - NoInferProcs holds the procedures whose determinism is already
    %   known, and which should not be processed further.
    %
:- pred segregate_procs(module_info::in, pred_proc_list::in,
    pred_proc_list::out, pred_proc_list::out, pred_proc_list::out) is det.

segregate_procs(ModuleInfo, PredProcs, DeclaredProcs, UndeclaredProcs,
        NoInferProcs) :-
    segregate_procs_2(ModuleInfo, PredProcs, [], DeclaredProcs,
        [], UndeclaredProcs, [], NoInferProcs).

:- pred segregate_procs_2(module_info::in, pred_proc_list::in,
    pred_proc_list::in, pred_proc_list::out,
    pred_proc_list::in, pred_proc_list::out,
    pred_proc_list::in, pred_proc_list::out) is det.

segregate_procs_2(_ModuleInfo, [], !DeclaredProcs,
        !UndeclaredProcs, !NoInferProcs).
segregate_procs_2(ModuleInfo, [PredProcId | PredProcIds],
        !DeclaredProcs, !UndeclaredProcs, !NoInferProcs) :-
    PredProcId = proc(PredId, ProcId),
    module_info_get_preds(ModuleInfo, Preds),
    map.lookup(Preds, PredId, Pred),
    (
        (
            pred_info_is_imported(Pred)
        ;
            pred_info_is_pseudo_imported(Pred),
            hlds_pred.in_in_unification_proc_id(ProcId)
        ;
            pred_info_get_markers(Pred, Markers),
            check_marker(Markers, marker_class_method)
        )
    ->
        !:NoInferProcs = [PredProcId | !.NoInferProcs]
    ;
        pred_info_get_procedures(Pred, Procs),
        map.lookup(Procs, ProcId, Proc),
        proc_info_get_declared_determinism(Proc, MaybeDetism),
        (
            MaybeDetism = no,
            !:UndeclaredProcs = [PredProcId | !.UndeclaredProcs]
        ;
            MaybeDetism = yes(_),
            !:DeclaredProcs = [PredProcId | !.DeclaredProcs]
        )
    ),
    segregate_procs_2(ModuleInfo, PredProcIds, !DeclaredProcs,
        !UndeclaredProcs, !NoInferProcs).

    % We can't infer a tighter determinism for imported procedures or for
    % class methods, so set the inferred determinism to be the same as the
    % declared determinism. This can't be done easily during make_hlds since
    % inter-module optimization means that the import_status of procedures
    % isn't determined until after all items are processed.
    %
:- pred set_non_inferred_proc_determinism(pred_proc_id::in,
    module_info::in, module_info::out) is det.

set_non_inferred_proc_determinism(proc(PredId, ProcId), !ModuleInfo) :-
    module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),
    pred_info_get_procedures(PredInfo0, Procs0),
    map.lookup(Procs0, ProcId, ProcInfo0),
    proc_info_get_declared_determinism(ProcInfo0, MaybeDet),
    (
        MaybeDet = yes(Det),
        proc_info_set_inferred_determinism(Det, ProcInfo0, ProcInfo),
        map.det_update(ProcId, ProcInfo, Procs0, Procs),
        pred_info_set_procedures(Procs, PredInfo0, PredInfo),
        module_info_set_pred_info(PredId, PredInfo, !ModuleInfo)
    ;
        MaybeDet = no
    ).

%-----------------------------------------------------------------------------%
:- end_module check_hlds.det_analysis.
%-----------------------------------------------------------------------------%
