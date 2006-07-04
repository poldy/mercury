%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: liveness.m.
% Main authors: conway, zs, trd.

% This module traverses the goal for each procedure, and adds liveness
% annotations to the goal_info for each sub-goal.  These annotations are the
% pre-birth set, the post-birth set, the pre-death set, the post-death set,
% and the resume_point field.
%
% Because it recomputes each of these annotations from scratch, it is safe to
% call this module multiple times, and in fact we do so if stack slot
% optimization is enabled.
%
% NOTE: the concept of `liveness' here is different to that used in mode
% analysis. Mode analysis is concerned with the liveness of what is *pointed*
% to by a variable, for the purpose of avoiding and/or keeping track of
% aliasing and for structure re-use optimization, whereas here we are
% concerned with the liveness of the variable itself, for the purposes of
% optimizing stack slot and register usage.  Variables have a lifetime: each
% variable is born, gets used, and then dies.  To minimize stack slot and
% register usage, the birth should be as late as possible (but before the
% first possible use), and the death should be as early as possible (but after
% the last possible use).
%
% We compute liveness related information in four distinct passes.
%
% The first pass, detect_liveness_in_goal, finds the first value-giving
% occurrence of each variable on each computation path. Goals containing the
% first such occurrence of a variable include that variable in their pre-birth
% set. In branched structures, branches whose endpoint is not reachable
% include a post-birth set listing the variables that should have been born in
% that branch but haven't. Variables that shouldn't have been born but have
% been (in computation paths that cannot succeed) are included in the
% post-death set of the goal concerned.
%
% The second pass, detect_deadness_in_goal, finds the last occurrence of each
% variable on each computation path. Goals containing the last occurrence of a
% variable include that variable in their post-death set. In branched
% structures, branches in which a variable is not used at all include a
% pre-death set listing the variables that have died in parallel branches.
% Branches whose end-points are unreachable are handled specially; see the
% comment before union_branch_deadness for details.
%
% The third pass is optional: it delays the deaths of named variables until
% the last possible moment. This can be useful if debugging is enabled, as it
% allows the programmer to look at the values of such variables at as many
% trace events as possible. If debugging is not enabled, this pass is a pure
% pessimization (it increases stack slot pressure and thus probably increases
% the size of the procedure's stack frame), and therefore should not be
% enabled.
%
% The second and third passes cannot be combined, because the second pass
% traverses goals backwards while the third pass traverses goals forwards.
% (The second pass does propagate liveness forwards, but it does so only along
% one branch of every branched control structure.)
%
% The fourth pass, detect_resume_points_in_goal, finds goals that establish
% resume points and attaches to them a resume_point annotation listing the
% variables that may be referenced by the code at that resume point as well as
% the nature of the required entry labels.

% Typeinfo liveness calculation notes:
%
% When using accurate gc or execution tracing, liveness is computed slightly
% differently.  The runtime system needs access to the typeinfo variables of
% any variable that is live at a continuation or event.  (This includes
% typeclass info variables that hold typeinfos; in the following "typeinfo
% variables" also includes typeclass info variables.)
%
% Hence, the invariant needed for typeinfo-liveness calculation:
%   a variable holding a typeinfo must be live at any continuation
%   where any variable whose type is described (in whole or in part)
%   by that typeinfo is live.
%
% Typeinfos are introduced as either one of the head variables, or a new
% variable created by a goal in the procedure. If introduced as a head
% variable, initial_liveness will add it to the initial live set of variables
% -- no variable could be introduced earlier than the start of the goal. If
% introduced by a goal in the procedure, that goal must occur before any call
% that requires the typeinfo, so the variable will be born before the
% continuation after the call. So the typeinfo variables will always be born
% before any continuation where they are needed.
%
% A typeinfo variable becomes dead after both the following conditions
% are true:
%
%   (1) The typeinfo variable is not used again (when it is no
%       longer part of the nonlocals)
%   (2) No other nonlocal variable's type is described by that typeinfo
%       variable.
%
% (1) happens without any changes to the liveness computation (it is
%     the normal condition for variables becoming dead). This is more
%     conservative than what is required for the invariant, but is
%     required for code generation, so we should keep it ;-)
% (2) is implemented by adding the typeinfo variables for the types of the
%     nonlocals to the nonlocals for the purposes of computing liveness.
%
% In some circumstances, one of which is tests/debugger/resume_typeinfos.m, it
% is possible for a typeinfo variable to be born in a goal without that
% typeinfo variable appearing anywhere else in the procedure body.
% Nevertheless, with typeinfo liveness, we must consider such variables to be
% born in such goals even though they do not appear in the nonlocals set or in
% the instmap delta. (If they were not born, it would be an error for them to
% die, and die they will, at the last occurrence of a variable whose type they
% (partially) describe.) The special case solution we adopt for such
% situations is that we consider the first appearance of a typeinfo variable
% in the typeinfo-completed nonlocals set of a goal to be a value giving
% occurrence, even if the typeinfo does not appear in the instmap delta.  This
% is safe, since with our current scheme for handling polymorphism, the first
% appearance will in fact always ground the typeinfo.
%
% So typeinfo variables will always be born before they are needed, and die
% only when no other variable needing them will be live, so the invariant
% holds.

% Quantification notes:
%
% If a variable is not live on entry to a goal, but the goal gives it a value,
% the code of this module assumes that:
%
% (a) any parallel goals also give it a value, or
% (b) the variable is local to this goal and hence does not occur in parallel
%     goals.
%
% If a variable occurs in the nonlocal set of the goal, the code of this
% assumes that (b) is not true, and will therefore require (a) to be true.
% If some of the parallel goals cannot succeed, the first pass will include
% the variable in their post-birth sets.
%
% If a variable occurs in the nonlocal set of the goal, but is actually local
% to the goal, then any occurrence of that variable in the postbirth sets of
% parallel goals will lead to an inconsistency, because the variable will not
% die on those parallel paths, but will die on the path that actually gives a
% value to the variable.
%
% The nonlocal set of a goal is in general allowed to overapproximate the true
% set of nonlocal variables of the goal. Since this module requires *exact*
% information about nonlocals, it must recompute the nonlocal sets before
% starting.

%-----------------------------------------------------------------------------%

:- module ll_backend.liveness.
:- interface.

:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module parse_tree.prog_data.

:- import_module io.
:- import_module set.

%-----------------------------------------------------------------------------%

    % Add liveness annotations to the goal of the procedure. This consists of
    % the {pre,post}{birth,death} sets and resume point information.
    %
:- pred detect_liveness_proc(pred_id::in, proc_id::in, module_info::in,
    proc_info::in, proc_info::out, io::di, io::uo) is det.

    % Return the set of variables live at the start of the procedure.
    %
:- pred initial_liveness(proc_info::in, pred_id::in, module_info::in,
    set(prog_var)::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module check_hlds.polymorphism.
:- import_module hlds.arg_info.
:- import_module hlds.code_model.
:- import_module hlds.goal_form.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_out.
:- import_module hlds.hlds_rtti.
:- import_module hlds.instmap.
:- import_module hlds.passes_aux.
:- import_module hlds.quantification.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module libs.trace_params.
:- import_module ll_backend.llds.
:- import_module ll_backend.trace.
:- import_module parse_tree.prog_util.

:- import_module assoc_list.
:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module string.
:- import_module svset.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

detect_liveness_proc(PredId, _ProcId, ModuleInfo, !ProcInfo, !IO) :-
    requantify_proc(!ProcInfo),

    proc_info_get_goal(!.ProcInfo, Goal0),
    proc_info_get_varset(!.ProcInfo, VarSet),
    proc_info_get_vartypes(!.ProcInfo, VarTypes),
    proc_info_get_rtti_varmaps(!.ProcInfo, RttiVarMaps),
    module_info_get_globals(ModuleInfo, Globals),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    body_should_use_typeinfo_liveness(PredInfo, Globals, TypeInfoLiveness),
    live_info_init(ModuleInfo, TypeInfoLiveness, VarTypes, RttiVarMaps,
        VarSet, LiveInfo),

    globals.lookup_int_option(Globals, debug_liveness, DebugLiveness),
    pred_id_to_int(PredId, PredIdInt),
    maybe_write_progress_message("\nbefore liveness",
        DebugLiveness, PredIdInt, Goal0, VarSet, ModuleInfo, !IO),

    initial_liveness(!.ProcInfo, PredId, ModuleInfo, Liveness0),
    detect_liveness_in_goal(Goal0, Goal1, Liveness0, _, LiveInfo),

    maybe_write_progress_message("\nafter liveness",
        DebugLiveness, PredIdInt, Goal1, VarSet, ModuleInfo, !IO),

    initial_deadness(!.ProcInfo, LiveInfo, ModuleInfo, Deadness0),
    detect_deadness_in_goal(Goal1, Goal2, Deadness0, _, Liveness0, LiveInfo),
    maybe_write_progress_message("\nafter deadness",
        DebugLiveness, PredIdInt, Goal2, VarSet, ModuleInfo, !IO),

    (
        globals.get_trace_level(Globals, TraceLevel),
        AllowDelayDeath = trace_level_allows_delay_death(TraceLevel),
        AllowDelayDeath = yes,
        globals.lookup_bool_option(Globals, delay_death, DelayDeath),
        DelayDeath = yes
    ->
        delay_death_proc_body(Goal2, Goal3, VarSet, Liveness0),
        maybe_write_progress_message("\nafter delay death",
            DebugLiveness, PredIdInt, Goal3, VarSet, ModuleInfo, !IO)
    ;
        Goal3 = Goal2
    ),

    globals.get_trace_level(Globals, TraceLevel),
    ( eff_trace_level_is_none(PredInfo, !.ProcInfo, TraceLevel) = no ->
        trace.fail_vars(ModuleInfo, !.ProcInfo, ResumeVars0)
    ;
        set.init(ResumeVars0)
    ),
    detect_resume_points_in_goal(Goal3, Goal, Liveness0, _,
        LiveInfo, ResumeVars0),
    maybe_write_progress_message("\nafter resume point",
        DebugLiveness, PredIdInt, Goal, VarSet, ModuleInfo, !IO),
    proc_info_set_goal(Goal, !ProcInfo),
    proc_info_set_liveness_info(Liveness0, !ProcInfo).

:- pred maybe_write_progress_message(string::in, int::in, int::in,
    hlds_goal::in, prog_varset::in, module_info::in,
    io::di, io::uo) is det.

maybe_write_progress_message(Message, DebugLiveness, PredIdInt,
        Goal, VarSet, ModuleInfo, !IO) :-
    ( DebugLiveness = PredIdInt ->
        io.write_string(Message, !IO),
        io.write_string(":\n", !IO),
        hlds_out.write_goal(Goal, ModuleInfo, VarSet, yes, 0, "\n", !IO)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred detect_liveness_in_goal(hlds_goal::in, hlds_goal::out,
    set(prog_var)::in, set(prog_var)::out, live_info::in) is det.

detect_liveness_in_goal(Goal0 - GoalInfo0, Goal - GoalInfo,
        Liveness0, Liveness, LiveInfo) :-

        % work out which variables get born in this goal
    liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo0,
        BaseNonLocals, CompletedNonLocals),
    set.difference(CompletedNonLocals, Liveness0, NewVarsSet),
    set.to_sorted_list(NewVarsSet, NewVarsList),
    goal_info_get_instmap_delta(GoalInfo0, InstMapDelta),
    set.init(Empty),
    ( instmap_delta_is_unreachable(InstMapDelta) ->
        Births = Empty
    ;
        set.init(Births0),
        find_value_giving_occurrences(NewVarsList, LiveInfo,
            InstMapDelta, Births0, Births1),
        set.difference(CompletedNonLocals, BaseNonLocals, TypeInfos),
        set.difference(TypeInfos, Liveness0, NewTypeInfos),
        set.union(Births1, NewTypeInfos, Births)
    ),
    ( goal_is_atomic(Goal0) ->
        PreDeaths = Empty,
        PreBirths = Births,
        PostDeaths = Empty,
        PostBirths = Empty,
        Goal = Goal0
    ;
        PreDeaths = Empty,
        PreBirths = Empty,
        detect_liveness_in_goal_2(Goal0, Goal, Liveness0, ActualLiveness,
            CompletedNonLocals, LiveInfo),
        set.intersect(CompletedNonLocals, ActualLiveness, NonLocalLiveness),
        set.union(NonLocalLiveness, Liveness0, FinalLiveness),
        set.difference(FinalLiveness, Liveness, PostDeaths),
        set.difference(Liveness, FinalLiveness, PostBirths)
    ),
    set.union(Liveness0, Births, Liveness),
    % We initialize all the fields in order to obliterate any
    % annotations left by a previous invocation of this module.
    goal_info_initialize_liveness_info(PreBirths, PostBirths,
        PreDeaths, PostDeaths, no_resume_point, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%

    % Here we process each of the different sorts of goals.
    %
:- pred detect_liveness_in_goal_2(hlds_goal_expr::in, hlds_goal_expr::out,
    set(prog_var)::in, set(prog_var)::out, set(prog_var)::in,
    live_info::in) is det.

detect_liveness_in_goal_2(conj(ConjType, Goals0), conj(ConjType, Goals),
        !Liveness, NonLocals, LiveInfo) :-
    (
        ConjType = plain_conj,
        detect_liveness_in_conj(Goals0, Goals, !Liveness, LiveInfo)
    ;
        ConjType = parallel_conj,
        set.init(Union0),
        detect_liveness_in_par_conj(Goals0, Goals, !.Liveness, NonLocals,
            LiveInfo, Union0, Union),
        set.union(Union, !Liveness)
    ).

detect_liveness_in_goal_2(disj(Goals0), disj(Goals), !Liveness,
        NonLocals, LiveInfo) :-
    set.init(Union0),
    detect_liveness_in_disj(Goals0, Goals, !.Liveness, NonLocals,
        LiveInfo, Union0, Union),
    set.union(Union, !Liveness).

detect_liveness_in_goal_2(switch(Var, Det, Cases0), switch(Var, Det, Cases),
        !Liveness, NonLocals, LiveInfo) :-
    detect_liveness_in_cases(Cases0, Cases, !.Liveness, NonLocals,
        LiveInfo, !Liveness).

detect_liveness_in_goal_2(not(Goal0), not(Goal), !Liveness, _, LiveInfo) :-
    detect_liveness_in_goal(Goal0, Goal, !Liveness, LiveInfo).

detect_liveness_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0),
        if_then_else(Vars, Cond, Then, Else),
        Liveness0, Liveness, NonLocals, LiveInfo) :-
    detect_liveness_in_goal(Cond0, Cond, Liveness0, LivenessCond, LiveInfo),

    % If the condition cannot succeed, any variables which become live
    % in the else part should be put in the post-birth set of the then part
    % by add_liveness_after_goal, and the other sets should be empty.
    Cond = _ - CondInfo,
    goal_info_get_instmap_delta(CondInfo, CondDelta),
    ( instmap_delta_is_unreachable(CondDelta) ->
        LivenessThen = LivenessCond,
        Then1 = Then0
    ;
        detect_liveness_in_goal(Then0, Then1,
            LivenessCond, LivenessThen, LiveInfo)
    ),

    detect_liveness_in_goal(Else0, Else1, Liveness0, LivenessElse, LiveInfo),

    set.union(LivenessThen, LivenessElse, Liveness),
    set.intersect(Liveness, NonLocals, NonLocalLiveness),

    set.difference(NonLocalLiveness, LivenessThen, ResidueThen),
    set.difference(NonLocalLiveness, LivenessElse, ResidueElse),

    add_liveness_after_goal(Then1, ResidueThen, Then),
    add_liveness_after_goal(Else1, ResidueElse, Else).

detect_liveness_in_goal_2(scope(Reason, Goal0), scope(Reason, Goal),
        !Liveness, _, LiveInfo) :-
    detect_liveness_in_goal(Goal0, Goal, !Liveness, LiveInfo).

detect_liveness_in_goal_2(generic_call(_, _, _, _), _, _, _, _, _) :-
    unexpected(this_file, "higher-order-call in detect_liveness_in_goal_2").

detect_liveness_in_goal_2(call(_, _, _, _, _, _), _, _, _, _, _) :-
    unexpected(this_file, "call in detect_liveness_in_goal_2").

detect_liveness_in_goal_2(unify(_, _, _, _, _), _, _, _, _, _) :-
    unexpected(this_file, "unify in detect_liveness_in_goal_2").

detect_liveness_in_goal_2(foreign_proc(_, _, _, _, _, _),
        _, _, _, _, _) :-
    unexpected(this_file, "foreign_proc in detect_liveness_in_goal_2").

detect_liveness_in_goal_2(shorthand(_), _, _, _, _, _) :-
    unexpected(this_file, "shorthand in detect_liveness_in_goal_2").

%-----------------------------------------------------------------------------%

:- pred detect_liveness_in_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::out, live_info::in) is det.

detect_liveness_in_conj([], [], !Liveness, _LiveInfo).
detect_liveness_in_conj([Goal0 | Goals0], [Goal | Goals], !Liveness,
        LiveInfo) :-
    detect_liveness_in_goal(Goal0, Goal, !Liveness, LiveInfo),
    (
        Goal0 = _ - GoalInfo,
        goal_info_get_instmap_delta(GoalInfo, InstmapDelta),
        instmap_delta_is_unreachable(InstmapDelta)
    ->
        % If we continued processing goals, the final value of Liveness
        % would not reflect reality. If we stopped processing goals but
        % included the original Goals0 in Goals, then the liveness
        % fields in Goals would remain uninitialized. Removing goals
        % following a goal that cannot succeed works.
        Goals = []
    ;
        detect_liveness_in_conj(Goals0, Goals, !Liveness, LiveInfo)
    ).

%-----------------------------------------------------------------------------%

:- pred detect_liveness_in_disj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

detect_liveness_in_disj([], [], _Liveness, _NonLocals, _LiveInfo, !Union).
detect_liveness_in_disj([Goal0 | Goals0], [Goal | Goals], Liveness0, NonLocals,
        LiveInfo, !Union) :-
    detect_liveness_in_goal(Goal0, Goal1, Liveness0, Liveness1, LiveInfo),
    set.union(Liveness1, !Union),
    detect_liveness_in_disj(Goals0, Goals, Liveness0, NonLocals, LiveInfo,
        !Union),
    set.intersect(!.Union, NonLocals, NonLocalUnion),
    set.difference(NonLocalUnion, Liveness1, Residue),
    add_liveness_after_goal(Goal1, Residue, Goal).

%-----------------------------------------------------------------------------%

:- pred detect_liveness_in_cases(list(case)::in, list(case)::out,
    set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

detect_liveness_in_cases([], [], _Liveness, _NonLocals, _LiveInfo, !Union).
detect_liveness_in_cases([case(Cons, Goal0) | Goals0],
        [case(Cons, Goal) | Goals], Liveness0, NonLocals, LiveInfo, !Union) :-
    detect_liveness_in_goal(Goal0, Goal1, Liveness0, Liveness1, LiveInfo),
    set.union(Liveness1, !Union),
    detect_liveness_in_cases(Goals0, Goals, Liveness0, NonLocals, LiveInfo,
        !Union),
    set.intersect(!.Union, NonLocals, NonLocalUnion),
    set.difference(NonLocalUnion, Liveness1, Residue),
    add_liveness_after_goal(Goal1, Residue, Goal).

%-----------------------------------------------------------------------------%

:- pred detect_liveness_in_par_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

detect_liveness_in_par_conj([], [], _Liveness, _NonLocals, _LiveInfo, !Union).
detect_liveness_in_par_conj([Goal0 | Goals0], [Goal | Goals], Liveness0,
        NonLocals, LiveInfo, !Union) :-
    detect_liveness_in_goal(Goal0, Goal1, Liveness0, Liveness1, LiveInfo),
    set.union(Liveness1, !Union),
    detect_liveness_in_par_conj(Goals0, Goals, Liveness0, NonLocals,
        LiveInfo, !Union),
    set.intersect(!.Union, NonLocals, NonLocalUnion),
    set.difference(NonLocalUnion, Liveness1, Residue),
    add_liveness_after_goal(Goal1, Residue, Goal).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred detect_deadness_in_goal(hlds_goal::in, hlds_goal::out,
    set(prog_var)::in, set(prog_var)::out, set(prog_var)::in,
    live_info::in) is det.

detect_deadness_in_goal(Goal0 - GoalInfo0, Goal - GoalInfo, !Deadness,
        !.Liveness, LiveInfo) :-
    goal_info_get_pre_deaths(GoalInfo0, PreDeaths0),
    goal_info_get_pre_births(GoalInfo0, PreBirths0),
    goal_info_get_post_deaths(GoalInfo0, PostDeaths0),
    goal_info_get_post_births(GoalInfo0, PostBirths0),

    set.difference(!.Deadness, PostBirths0, !:Deadness),
    set.union(PostDeaths0, !Deadness),

    set.difference(!.Liveness, PreDeaths0, !:Liveness),
    set.union(PreBirths0, !Liveness),

    set.init(Empty),
    ( goal_is_atomic(Goal0) ->
        liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo0,
            _BaseNonLocals, CompletedNonLocals),
        set.intersect(!.Liveness, CompletedNonLocals, LiveNonLocals),
        set.difference(LiveNonLocals, !.Deadness, NewPostDeaths),
        set.union(NewPostDeaths, !Deadness),
        Goal = Goal0
    ;
        NewPostDeaths = Empty,
        detect_deadness_in_goal_2(Goal0, Goal, GoalInfo0,
            !Deadness, !.Liveness, LiveInfo)
    ),
    set.union(PostDeaths0, NewPostDeaths, PostDeaths),
    goal_info_set_post_deaths(PostDeaths, GoalInfo0, GoalInfo),

    set.difference(!.Deadness, PreBirths0, !:Deadness),
    set.union(PreDeaths0, !Deadness).

    % Here we process each of the different sorts of goals.
    %
:- pred detect_deadness_in_goal_2(hlds_goal_expr::in, hlds_goal_expr::out,
    hlds_goal_info::in, set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, live_info::in) is det.

detect_deadness_in_goal_2(conj(ConjType, Goals0), conj(ConjType, Goals),
        GoalInfo, !Deadness, Liveness0, LiveInfo) :-
    (
        ConjType = plain_conj,
        detect_deadness_in_conj(Goals0, Goals, !Deadness, Liveness0, LiveInfo)
    ;
        ConjType = parallel_conj,
        liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
            _, CompletedNonLocals),
        set.init(Union0),
        detect_deadness_in_par_conj(Goals0, Goals, !.Deadness, Liveness0,
            CompletedNonLocals, LiveInfo, Union0, Union,
            _CompletedNonLocalUnion),
        !:Deadness = Union
    ).

detect_deadness_in_goal_2(disj(Goals0), disj(Goals), GoalInfo, !Deadness,
        Liveness0, LiveInfo) :-
    set.init(Union0),
    liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
        _, CompletedNonLocals),
    detect_deadness_in_disj(Goals0, Goals, !.Deadness, Liveness0,
        CompletedNonLocals, LiveInfo, Union0, Union, _),
    !:Deadness = Union.

detect_deadness_in_goal_2(switch(Var, Det, Cases0), switch(Var, Det, Cases),
        GoalInfo, !Deadness, Liveness0, LiveInfo) :-
    set.init(Union0),
    liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
        _, CompletedNonLocals),
    detect_deadness_in_cases(Var, Cases0, Cases, !.Deadness, Liveness0,
        CompletedNonLocals, LiveInfo, Union0, Union, _),
    !:Deadness = Union.

detect_deadness_in_goal_2(not(Goal0), not(Goal), _, !Deadness, Liveness0,
        LiveInfo) :-
    detect_deadness_in_goal(Goal0, Goal, !Deadness, Liveness0, LiveInfo).

detect_deadness_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0),
        if_then_else(Vars, Cond, Then, Else), GoalInfo,
        Deadness0, Deadness, Liveness0, LiveInfo) :-
    update_liveness_goal(Cond0, LiveInfo, Liveness0, LivenessCond),

    detect_deadness_in_goal(Else0, Else1, Deadness0, DeadnessElse,
        Liveness0, LiveInfo),
    detect_deadness_in_goal(Then0, Then, Deadness0, DeadnessThen,
        LivenessCond, LiveInfo),
    detect_deadness_in_goal(Cond0, Cond1, DeadnessThen, DeadnessCond,
        Liveness0, LiveInfo),

    liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
        _, CompletedNonLocals),
    goal_info_get_instmap_delta(GoalInfo, InstmapDelta),
    ( instmap_delta_is_reachable(InstmapDelta) ->
        Cond0 = _ - CondGoalInfo,
        goal_info_get_instmap_delta(CondGoalInfo, CondInstmapDelta),
        Then0 = _ - ThenGoalInfo,
        goal_info_get_instmap_delta(ThenGoalInfo, ThenInstmapDelta),
        Else0 = _ - ElseGoalInfo,
        goal_info_get_instmap_delta(ElseGoalInfo, ElseInstmapDelta),
        (
            instmap_delta_is_reachable(CondInstmapDelta),
            instmap_delta_is_reachable(ThenInstmapDelta)
        ->
            CondThenInstmapReachable = yes
        ;
            CondThenInstmapReachable = no
        ),
        (
            instmap_delta_is_reachable(ElseInstmapDelta)
        ->
            ElseInstmapReachable = yes
        ;
            ElseInstmapReachable = no
        ),
        set.init(Union0),
        union_branch_deadness(DeadnessCond, Deadness0,
            CondThenInstmapReachable, Union0, Union1),
        union_branch_deadness(DeadnessElse, Deadness0,
            ElseInstmapReachable, Union1, Union),
        Deadness = Union,
        set.intersect(Deadness, CompletedNonLocals,
            CompletedNonLocalDeadness),
        add_branch_pre_deaths(DeadnessCond, Deadness0,
            CompletedNonLocalDeadness, CondThenInstmapReachable, Cond1, Cond),
        add_branch_pre_deaths(DeadnessElse, Deadness0,
            CompletedNonLocalDeadness, ElseInstmapReachable, Else1, Else)
    ;
        set.union(DeadnessCond, DeadnessElse, Deadness),
        set.intersect(Deadness, CompletedNonLocals,
            CompletedNonLocalDeadness),
        add_branch_pre_deaths(DeadnessCond, Deadness0,
            CompletedNonLocalDeadness, yes, Cond1, Cond),
        add_branch_pre_deaths(DeadnessElse, Deadness0,
            CompletedNonLocalDeadness, yes, Else1, Else)
    ).

detect_deadness_in_goal_2(scope(Reason, Goal0), scope(Reason, Goal), _,
        !Deadness, Liveness0, LiveInfo) :-
    detect_deadness_in_goal(Goal0, Goal, !Deadness, Liveness0, LiveInfo).

detect_deadness_in_goal_2(generic_call(_,_,_,_), _, _, _, _, _, _) :-
    unexpected(this_file, "higher-order-call in detect_deadness_in_goal_2").

detect_deadness_in_goal_2(call(_,_,_,_,_,_), _, _, _, _, _, _) :-
    unexpected(this_file, "call in detect_deadness_in_goal_2").

detect_deadness_in_goal_2(unify(_,_,_,_,_), _, _, _, _, _, _) :-
    unexpected(this_file, "unify in detect_deadness_in_goal_2").

detect_deadness_in_goal_2(foreign_proc(_, _, _, _, _, _),
        _, _, _, _, _, _) :-
    unexpected(this_file, "foreign_proc in detect_deadness_in_goal_2").

detect_deadness_in_goal_2(shorthand(_), _, _, _, _, _, _) :-
    unexpected(this_file, "shorthand in detect_deadness_in_goal_2").

%-----------------------------------------------------------------------------%

:- pred detect_deadness_in_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::out, set(prog_var)::in,
    live_info::in) is det.

detect_deadness_in_conj([], [], !Deadness, _, _LiveInfo).
detect_deadness_in_conj([Goal0 | Goals0], [Goal | Goals], !Deadness,
        Liveness0, LiveInfo) :-
    Goal0 = _ - GoalInfo,
    goal_info_get_instmap_delta(GoalInfo, InstmapDelta),
    ( instmap_delta_is_unreachable(InstmapDelta) ->
        Goals = Goals0,
        detect_deadness_in_goal(Goal0, Goal, !Deadness, Liveness0, LiveInfo)
    ;
        update_liveness_goal(Goal0, LiveInfo, Liveness0, LivenessGoal),
        detect_deadness_in_conj(Goals0, Goals, !Deadness,
            LivenessGoal, LiveInfo),
        detect_deadness_in_goal(Goal0, Goal, !Deadness, Liveness0, LiveInfo)
    ).

%-----------------------------------------------------------------------------%

:- pred detect_deadness_in_disj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::in, set(prog_var)::in,
    live_info::in, set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::out) is det.

detect_deadness_in_disj([], [], _Deadness0, _Liveness0, CompletedNonLocals,
        _LiveInfo, !Union, CompletedNonLocalUnion) :-
    set.intersect(!.Union, CompletedNonLocals, CompletedNonLocalUnion).
detect_deadness_in_disj([Goal0 | Goals0], [Goal | Goals], Deadness0, Liveness0,
        CompletedNonLocals, LiveInfo, !Union, CompletedNonLocalUnion) :-
    detect_deadness_in_goal(Goal0, Goal1, Deadness0, DeadnessGoal,
        Liveness0, LiveInfo),
    Goal1 = _ - GoalInfo1,
    goal_info_get_instmap_delta(GoalInfo1, InstmapDelta1),
    ( instmap_delta_is_reachable(InstmapDelta1) ->
        InstmapReachable = yes
    ;
        InstmapReachable = no
    ),
    union_branch_deadness(DeadnessGoal, Deadness0, InstmapReachable, !Union),
    detect_deadness_in_disj(Goals0, Goals, Deadness0, Liveness0,
        CompletedNonLocals, LiveInfo, !Union, CompletedNonLocalUnion),
    add_branch_pre_deaths(DeadnessGoal, Deadness0, CompletedNonLocalUnion,
        InstmapReachable, Goal1, Goal).

%-----------------------------------------------------------------------------%

:- pred detect_deadness_in_cases(prog_var::in, list(case)::in, list(case)::out,
    set(prog_var)::in, set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out, set(prog_var)::out) is det.

detect_deadness_in_cases(SwitchVar, [], [], _Deadness0, _Liveness,
        CompletedNonLocals, _LiveInfo, !Union, CompletedNonLocalUnion) :-
    % If the switch variable does not become dead in a case,
    % it must be put in the pre-death set of that case.
    set.insert(!.Union, SwitchVar, !:Union),
    set.intersect(!.Union, CompletedNonLocals, CompletedNonLocalUnion).
detect_deadness_in_cases(SwitchVar, [case(Cons, Goal0) | Goals0],
        [case(Cons, Goal) | Goals], Deadness0, Liveness0,
        CompletedNonLocals, LiveInfo, !Union, CompletedNonLocalUnion) :-
    detect_deadness_in_goal(Goal0, Goal1, Deadness0, DeadnessGoal,
        Liveness0, LiveInfo),
    Goal1 = _ - GoalInfo1,
    goal_info_get_instmap_delta(GoalInfo1, InstmapDelta1),
    ( instmap_delta_is_reachable(InstmapDelta1) ->
        InstmapReachable = yes
    ;
        InstmapReachable = no
    ),
    union_branch_deadness(DeadnessGoal, Deadness0, InstmapReachable, !Union),
    detect_deadness_in_cases(SwitchVar, Goals0, Goals, Deadness0,
        Liveness0, CompletedNonLocals, LiveInfo, !Union,
        CompletedNonLocalUnion),
    add_branch_pre_deaths(DeadnessGoal, Deadness0, CompletedNonLocalUnion,
        InstmapReachable, Goal1, Goal).

%-----------------------------------------------------------------------------%

:- pred detect_deadness_in_par_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out, set(prog_var)::out) is det.

detect_deadness_in_par_conj([], [], _Deadness0, _Liveness0, CompletedNonLocals,
        _LiveInfo, !Union, CompletedNonLocalUnion) :-
    set.intersect(!.Union, CompletedNonLocals, CompletedNonLocalUnion).
detect_deadness_in_par_conj([Goal0 | Goals0], [Goal | Goals], Deadness0,
        Liveness0, CompletedNonLocals, LiveInfo, !Union,
        CompletedNonLocalUnion) :-
    detect_deadness_in_goal(Goal0, Goal1, Deadness0, DeadnessGoal,
        Liveness0, LiveInfo),
    set.union(DeadnessGoal, !Union),
    detect_deadness_in_par_conj(Goals0, Goals, Deadness0,
        Liveness0, CompletedNonLocals, LiveInfo, !Union,
        CompletedNonLocalUnion),
    Goal1 = _ - GoalInfo1,
    goal_info_get_instmap_delta(GoalInfo1, InstmapDelta1),
    ( instmap_delta_is_reachable(InstmapDelta1) ->
        InstmapReachable = yes
    ;
        unexpected(this_file,
            "detect_deadness_in_par_conj: unreachable instmap")
    ),
    add_branch_pre_deaths(DeadnessGoal, Deadness0, CompletedNonLocalUnion,
        InstmapReachable, Goal1, Goal).

%-----------------------------------------------------------------------------%

% The situation that requires the use of these predicates is the following:
%
% ... ( branch1 ; branch2 ), <goal2>, <goal3> ...
%
% where a variable is born in goal2 and dies in goal3, but, because e.g.
% branch1 has determinism erroneous, the same variable is born and dies in
% branch1 as well. (The current mode system permits this, although whether it
% should is another matter.) Since the variable dies in branch1, it is put into
% the pre-death set of branch2 as well.
%
% The problem arises when the death of the variable is delayed by the third
% phase of liveness. The variable is still born in branch1, but is not born in
% branch2, which leads to an inconsistency and a compiler abort.
%
% The solution is to take into account only the non-erroneous branches (the
% branches that have reachable instmaps) when computing the set of variables
% that have been seen in the branched control structure for the first time
% in the backward traversal in the procedure body, and which therefore should
% be put into the pre-death set of the branches which do not mention them.
%
% A further complication is branched control structures that have *no* branches
% whose end points are reachable. (They exist, typically to select the
% appropriate argument to invoke error/1 with.) We treat such control
% structures as if they were erroneous non-branched goals, reducing the
% situation to the one discussed in the previous paragraph. Treating them
% as non-branched goals in this case requires treating all branches as if
% their end points *were* reachable. Any excess deadness acquired by the goal
% in this fashion will be discarded when the erroneous goal is paralleled by
% a non-erroneous branch of an enclosing branched control structure.

:- pred union_branch_deadness(set(prog_var)::in, set(prog_var)::in,
    bool::in, set(prog_var)::in, set(prog_var)::out) is det.

union_branch_deadness(DeadnessGoal, Deadness0, InstmapReachable, !Union) :-
    (
        InstmapReachable = yes,
        set.union(!.Union, DeadnessGoal, !:Union)
    ;
        InstmapReachable = no,
        set.difference(DeadnessGoal, Deadness0, FilteredDeadnessGoal),
        set.union(!.Union, FilteredDeadnessGoal, !:Union)
    ).

:- pred add_branch_pre_deaths(set(prog_var)::in, set(prog_var)::in,
    set(prog_var)::in, bool::in, hlds_goal::in, hlds_goal::out) is det.

add_branch_pre_deaths(DeadnessGoal, Deadness0, CompletedNonLocalUnion,
        InstmapReachable, !Goal) :-
    set.difference(CompletedNonLocalUnion, DeadnessGoal, PreDeaths),
    (
        InstmapReachable = yes,
        add_deadness_before_goal(PreDeaths, !Goal)
    ;
        InstmapReachable = no,
        set.difference(PreDeaths, Deadness0, FilteredPreDeaths),
        add_deadness_before_goal(FilteredPreDeaths, !Goal)
    ).

%-----------------------------------------------------------------------------%

:- pred update_liveness_goal(hlds_goal::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

update_liveness_goal(GoalExpr - GoalInfo, LiveInfo, !Liveness) :-
    goal_info_get_pre_deaths(GoalInfo, PreDeaths),
    goal_info_get_pre_births(GoalInfo, PreBirths),
    goal_info_get_post_deaths(GoalInfo, PostDeaths),
    goal_info_get_post_births(GoalInfo, PostBirths),

    Liveness0 = !.Liveness,
    set.difference(!.Liveness, PreDeaths, !:Liveness),
    set.union(PreBirths, !Liveness),
    update_liveness_expr(GoalExpr, GoalInfo, LiveInfo, !Liveness),
    set.difference(!.Liveness, PostDeaths, !:Liveness),
    set.union(PostBirths, !Liveness),

    set.divide_by_set(Liveness0, !.Liveness, OldLiveness, NewLiveness0),
    liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
        _, CompletedNonLocals),
    set.intersect(NewLiveness0, CompletedNonLocals, NewLiveness),
    set.union(OldLiveness, NewLiveness, !:Liveness).

:- pred update_liveness_expr(hlds_goal_expr::in, hlds_goal_info::in,
    live_info::in, set(prog_var)::in, set(prog_var)::out) is det.

update_liveness_expr(call(_, _, _, _, _, _), _, _, !Liveness).
update_liveness_expr(generic_call(_, _, _, _), _, _, !Liveness).
update_liveness_expr(unify(_, _, _, _, _), _, _, !Liveness).
update_liveness_expr(foreign_proc(_, _, _, _, _, _), _, _, !Liveness).
update_liveness_expr(conj(_ConjType, Goals), _, LiveInfo, !Liveness) :-
    % XXX Do parallel conjunctions need special treatment?
    update_liveness_conj(Goals, LiveInfo, !Liveness).
update_liveness_expr(disj(Goals), _GoalInfo, LiveInfo, !Liveness) :-
    ( find_reachable_goal(Goals, Goal) ->
        update_liveness_goal(Goal, LiveInfo, !Liveness)
    ;
        true
    ).
update_liveness_expr(switch(_, _, Cases), _GoalInfo, LiveInfo, !Liveness) :-
    ( find_reachable_case(Cases, Goal) ->
        update_liveness_goal(Goal, LiveInfo, !Liveness)
    ;
        true
    ).
update_liveness_expr(if_then_else(_, Cond, Then, Else), _GoalInfo, LiveInfo,
        !Liveness) :-
    Else = _ - ElseGoalInfo,
    goal_info_get_instmap_delta(ElseGoalInfo, ElseInstmapDelta),
    Cond = _ - CondGoalInfo,
    goal_info_get_instmap_delta(CondGoalInfo, CondInstmapDelta),
    Then = _ - ThenGoalInfo,
    goal_info_get_instmap_delta(ThenGoalInfo, ThenInstmapDelta),
    (
        instmap_delta_is_reachable(ElseInstmapDelta)
    ->
        update_liveness_goal(Else, LiveInfo, !Liveness)
    ;
        instmap_delta_is_reachable(CondInstmapDelta),
        instmap_delta_is_reachable(ThenInstmapDelta)
    ->
        update_liveness_goal(Cond, LiveInfo, !Liveness),
        update_liveness_goal(Then, LiveInfo, !Liveness)
    ;
        true
    ).
update_liveness_expr(not(Goal), _, LiveInfo, !Liveness) :-
    update_liveness_goal(Goal, LiveInfo, !Liveness).
update_liveness_expr(scope(_, Goal), _, LiveInfo, !Liveness) :-
    update_liveness_goal(Goal, LiveInfo, !Liveness).
update_liveness_expr(shorthand(_), _, _, _, _) :-
    unexpected(this_file, "update_liveness_expr: shorthand").

:- pred update_liveness_conj(list(hlds_goal)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

update_liveness_conj([], _, !Liveness).
update_liveness_conj([Goal | Goals], LiveInfo, !Liveness) :-
    update_liveness_goal(Goal, LiveInfo, !Liveness),
    update_liveness_conj(Goals, LiveInfo, !Liveness).

:- pred find_reachable_goal(list(hlds_goal)::in, hlds_goal::out) is semidet.

find_reachable_goal([Goal | Goals], ReachableGoal) :-
    Goal = _ - GoalInfo,
    goal_info_get_instmap_delta(GoalInfo, InstmapDelta),
    ( instmap_delta_is_reachable(InstmapDelta) ->
        ReachableGoal = Goal
    ;
        find_reachable_goal(Goals, ReachableGoal)
    ).

:- pred find_reachable_case(list(case)::in, hlds_goal::out) is semidet.

find_reachable_case([case(_, Goal) | Cases], ReachableGoal) :-
    Goal = _ - GoalInfo,
    goal_info_get_instmap_delta(GoalInfo, InstmapDelta),
    ( instmap_delta_is_unreachable(InstmapDelta) ->
        find_reachable_case(Cases, ReachableGoal)
    ;
        ReachableGoal = Goal
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% The delay_death pass works by maintaining a set of variables (all named)
% that, according to the deadness pass should have died by now, but which
% are being kept alive so that their values are accessible to the debugger.
% Variables in this DelayedDead set are finally killed when we come to the end
% of the goal in which they were born. This is because if a variable is born in
% one arm of a branched control structure (e.g. a switch), it cannot live
% beyond the control structure, because it is not given a value in other
% branches.
%
% The correctness of this pass with typeinfo_liveness depends on the fact that
% typeinfo and typeclass_info variables are all named. If they weren't, then it
% would be possible for a (named) variable to have its death delayed without
% the type(class)info variable describing part of its type having its death
% delayed as well. In fact, its death will be delayed by at least as much,
% since a variable cannot be live on entry to a branched control structure
% without the type(class)info variables describing its type being live there as
% well.

:- pred delay_death_proc_body(hlds_goal::in, hlds_goal::out, prog_varset::in,
    set(prog_var)::in) is det.

delay_death_proc_body(Goal0, Goal, VarSet, BornVars0) :-
    delay_death_goal(Goal0, Goal1, BornVars0, _, set.init, DelayedDead,
        VarSet),
    Goal1 = GoalExpr - GoalInfo1,
    goal_info_get_post_deaths(GoalInfo1, PostDeaths1),
    set.union(PostDeaths1, DelayedDead, PostDeaths),
    goal_info_set_post_deaths(PostDeaths, GoalInfo1, GoalInfo),
    Goal = GoalExpr - GoalInfo.

:- pred delay_death_goal(hlds_goal::in, hlds_goal::out,
    set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, set(prog_var)::out, prog_varset::in) is det.

delay_death_goal(GoalExpr0 - GoalInfo0, GoalExpr - GoalInfo,
        !BornVars, !DelayedDead, VarSet) :-
    goal_info_get_pre_births(GoalInfo0, PreBirths),
    goal_info_get_pre_deaths(GoalInfo0, PreDeaths0),
    BornVars0 = !.BornVars,

    set.union(PreBirths, !BornVars),
    set.divide(var_is_named(VarSet), PreDeaths0,
        PreDelayedDead, UnnamedPreDeaths),
    set.union(PreDelayedDead, !DelayedDead),
    goal_info_set_pre_deaths(UnnamedPreDeaths, GoalInfo0, GoalInfo1),

    delay_death_goal_expr(GoalExpr0, GoalExpr, GoalInfo1, GoalInfo2,
        !BornVars, !DelayedDead, VarSet),

    goal_info_get_post_births(GoalInfo2, PostBirths),
    goal_info_get_post_deaths(GoalInfo2, PostDeaths2),

    set.union(PostBirths, !BornVars),
    set.divide(var_is_named(VarSet), PostDeaths2,
        PostDelayedDead, UnnamedPostDeaths),
    set.union(PostDelayedDead, !DelayedDead),
    set.divide_by_set(BornVars0, !.DelayedDead, !:DelayedDead, ToBeKilled),
    set.union(UnnamedPostDeaths, ToBeKilled, PostDeaths),
    goal_info_set_post_deaths(PostDeaths, GoalInfo2, GoalInfo).

:- pred var_is_named(prog_varset::in, prog_var::in) is semidet.

var_is_named(VarSet, Var) :-
    varset.search_name(VarSet, Var, _).

:- pred delay_death_goal_expr(hlds_goal_expr::in, hlds_goal_expr::out,
    hlds_goal_info::in, hlds_goal_info::out,
    set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, set(prog_var)::out, prog_varset::in) is det.

delay_death_goal_expr(!GoalExpr, !GoalInfo, !BornVars, !DelayedDead, VarSet) :-
    (
        !.GoalExpr = call(_, _, _, _, _, _)
    ;
        !.GoalExpr = generic_call(_, _, _, _)
    ;
        !.GoalExpr = unify(_, _, _, _, _)
    ;
        !.GoalExpr = foreign_proc(_, _, _, _, _, _)
    ;
        !.GoalExpr = conj(ConjType, Goals0),
        (
            ConjType = plain_conj,
            delay_death_conj(Goals0, Goals, !BornVars, !DelayedDead, VarSet)
        ;
            ConjType = parallel_conj,
            delay_death_par_conj(Goals0, Goals, !BornVars, !DelayedDead,
                VarSet)
        ),
        !:GoalExpr = conj(ConjType, Goals)
    ;
        !.GoalExpr = disj(Goals0),
        delay_death_disj(Goals0, GoalDeaths, !.BornVars, !.DelayedDead,
            VarSet, MaybeBornVarsDelayedDead),
        (
            MaybeBornVarsDelayedDead = yes(!:BornVars - !:DelayedDead),
            Goals = list.map(kill_excess_delayed_dead_goal(!.DelayedDead),
                GoalDeaths),
            !:GoalExpr = disj(Goals)
        ;
            MaybeBornVarsDelayedDead = no
            % Empty disjunctions represent the goal `fail',
            % so we process them as if they were primitive goals.
        )
    ;
        !.GoalExpr = switch(Var, CanFail, Cases0),
        delay_death_cases(Cases0, CaseDeaths, !.BornVars, !.DelayedDead,
            VarSet, MaybeBornVarsDelayedDead),
        (
            MaybeBornVarsDelayedDead = yes(!:BornVars - !:DelayedDead),
            Cases = list.map(kill_excess_delayed_dead_case(!.DelayedDead),
                CaseDeaths),
            !:GoalExpr = switch(Var, CanFail, Cases)
        ;
            MaybeBornVarsDelayedDead = no,
            unexpected(this_file, "delay_death_goal_expr: empty switch")
        )
    ;
        !.GoalExpr = not(Goal0),
        delay_death_goal(Goal0, Goal, !.BornVars, _, !DelayedDead, VarSet),
        !:GoalExpr = not(Goal)
    ;
        !.GoalExpr = if_then_else(QuantVars, Cond0, Then0, Else0),
        BornVars0 = !.BornVars,
        DelayedDead0 = !.DelayedDead,
        delay_death_goal(Cond0, Cond, BornVars0, BornVarsCond,
            DelayedDead0, DelayedDeadCond, VarSet),
        delay_death_goal(Then0, Then1, BornVarsCond, BornVarsThen,
            DelayedDeadCond, DelayedDeadThen, VarSet),
        delay_death_goal(Else0, Else1, BornVars0, BornVarsElse,
            DelayedDead0, DelayedDeadElse, VarSet),
        set.intersect(BornVarsThen, BornVarsElse, BornVars),
        set.intersect(DelayedDeadThen, DelayedDeadElse, DelayedDead),
        Then = kill_excess_delayed_dead_goal(DelayedDead,
            Then1 - DelayedDeadThen),
        !:BornVars = BornVars,
        !:DelayedDead = DelayedDead,
        Else = kill_excess_delayed_dead_goal(DelayedDead,
            Else1 - DelayedDeadElse),
        !:GoalExpr = if_then_else(QuantVars, Cond, Then, Else)
    ;
        !.GoalExpr = scope(Reason, Goal0),
        delay_death_goal(Goal0, Goal, !.BornVars, _, !DelayedDead, VarSet),
        !:GoalExpr = scope(Reason, Goal)
    ;
        !.GoalExpr = shorthand(_),
        unexpected(this_file, "delay_death_goal_expr: shorthand")
    ).

