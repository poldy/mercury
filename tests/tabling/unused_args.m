% Regression test.

% Versions rotd-2000-04-03 and earlier
% got a software error when compiling this test.

:- module unused_args.
:- interface.
:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.
:- import_module std_util.

main(!IO) :-
	test(!IO),
	test(!IO),
	test(!IO).

:- pred test(io::di, io::uo) is det.
:- pragma no_inline(test/2).

test(!IO) :-
	foo_unused_args(42, Z),
	print(Z, !IO),
	nl(!IO),
	( foo_unused_args_semi(42, Y) ->
		print(Y, !IO),
		nl(!IO)
	;
		io__write_string("foo_unused_args failed\n", !IO)
	),
	( foo_fail(X) ->
		print(X, !IO),
		nl(!IO)
	;
		io__write_string("foo_fail failed, as expected\n", !IO)
	).

:- pred foo_unused_args(int::in, string::out) is det.
:- pragma memo(foo_unused_args/2).

foo_unused_args(_, "foo").

:- pred foo_unused_args_semi(int::in, string::out) is semidet.
:- pragma memo(foo_unused_args_semi/2).

foo_unused_args_semi(_, "bar") :- semidet_succeed.

:- pred foo_fail(string::out) is semidet.
:- pragma memo(foo_fail/1).

foo_fail("") :- semidet_fail.
