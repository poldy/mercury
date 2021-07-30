%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1996-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: deps_map.m.
%
% This module contains a data structure for recording module dependencies
% and its access predicates. The module_deps_graph module contains another
% data structure, used for similar purposes, that is built on top of this one.
% XXX Document the exact relationship between the two.
%
%---------------------------------------------------------------------------%

:- module parse_tree.deps_map.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.error_util.
:- import_module parse_tree.file_names.
:- import_module parse_tree.module_imports.

:- import_module io.
:- import_module list.
:- import_module map.

% This is the data structure we use to record the dependencies.
% We keep a map from module name to information about the module.

:- type deps_map == map(module_name, deps).
:- type deps
    --->    deps(
                have_processed,
                module_and_imports
            ).

:- type have_processed
    --->    not_yet_processed
    ;       already_processed.

%---------------------------------------------------------------------------%

:- type submodule_kind
    --->    toplevel
    ;       nested_submodule
    ;       separate_submodule.

    % Check if a module is a top-level module, a nested submodule,
    % or a separate submodule.
    %
:- func get_submodule_kind(module_name, deps_map) = submodule_kind.

%---------------------------------------------------------------------------%

:- pred generate_deps_map(globals::in, maybe_search::in, module_name::in,
    deps_map::in, deps_map::out,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

    % Insert a new entry into the deps_map. If the module already occurred
    % in the deps_map, then we just replace the old entry (presumed to be
    % a dummy entry) with the new one.
    %
    % This can only occur for submodules which have been imported before
    % their parent module was imported: before reading a module and
    % inserting it into the deps map, we check if it was already there,
    % but when we read in the module, we try to insert not just that module
    % but also all the nested submodules inside that module. If a submodule
    % was previously imported, then it may already have an entry in the
    % deps_map. However, unless the submodule is defined both as a separate
    % submodule and also as a nested submodule, the previous entry will be
    % a dummy entry that we inserted after trying to read the source file
    % and failing.
    %
    % Note that the case where a module is defined as both a separate
    % submodule and also as a nested submodule is caught in
    % split_into_submodules.
    %
    % XXX This shouldn't need to be exported.
    %
:- pred insert_into_deps_map(module_and_imports::in,
    deps_map::in, deps_map::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module libs.timestamp.
:- import_module parse_tree.parse_error.
:- import_module parse_tree.prog_data_foreign.
:- import_module parse_tree.prog_item.
:- import_module parse_tree.read_modules.

:- import_module one_or_more.
:- import_module one_or_more_map.
:- import_module pair.
:- import_module set.
:- import_module term.

%---------------------------------------------------------------------------%

get_submodule_kind(ModuleName, DepsMap) = Kind :-
    Ancestors = get_ancestors(ModuleName),
    ( if list.last(Ancestors, Parent) then
        map.lookup(DepsMap, ModuleName, deps(_, ModuleImports)),
        map.lookup(DepsMap, Parent, deps(_, ParentImports)),
        module_and_imports_get_source_file_name(ModuleImports, ModuleFileName),
        module_and_imports_get_source_file_name(ParentImports, ParentFileName),
        ( if ModuleFileName = ParentFileName then
            Kind = nested_submodule
        else
            Kind = separate_submodule
        )
    else
        Kind = toplevel
    ).

%---------------------------------------------------------------------------%

generate_deps_map(Globals, Search, ModuleName, !DepsMap, !Specs, !IO) :-
    generate_deps_map_loop(Globals, Search, map.singleton(ModuleName, []),
        !DepsMap, !Specs, !IO).

    % Values of this type map each module name to the list of contexts
    % that mention it, and thus establish an expectation that a module
    % with that name exists.
    %
:- type expectation_contexts_map == map(module_name, expectation_contexts).
:- type expectation_contexts == list(term.context).

:- pred generate_deps_map_loop(globals::in, maybe_search::in,
    expectation_contexts_map::in, deps_map::in, deps_map::out,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

generate_deps_map_loop(Globals, Search, !.Modules, !DepsMap, !Specs, !IO) :-
    ( if map.remove_smallest(Module, ExpectationContexts, !Modules) then
        generate_deps_map_step(Globals, Search, Module, ExpectationContexts,
            !Modules, !DepsMap, !Specs, !IO),
        generate_deps_map_loop(Globals, Search,
            !.Modules, !DepsMap, !Specs, !IO)
    else
        % If we can't remove the smallest, then the set of modules to be
        % processed is empty.
        true
    ).

:- pred generate_deps_map_step(globals::in, maybe_search::in,
    module_name::in, expectation_contexts::in,
    expectation_contexts_map::in, expectation_contexts_map::out,
    deps_map::in, deps_map::out,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

generate_deps_map_step(Globals, Search, Module, ExpectationContexts,
        !Modules, !DepsMap, !Specs, !IO) :-
    % Look up the module's dependencies, and determine whether
    % it has been processed yet.
    lookup_or_find_dependencies(Globals, Search, Module, ExpectationContexts,
        Deps0, !DepsMap, !Specs, !IO),

    % If the module hadn't been processed yet, then add its imports, parents,
    % and public children to the list of dependencies we need to generate,
    % and mark it as having been processed.
    Deps0 = deps(Done0, ModuleImports),
    (
        Done0 = not_yet_processed,
        Deps = deps(already_processed, ModuleImports),
        map.det_update(Module, Deps, !DepsMap),
        module_and_imports_get_fim_specs(ModuleImports, FIMSpecs),
        % We could keep a list of the modules we have already processed
        % and subtract it from the sets of modules we add here, but doing that
        % actually leads to a small slowdown.
        module_and_imports_get_parse_tree_module_src(ModuleImports,
            ParseTreeModuleSrc),
        ModuleName = ParseTreeModuleSrc ^ ptms_module_name,
        ModuleNameContext = ParseTreeModuleSrc ^ ptms_module_name_context,
        AncestorModuleNames = get_ancestors_set(ModuleName),
        ForeignImportedModuleNames =
            set.map((func(fim_spec(_L, M)) = M), FIMSpecs),
        set.foldl(add_module_name_and_context(ModuleNameContext),
            AncestorModuleNames, !Modules),
        set.foldl(add_module_name_and_context(ModuleNameContext),
            ForeignImportedModuleNames, !Modules),

        module_and_imports_get_int_deps_map(ModuleImports, IntDepsMap),
        module_and_imports_get_imp_deps_map(ModuleImports, ImpDepsMap),
        PublicChildrenMap = ParseTreeModuleSrc ^ ptms_int_includes,
        one_or_more_map.to_assoc_list(IntDepsMap, IntDepsModuleNamesContexts),
        one_or_more_map.to_assoc_list(ImpDepsMap, ImpDepsModuleNamesContexts),
        one_or_more_map.to_assoc_list(PublicChildrenMap,
            ChildrenModuleNamesContexts),
        list.foldl(add_module_name_with_contexts,
            IntDepsModuleNamesContexts, !Modules),
        list.foldl(add_module_name_with_contexts,
            ImpDepsModuleNamesContexts, !Modules),
        list.foldl(add_module_name_with_contexts,
            ChildrenModuleNamesContexts, !Modules)
    ;
        Done0 = already_processed
    ).

:- pred add_module_name_and_context(term.context::in, module_name::in,
    expectation_contexts_map::in, expectation_contexts_map::out) is det.

add_module_name_and_context(Context, ModuleName, !Modules) :-
    ( if map.search(!.Modules, ModuleName, OldContexts) then
        map.det_update(ModuleName, [Context | OldContexts], !Modules)
    else
        map.det_insert(ModuleName, [Context], !Modules)
    ).

:- pred add_module_name_with_contexts(
    pair(module_name, one_or_more(term.context))::in,
    expectation_contexts_map::in, expectation_contexts_map::out) is det.

add_module_name_with_contexts(ModuleName - NewContexts, !Modules) :-
    ( if map.search(!.Modules, ModuleName, OldContexts) then
        NewOldContexts = one_or_more_to_list(NewContexts) ++ OldContexts,
        map.det_update(ModuleName, NewOldContexts, !Modules)
    else
        NewOldContexts = one_or_more_to_list(NewContexts),
        map.det_insert(ModuleName, NewOldContexts, !Modules)
    ).

    % Look up a module in the dependency map.
    % If we don't know its dependencies, read the module and
    % save the dependencies in the dependency map.
    %
:- pred lookup_or_find_dependencies(globals::in, maybe_search::in,
    module_name::in, expectation_contexts::in,
    deps::out, deps_map::in, deps_map::out,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

lookup_or_find_dependencies(Globals, Search, ModuleName, ExpectationContexts,
        Deps, !DepsMap, !Specs, !IO) :-
    ( if map.search(!.DepsMap, ModuleName, DepsPrime) then
        Deps = DepsPrime
    else
        read_dependencies(Globals, Search, ModuleName, ExpectationContexts,
            ModuleImportsList, !Specs, !IO),
        list.foldl(insert_into_deps_map, ModuleImportsList, !DepsMap),
        map.lookup(!.DepsMap, ModuleName, Deps)
    ).

insert_into_deps_map(ModuleImports, !DepsMap) :-
    module_and_imports_get_module_name(ModuleImports, ModuleName),
    Deps = deps(not_yet_processed, ModuleImports),
    map.set(ModuleName, Deps, !DepsMap).

    % Read a module to determine the (direct) dependencies of that module
    % and any nested submodules it contains. Return the module_and_imports
    % structure for the named module, and each of its nested submodules.
    %
:- pred read_dependencies(globals::in, maybe_search::in,
    module_name::in, expectation_contexts::in,
    list(module_and_imports)::out,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

read_dependencies(Globals, Search, ModuleName, ExpectationContexts,
        ModuleAndImportsList, !Specs, !IO) :-
    % XXX If SrcSpecs contains error messages, the parse tree may not be
    % complete, and the rest of this predicate may work on incorrect data.
    read_module_src(Globals, "Getting dependencies for module",
        ignore_errors, Search, ModuleName, ExpectationContexts,
        SourceFileName, always_read_module(dont_return_timestamp), _,
        ParseTreeSrc, SrcSpecs, SrcReadModuleErrors, !IO),
    parse_tree_src_to_module_and_imports_list(Globals, SourceFileName,
        ParseTreeSrc, SrcReadModuleErrors, SrcSpecs, Specs,
        _ParseTreeModuleSrcs, ModuleAndImportsList),
    !:Specs = Specs ++ !.Specs.

%---------------------------------------------------------------------------%
:- end_module parse_tree.deps_map.
%---------------------------------------------------------------------------%