:- pred delay_death_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, set(prog_var)::out, prog_varset::in) is det.

delay_death_conj([], [], !BornVars, !DelayedDead, _).
delay_death_conj([Goal0 | Goals0], [Goal | Goals], !BornVars, !DelayedDead,
        VarSet) :-
    delay_death_goal(Goal0, Goal, !BornVars, !DelayedDead, VarSet),
    delay_death_conj(Goals0, Goals, !BornVars, !DelayedDead, VarSet).

:- pred delay_death_par_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, set(prog_var)::out, prog_varset::in) is det.

delay_death_par_conj([], [], !BornVars, !DelayedDead, _).
delay_death_par_conj([Goal0 | Goals0], [Goal | Goals],
        BornVars0, BornVars, DelayedDead0, DelayedDead, VarSet) :-
    delay_death_goal(Goal0, Goal, BornVars0, BornVarsGoal,
        DelayedDead0, DelayedDeadGoal, VarSet),
    delay_death_par_conj(Goals0, Goals, BornVars0, BornVarsGoals,
        DelayedDead0, DelayedDeadGoals, VarSet),
    set.union(BornVarsGoal, BornVarsGoals, BornVars),
    set.union(DelayedDeadGoal, DelayedDeadGoals, DelayedDead).

:- pred delay_death_disj(list(hlds_goal)::in,
    assoc_list(hlds_goal, set(prog_var))::out,
    set(prog_var)::in, set(prog_var)::in, prog_varset::in,
    maybe(pair(set(prog_var)))::out) is det.

