%%%-------------------------------------------------------------------
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2011, Tony Rogvall
%%% @doc
%%%    Defines for debugging.
%%% @end
%%% Created : 15 December 2011
%%%-------------------------------------------------------------------
-ifndef(CO_DEBUG_HRL).
-define(CO_DEBUG_HRL, true).

-ifdef(debug).
-define(dbg(Tag, Format, Args),
	case get(dbg) of
	    true ->
		io:format("~p: ~p: " ++ Format ++ "\n", [self(), ?MODULE] ++ Args);
	    _ ->
		ok
	end).
-else.
-define(dbg(Tag, Format, Args), ok).

-endif.


-endif.
