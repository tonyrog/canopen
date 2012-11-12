%%%---- BEGIN COPYRIGHT --------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2012, Rogvall Invest AB, <tony@rogvall.se>
%%%
%%% This software is licensed as described in the file COPYRIGHT, which
%%% you should have received as part of this distribution. The terms
%%% are also available at http://www.rogvall.se/docs/copyright.txt.
%%%
%%% You may opt to use, copy, modify, merge, publish, distribute and/or sell
%%% copies of the Software, and permit persons to whom the Software is
%%% furnished to do so, under the terms of the COPYRIGHT file.
%%%
%%% This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
%%% KIND, either express or implied.
%%%
%%%---- END COPYRIGHT ----------------------------------------------------------
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
		io:format("~s: ~p: ~p: " ++ Format ++ "\n", 
			  [co_lib:utc_time(), self(), ?MODULE] ++ Args);
	    _ ->
		ok
	end).
-else.
-define(dbg(_Tag, Format, Args),
	ok.
%% When switching to lager
%% -define(dbg(_Tag, Format, Args),
%% 	lager:debug("~s(~p): " ++ Format, [?MODULE, self() | Args])).


-endif.


-endif.