delay_death_disj([], [], _, _, _, no).
delay_death_disj([Goal0 | Goals0], [Goal - DelayedDeadGoal | Goals],
        BornVars0, DelayedDead0, VarSet, yes(BornVars - DelayedDead)) :-
    delay_death_goal(Goal0, Goal, BornVars0, BornVarsGoal,
        DelayedDead0, DelayedDeadGoal, VarSet),
    delay_death_disj(Goals0, Goals, BornVars0, DelayedDead0, VarSet,
        MaybeBornVarsDelayedDead),
    (
        MaybeBornVarsDelayedDead = yes(BornVarsGoals - DelayedDeadGoals),
        set.intersect(BornVarsGoal, BornVarsGoals, BornVars),
        set.intersect(DelayedDeadGoal, DelayedDeadGoals, DelayedDead)
    ;
        MaybeBornVarsDelayedDead = no,
        BornVars = BornVarsGoal,
        DelayedDead = DelayedDeadGoal
    ).

:- pred delay_death_cases(list(case)::in, assoc_list(case, set(prog_var))::out,
    set(prog_var)::in, set(prog_var)::in, prog_varset::in,
    maybe(pair(set(prog_var)))::out) is det.

delay_death_cases([], [], _, _, _, no).
delay_death_cases([case(ConsId, Goal0) | Cases0],
        [case(ConsId, Goal) - DelayedDeadGoal | Cases],
        BornVars0, DelayedDead0, VarSet, yes(BornVars - DelayedDead)) :-
    delay_death_goal(Goal0, Goal, BornVars0, BornVarsGoal,
        DelayedDead0, DelayedDeadGoal, VarSet),
    delay_death_cases(Cases0, Cases, BornVars0, DelayedDead0, VarSet,
        MaybeBornVarsDelayedDead),
    (
        MaybeBornVarsDelayedDead = yes(BornVarsCases - DelayedDeadCases),
        set.intersect(BornVarsGoal, BornVarsCases, BornVars),
        set.intersect(DelayedDeadGoal, DelayedDeadCases, DelayedDead)
    ;
        MaybeBornVarsDelayedDead = no,
        BornVars = BornVarsGoal,
        DelayedDead = DelayedDeadGoal
    ).

% The kill_excess_delayed_dead_* functions are called on each branch of a
% branched control structure to make sure that all branches kill the same
% set of variables.

:- func kill_excess_delayed_dead_goal(set(prog_var),
    pair(hlds_goal, set(prog_var))) = hlds_goal.

kill_excess_delayed_dead_goal(FinalDelayedDead, Goal0 - DelayedDead0) = Goal :-
    set.difference(DelayedDead0, FinalDelayedDead, ToBeKilled),
    Goal0 = GoalExpr - GoalInfo0,
    goal_info_get_post_deaths(GoalInfo0, PostDeath0),
    set.union(PostDeath0, ToBeKilled, PostDeath),
    goal_info_set_post_deaths(PostDeath, GoalInfo0, GoalInfo),
    Goal = GoalExpr - GoalInfo.

:- func kill_excess_delayed_dead_case(set(prog_var),
    pair(case, set(prog_var))) = case.

kill_excess_delayed_dead_case(FinalDelayedDead,
        case(ConsId, Goal0) - DelayedDead0) = case(ConsId, Goal) :-
    set.difference(DelayedDead0, FinalDelayedDead, ToBeKilled),
    Goal0 = GoalExpr - GoalInfo0,
    goal_info_get_post_deaths(GoalInfo0, PostDeath0),
    set.union(PostDeath0, ToBeKilled, PostDeath),
    goal_info_set_post_deaths(PostDeath, GoalInfo0, GoalInfo),
    Goal = GoalExpr - GoalInfo.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred detect_resume_points_in_goal(hlds_goal::in, hlds_goal::out,
    set(prog_var)::in, set(prog_var)::out, live_info::in,
    set(prog_var)::in) is det.

detect_resume_points_in_goal(Goal0 - GoalInfo0, Goal - GoalInfo0,
        !Liveness, LiveInfo, ResumeVars0) :-
    goal_info_get_pre_deaths(GoalInfo0, PreDeaths0),
    goal_info_get_pre_births(GoalInfo0, PreBirths0),
    goal_info_get_post_deaths(GoalInfo0, PostDeaths0),
    goal_info_get_post_births(GoalInfo0, PostBirths0),

    set.difference(!.Liveness, PreDeaths0, !:Liveness),
    set.union(PreBirths0, !Liveness),

    detect_resume_points_in_goal_2(Goal0, Goal, !Liveness, GoalInfo0,
        LiveInfo, ResumeVars0),

    set.difference(!.Liveness, PostDeaths0, !:Liveness),
    set.union(PostBirths0, !Liveness).

:- pred detect_resume_points_in_goal_2(hlds_goal_expr::in, hlds_goal_expr::out,
    set(prog_var)::in, set(prog_var)::out, hlds_goal_info::in,
    live_info::in, set(prog_var)::in) is det.

detect_resume_points_in_goal_2(conj(ConjType, Goals0), conj(ConjType, Goals),
        !Liveness, _, LiveInfo, ResumeVars0) :-
    (
        ConjType = plain_conj,
        detect_resume_points_in_conj(Goals0, Goals, !Liveness,
            LiveInfo, ResumeVars0)
    ;
        ConjType = parallel_conj,
        detect_resume_points_in_par_conj(Goals0, Goals, !Liveness,
            LiveInfo, ResumeVars0)
    ).

detect_resume_points_in_goal_2(disj(Goals0), disj(Goals), !Liveness, GoalInfo,
        LiveInfo, ResumeVars0) :-
    goal_info_get_code_model(GoalInfo, CodeModel),
    ( CodeModel = model_non ->
        detect_resume_points_in_non_disj(Goals0, Goals, !Liveness,
            LiveInfo, ResumeVars0, _)
    ;
        detect_resume_points_in_pruned_disj(Goals0, Goals, !Liveness,
            LiveInfo, ResumeVars0, _)
    ).

detect_resume_points_in_goal_2(switch(Var, CF, Cases0), switch(Var, CF, Cases),
        !Liveness, _, LiveInfo, ResumeVars0) :-
    detect_resume_points_in_cases(Cases0, Cases, !Liveness,
        LiveInfo, ResumeVars0).

detect_resume_points_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0),
        if_then_else(Vars, Cond, Then, Else), Liveness0, LivenessThen,
        GoalInfo0, LiveInfo, ResumeVars0) :-

    % Compute the set of variables that may be needed at the start
    % of the else part and attach this set to the condition.
    Else0 = _ElseExpr0 - ElseInfo0,
    goal_info_get_pre_deaths(ElseInfo0, ElsePreDeath0),
    set.difference(Liveness0, ElsePreDeath0, CondResumeVars0),
    liveness.maybe_complete_with_typeinfos(LiveInfo, CondResumeVars0,
        CondResumeVars1),
    % ResumeVars0 should already have been completed.
    set.union(CondResumeVars1, ResumeVars0, CondResumeVars),

    detect_resume_points_in_goal(Cond0, Cond1, Liveness0, LivenessCond,
        LiveInfo, CondResumeVars),
    detect_resume_points_in_goal(Then0, Then, LivenessCond, LivenessThen,
        LiveInfo, ResumeVars0),
    detect_resume_points_in_goal(Else0, Else, Liveness0, LivenessElse,
        LiveInfo, ResumeVars0),

    % Figure out which entry labels we need at the resumption point.
    % By minimizing the number of labels we use, we also minimize
    % the amount of data movement code we emit between such labels.
    (
        cannot_stack_flush(Cond1),
        goal_info_get_code_model(GoalInfo0, CodeModel),
        CodeModel \= model_non
    ->
        CondResumeLocs = orig_only
    ;
        set.empty(CondResumeVars)
    ->
        % There is no difference between orig_only and stack_only when
        % there are no resume variables, but some parts of code_info
        % insist on a stack label if e.g. the condition contains
        % commits, which is why we choose to use stack_only here.
        CondResumeLocs = stack_only
    ;
        cannot_fail_before_stack_flush(Cond1)
    ->
        CondResumeLocs = stack_only
    ;
        CondResumeLocs = stack_and_orig
    ),

    % Attach the set of variables needed after the condition
    % as the resume point set of the condition.
    CondResume = resume_point(CondResumeVars, CondResumeLocs),
    goal_set_resume_point(CondResume, Cond1, Cond),

    require_equal(LivenessThen, LivenessElse, "if-then-else", LiveInfo).

detect_resume_points_in_goal_2(scope(Reason, Goal0), scope(Reason, Goal),
        !Liveness, _, LiveInfo, ResumeVars0) :-
    detect_resume_points_in_goal(Goal0, Goal, !Liveness,
        LiveInfo, ResumeVars0).

detect_resume_points_in_goal_2(not(Goal0), not(Goal), Liveness0, Liveness, _,
        LiveInfo, ResumeVars0) :-
    detect_resume_points_in_goal(Goal0, _, Liveness0, Liveness,
        LiveInfo, ResumeVars0),
    liveness.maybe_complete_with_typeinfos(LiveInfo, Liveness,
        CompletedLiveness),
    % ResumeVars0 should already have been completed.
    set.union(CompletedLiveness, ResumeVars0, ResumeVars1),
    detect_resume_points_in_goal(Goal0, Goal1, Liveness0, _Liveness,
        LiveInfo, ResumeVars1),

    % Figure out which entry labels we need at the resumption point.
    % By minimizing the number of labels we use, we also minimize
    % the amount of data movement code we emit between such labels.
    ( cannot_stack_flush(Goal1) ->
        ResumeLocs = orig_only
    ; cannot_fail_before_stack_flush(Goal1) ->
        ResumeLocs = stack_only
    ;
        ResumeLocs = stack_and_orig
    ),

    % Attach the set of variables alive after the negation
    % as the resume point set of the negated goal.
    Resume = resume_point(ResumeVars1, ResumeLocs),
    goal_set_resume_point(Resume, Goal1, Goal).

detect_resume_points_in_goal_2(Goal @ generic_call(_, _, _, _), Goal,
        !Liveness, _, _, _).

detect_resume_points_in_goal_2(Goal @ call(_, _, _, _, _, _), Goal,
        !Liveness, _, _, _).

detect_resume_points_in_goal_2(Goal @ unify(_, _, _, _, _), Goal,
        !Liveness, _, _, _).

detect_resume_points_in_goal_2(Goal @ foreign_proc(_, _, _, _, _, _), Goal,
        !Liveness, _, _, _).

detect_resume_points_in_goal_2(shorthand(_), _, _, _, _, _, _) :-
    % These should have been expanded out by now.
    unexpected(this_file,
        "detect_resume_points_in_goal_2: unexpected shorthand").

:- pred detect_resume_points_in_conj(list(hlds_goal)::in, list(hlds_goal)::out,
    set(prog_var)::in, set(prog_var)::out,
    live_info::in, set(prog_var)::in) is det.

detect_resume_points_in_conj([], [], !Liveness, _, _).
detect_resume_points_in_conj([Goal0 | Goals0], [Goal | Goals],
        !Liveness, LiveInfo, ResumeVars0) :-
    detect_resume_points_in_goal(Goal0, Goal, !Liveness,
        LiveInfo, ResumeVars0),
    detect_resume_points_in_conj(Goals0, Goals, !Liveness,
        LiveInfo, ResumeVars0).

    % There are only two differences in the handling of pruned disjs versus
    % nondet disjs. First, for nondet disjunctions we always generate code
    % for all disjuncts, whereas for pruned disjunctions we stop generating
    % code after the first cannot_fail disjunct. Second, an empty pruned
    % disjunction is legal, while an empty nondet disjunction isn't.
    %
    % For both kinds of disjunctions, the resume points to be attached to
    % the non-last disjuncts must be completed with the required typeinfos
    % if --typeinfo-liveness is set. ResumeVars0 should already be so
    % completed, so we need only complete the sets added here. We therefore
    % perform this completion when we return the set of variables needed by
    % the last disjunct, and when we add to this set the set of variables
    % needed by a non-last disjunct.
    %
:- pred detect_resume_points_in_non_disj(list(hlds_goal)::in,
    list(hlds_goal)::out, set(prog_var)::in, set(prog_var)::out,
    live_info::in, set(prog_var)::in, set(prog_var)::out) is det.

detect_resume_points_in_non_disj([], _, _, _, _, _, _) :-
    unexpected(this_file, "empty nondet disjunction").
detect_resume_points_in_non_disj([Goal0 | Goals0], [Goal | Goals],
        Liveness0, Liveness, LiveInfo, ResumeVars0, Needed) :-
    (
        % If there are any more disjuncts, then this disjunct
        % establishes a resumption point.
        Goals0 = [_ | _]
    ->
        detect_resume_points_in_non_disj(Goals0, Goals,
            Liveness0, LivenessRest, LiveInfo,
            ResumeVars0, NeededRest),
        detect_resume_points_in_non_last_disjunct(Goal0, Goal, no,
            Liveness0, LivenessRest, LiveInfo, ResumeVars0,
            Liveness, NeededRest, Needed)
    ;
        detect_resume_points_in_last_disjunct(Goal0, Goal,
            Liveness0, Liveness, LiveInfo, ResumeVars0, Needed),
        Goals = Goals0
    ).

:- pred detect_resume_points_in_pruned_disj(list(hlds_goal)::in,
    list(hlds_goal)::out, set(prog_var)::in, set(prog_var)::out,
    live_info::in, set(prog_var)::in, set(prog_var)::out) is det.

detect_resume_points_in_pruned_disj([], [], !Liveness, _, _, Needed) :-
    set.init(Needed).
detect_resume_points_in_pruned_disj([Goal0 | Goals0], [Goal | Goals],
        Liveness0, Liveness, LiveInfo, ResumeVars0, Needed) :-
    Goal0 = _ - GoalInfo0,
    goal_info_get_determinism(GoalInfo0, Detism0),
    determinism_components(Detism0, CanFail0, _),
    (
        % This disjunct establishes a resumption point only if
        % there are more disjuncts *and* this one can fail.
        % If there are more disjuncts but this one can't fail,
        % then the code generator will ignore any later disjuncts,
        % so this one will be effectively the last.
        CanFail0 = can_fail,
        Goals0 = [_ | _]
    ->
        detect_resume_points_in_pruned_disj(Goals0, Goals,
            Liveness0, LivenessRest, LiveInfo, ResumeVars0, NeededRest),
        detect_resume_points_in_non_last_disjunct(Goal0, Goal, yes,
            Liveness0, LivenessRest, LiveInfo, ResumeVars0,
            Liveness, NeededRest, Needed)
    ;
        detect_resume_points_in_last_disjunct(Goal0, Goal,
            Liveness0, Liveness, LiveInfo, ResumeVars0, Needed),
        Goals = Goals0
    ).

:- pred detect_resume_points_in_non_last_disjunct(hlds_goal::in,hlds_goal::out,
    bool::in, set(prog_var)::in, set(prog_var)::in, live_info::in,
    set(prog_var)::in, set(prog_var)::out,
    set(prog_var)::in, set(prog_var)::out) is det.

detect_resume_points_in_non_last_disjunct(Goal0, Goal, MayUseOrigOnly,
        Liveness0, LivenessRest, LiveInfo, ResumeVars0,
        Liveness, NeededRest, Needed) :-
    % We must save a variable across this disjunct if it is needed
    % in a later disjunct or in an enclosing resume point
    set.union(NeededRest, ResumeVars0, ResumeVars1),
    detect_resume_points_in_goal(Goal0, Goal1, Liveness0, Liveness,
        LiveInfo, ResumeVars1),

    % Figure out which entry labels we need at the resumption point.
    % By minimizing the number of labels we use, we also minimize
    % the amount of data movement code we emit between such labels.
    (
        MayUseOrigOnly = yes,
        cannot_stack_flush(Goal1)
    ->
        ResumeLocs = orig_only
    ;
        cannot_fail_before_stack_flush(Goal1)
    ->
        ResumeLocs = stack_only
    ;
        ResumeLocs = stack_and_orig
    ),

    % Attach the set of variables needed in the following disjuncts
    % as the resume point set of this disjunct.
    Resume = resume_point(ResumeVars1, ResumeLocs),
    goal_set_resume_point(Resume, Goal1, Goal),

    Goal = _ - GoalInfo,
    goal_info_get_pre_deaths(GoalInfo, PreDeaths),
    set.difference(Liveness0, PreDeaths, NeededFirst),
    liveness.maybe_complete_with_typeinfos(LiveInfo, NeededFirst,
        CompletedNeededFirst),
    % NeededRest has already been completed.
    set.union(CompletedNeededFirst, NeededRest, Needed),

    require_equal(Liveness, LivenessRest, "disjunction", LiveInfo).

:- pred detect_resume_points_in_last_disjunct(hlds_goal::in, hlds_goal::out,
    set(prog_var)::in, set(prog_var)::out, live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

detect_resume_points_in_last_disjunct(Goal0, Goal, Liveness0, Liveness,
        LiveInfo, ResumeVars0, CompletedNeeded) :-
    detect_resume_points_in_goal(Goal0, Goal, Liveness0, Liveness,
        LiveInfo, ResumeVars0),
    Goal = _ - GoalInfo,
    goal_info_get_pre_deaths(GoalInfo, PreDeaths),
    set.difference(Liveness0, PreDeaths, Needed),
    liveness.maybe_complete_with_typeinfos(LiveInfo, Needed, CompletedNeeded).

:- pred detect_resume_points_in_cases(list(case)::in, list(case)::out,
    set(prog_var)::in, set(prog_var)::out,
    live_info::in, set(prog_var)::in) is det.

detect_resume_points_in_cases([], [], !Liveness, _, _).
detect_resume_points_in_cases([case(ConsId, Goal0) | Cases0],
        [case(ConsId, Goal) | Cases], Liveness0, LivenessFirst,
        LiveInfo, ResumeVars0) :-
    detect_resume_points_in_goal(Goal0, Goal, Liveness0, LivenessFirst,
        LiveInfo, ResumeVars0),
    (
        Cases0 = [_ | _],
        detect_resume_points_in_cases(Cases0, Cases,
            Liveness0, LivenessRest, LiveInfo, ResumeVars0),
        require_equal(LivenessFirst, LivenessRest, "switch", LiveInfo)
    ;
        Cases0 = [],
        Cases = Cases0
    ).

:- pred detect_resume_points_in_par_conj(list(hlds_goal)::in,
    list(hlds_goal)::out, set(prog_var)::in, set(prog_var)::out,
    live_info::in, set(prog_var)::in) is det.

detect_resume_points_in_par_conj([], [], !Liveness, _, _).
detect_resume_points_in_par_conj([Goal0 | Goals0], [Goal | Goals],
        Liveness0, Liveness, LiveInfo, ResumeVars0) :-
    detect_resume_points_in_goal(Goal0, Goal, Liveness0, Liveness,
        LiveInfo, ResumeVars0),
    detect_resume_points_in_par_conj(Goals0, Goals,
        Liveness0, _LivenessRest, LiveInfo, ResumeVars0).

:- pred require_equal(set(prog_var)::in, set(prog_var)::in, string::in,
    live_info::in) is det.

require_equal(LivenessFirst, LivenessRest, GoalType, LiveInfo) :-
    ( set.equal(LivenessFirst, LivenessRest) ->
        true
    ;
        VarSet = LiveInfo ^ varset,
        set.to_sorted_list(LivenessFirst, FirstVarsList),
        set.to_sorted_list(LivenessRest, RestVarsList),
        list.map(varset.lookup_name(VarSet), FirstVarsList, FirstVarNames),
        list.map(varset.lookup_name(VarSet), RestVarsList, RestVarNames),
        Pad = (pred(S0::in, S::out) is det :- string.append(S0, " ", S)),
        list.map(Pad, FirstVarNames, PaddedFirstNames),
        list.map(Pad, RestVarNames, PaddedRestNames),
        string.append_list(PaddedFirstNames, FirstNames),
        string.append_list(PaddedRestNames, RestNames),
        Msg = "branches of " ++ GoalType ++ " disagree on liveness\n" ++
            "First: " ++ FirstNames ++ "\n" ++ "Rest:  " ++ RestNames ++ "\n",
        unexpected(this_file, Msg)
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

initial_liveness(ProcInfo, PredId, ModuleInfo, !:Liveness) :-
    proc_info_get_headvars(ProcInfo, Vars),
    proc_info_get_argmodes(ProcInfo, Modes),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    map.apply_to_list(Vars, VarTypes, Types),
    set.init(!:Liveness),
    ( initial_liveness_2(Vars, Modes, Types, ModuleInfo, !Liveness) ->
        true
    ;
        unexpected(this_file, "initial_liveness: list length mismatch")
    ),
    %
    % If a variable is unused in the goal, it shouldn't be in the initial
    % liveness. (If we allowed it to start live, it wouldn't ever become dead,
    % because it would have to be used to be killed).  So we intersect the
    % headvars with the non-locals and (if doing typeinfo liveness calculation)
    % their typeinfo vars.
    %
    module_info_get_globals(ModuleInfo, Globals),
    proc_info_get_goal(ProcInfo, _Goal - GoalInfo),
    goal_info_get_code_gen_nonlocals(GoalInfo, NonLocals0),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    proc_info_get_rtti_varmaps(ProcInfo, RttiVarMaps),
    body_should_use_typeinfo_liveness(PredInfo, Globals, TypeinfoLiveness),
    maybe_complete_with_typeinfo_vars(NonLocals0, TypeinfoLiveness, VarTypes,
        RttiVarMaps, NonLocals),
    set.intersect(!.Liveness, NonLocals, !:Liveness).

:- pred initial_liveness_2(list(prog_var)::in, list(mer_mode)::in,
    list(mer_type)::in, module_info::in,
    set(prog_var)::in, set(prog_var)::out) is semidet.

initial_liveness_2([], [], [], _ModuleInfo, !Liveness).
initial_liveness_2([V | Vs], [M | Ms], [T | Ts], ModuleInfo, !Liveness) :-
    ( mode_to_arg_mode(ModuleInfo, M, T, top_in) ->
        svset.insert(V, !Liveness)
    ;
        true
    ),
    initial_liveness_2(Vs, Ms, Ts, ModuleInfo, !Liveness).

%-----------------------------------------------------------------------------%

    % Return the set of variables whose values are needed beyond the end
    % of the procedure (i.e. its output arguments).
    %
:- pred initial_deadness(proc_info::in, live_info::in, module_info::in,
    set(prog_var)::out) is det.

initial_deadness(ProcInfo, LiveInfo, ModuleInfo, Deadness) :-
    % The output arguments are all in the initial deadness.
    arg_info.partition_proc_args(ProcInfo, ModuleInfo, _, Deadness0, _),

    % If doing typeinfo liveness, the corresponding typeinfos need to be added
    % to these.
    proc_info_get_vartypes(ProcInfo, VarTypes),
    proc_info_get_rtti_varmaps(ProcInfo, RttiVarMaps),
    maybe_complete_with_typeinfo_vars(Deadness0, LiveInfo ^ typeinfo_liveness,
        VarTypes, RttiVarMaps, Deadness).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred add_liveness_after_goal(hlds_goal::in, set(prog_var)::in,
    hlds_goal::out) is det.

add_liveness_after_goal(Goal - GoalInfo0, Residue, Goal - GoalInfo) :-
    goal_info_get_post_births(GoalInfo0, PostBirths0),
    set.union(PostBirths0, Residue, PostBirths),
    goal_info_set_post_births(PostBirths, GoalInfo0, GoalInfo).

:- pred add_deadness_before_goal(set(prog_var)::in,
    hlds_goal::in, hlds_goal::out) is det.

add_deadness_before_goal(Residue, Goal - GoalInfo0, Goal - GoalInfo) :-
    goal_info_get_pre_deaths(GoalInfo0, PreDeaths0),
    set.union(PreDeaths0, Residue, PreDeaths),
    goal_info_set_pre_deaths(PreDeaths, GoalInfo0, GoalInfo).

:- pred add_deadness_after_goal(set(prog_var)::in,
    hlds_goal::in, hlds_goal::out) is det.

add_deadness_after_goal(Residue, Goal - GoalInfo0, Goal - GoalInfo) :-
    goal_info_get_post_deaths(GoalInfo0, PostDeaths0),
    set.union(PostDeaths0, Residue, PostDeaths),
    goal_info_set_post_deaths(PostDeaths, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % Given a list of variables and an instmap delta, determine which
    % of those variables have a value given to them (i.e. they are bound
    % or aliased; in the latter case the "value" is the location they
    % should be stored in), and insert them into the accumulated set
    % of value-given vars.
    %
    % We don't handle the aliasing part yet.
    %
:- pred find_value_giving_occurrences(list(prog_var)::in, live_info::in,
    instmap_delta::in, set(prog_var)::in, set(prog_var)::out) is det.

find_value_giving_occurrences([], _, _, !ValueVars).
find_value_giving_occurrences([Var | Vars], LiveInfo, InstMapDelta,
        !ValueVars) :-
    VarTypes = LiveInfo ^ vartypes,
    map.lookup(VarTypes, Var, Type),
    (
        instmap_delta_search_var(InstMapDelta, Var, Inst),
        ModuleInfo = LiveInfo ^ module_info,
        mode_to_arg_mode(ModuleInfo, (free -> Inst), Type, top_out)
    ->
        svset.insert(Var, !ValueVars)
    ;
        true
    ),
    find_value_giving_occurrences(Vars, LiveInfo, InstMapDelta,
        !ValueVars).

%-----------------------------------------------------------------------------%

    % Get the nonlocals, and, if doing typeinfo liveness, add the
    % typeinfo vars for the nonlocals.

:- pred liveness.get_nonlocals_and_typeinfos(live_info::in,
    hlds_goal_info::in, set(prog_var)::out, set(prog_var)::out) is det.

liveness.get_nonlocals_and_typeinfos(LiveInfo, GoalInfo,
        NonLocals, CompletedNonLocals) :-
    goal_info_get_code_gen_nonlocals(GoalInfo, NonLocals),
    liveness.maybe_complete_with_typeinfos(LiveInfo,
        NonLocals, CompletedNonLocals).

:- pred liveness.maybe_complete_with_typeinfos(live_info::in,
    set(prog_var)::in, set(prog_var)::out) is det.

liveness.maybe_complete_with_typeinfos(LiveInfo, Vars0, Vars) :-
    maybe_complete_with_typeinfo_vars(Vars0, LiveInfo ^ typeinfo_liveness,
        LiveInfo ^ vartypes, LiveInfo ^ rtti_varmaps, Vars).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type live_info
    --->    live_info(
                module_info         ::  module_info,
                typeinfo_liveness   ::  bool,
                vartypes            ::  vartypes,
                rtti_varmaps        ::  rtti_varmaps,
                varset              ::  prog_varset
            ).

:- pred live_info_init(module_info::in, bool::in, vartypes::in,
    rtti_varmaps::in, prog_varset::in, live_info::out) is det.

live_info_init(ModuleInfo, TypeInfoLiveness, VarTypes, RttiVarMaps, VarSet,
    live_info(ModuleInfo, TypeInfoLiveness, VarTypes, RttiVarMaps, VarSet)).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "liveness.m".

%-----------------------------------------------------------------------------%
:- end_module liveness.
%-----------------------------------------------------------------------------%
