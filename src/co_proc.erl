%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Malotte Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%%  Process dictionary.
%%%
%%% File: co_proc.erl
%%% Created:  9 Feb 2012 by Malotte Westman Lonne
%%% @end
%%%-------------------------------------------------------------------
-module(co_proc).

-include("canopen.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).

%% gen_server api
-export([start_link/1, 
	 stop/0]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% function api
-export([reg/1]).
-export([unreg/1]).
-export([lookup/1]).
-export([regs/0, regs/1]).
-export([clear/0]).
-export([clear/1]).
-export([i/0]).
-export([alive/0]).

%% Test functions
-export([debug/1]).

-record(ctx, 
	{
	  term_dict, %% Term -> Pid
	  proc_dict  %% Pid -> list(Term)
	 }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link(list(tuple())) -> 
			{ok, Pid::pid()} | ignore | {error, Error::term()}.

start_link(Opts) ->
    ?ei("~p: start_link: args = ~p\n", [?MODULE, Opts]),
    F =	case proplists:get_value(linked,Opts,true) of
	    true -> start_link;
	    false -> start
	end,
    
    case whereis(?MODULE) of
	Pid when is_pid(Pid) ->
	    {ok, Pid};
	undefined ->
	    gen_server:F({local, ?MODULE}, ?MODULE, [], [])
    end.


%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Reason::atom()}.
				  
stop() ->
    case alive() of
	true -> gen_server:call(?MODULE, stop);
	false -> {error, no_process}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Registers Term.
%% @end
%%--------------------------------------------------------------------
-spec reg(Term::term()) -> ok | {error, Error::term()}.

reg(Term) ->
    case alive() of
	true -> gen_server:call(?MODULE, {reg, Term, self()});
	false -> {error, no_process}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Unregisters Term.
%% @end
%%--------------------------------------------------------------------
-spec unreg(Term::term()) -> ok | {error, Error::term()}.

unreg(Term) ->
    case alive() of
	true -> gen_server:call(?MODULE, {unreg, Term});
	false -> {error, no_process}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Looks up Term and returns corresponding Pid.
%% @end
%%--------------------------------------------------------------------
-spec lookup(Term::term()) -> Pid::pid() | {error, Error::term()}.

lookup(Term) ->
    ?dbg("lookup: Term = ~w", [Term]),    
    case ets:info(co_term_dict, name) of
	undefined -> 
	    {error, no_process};
	_N -> 
	    case ets:lookup(co_term_dict, Term) of
		[{Term, Pid}] -> Pid;
		[] -> {error, not_found}
	    end
    end.

%%--------------------------------------------------------------------
%% @doc
%% Looks up all terms for self().
%% @end
%%--------------------------------------------------------------------
-spec regs() -> list(term()) | {error, Error::term()}.

regs() ->
    regs(self()).

%%--------------------------------------------------------------------
%% @doc
%% Looks up all terms for Pid.
%% @end
%%--------------------------------------------------------------------
-spec regs(Pid::pid()) -> list(term()) | {error, Error::term()}.

regs(Pid) ->
    case ets:lookup(co_proc_dict, Pid) of
	[{_Pid, {dead, _R}, _TermList}] -> {error, dead};
	[{_Pid, _Mon, TermList}] -> TermList;
	[] -> {error, not_found}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Clears all Terms registered to self().
%% @end
%%--------------------------------------------------------------------
-spec clear() -> ok | {error, Error::term()}.

clear()  -> clear(self()).

%%--------------------------------------------------------------------
%% @doc
%% Clears all Terms registered to Pid.
%% @end
%%--------------------------------------------------------------------
-spec clear(Pid::pid()) -> ok | {error, Error::term()}.

clear(Pid) when is_pid(Pid) ->
    case alive() of
	true -> gen_server:call(?MODULE, {clear, Pid});
	false -> {error, no_process}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Lists all registrations.
%% @end
%%--------------------------------------------------------------------
-spec i() -> list(term()) | {error, Error::term()}.

i() ->
    ets:tab2list(co_proc_dict).

%%--------------------------------------------------------------------
%% @doc
%% Checks if the co_proc still is alive.
%% @end
%%--------------------------------------------------------------------
alive() ->
    case whereis(?MODULE) of
	undefined -> false;
	_PI -> true
    end.

%%--------------------------------------------------------------------
%% @doc
%% Adjust debug flag.
%% @end
%%--------------------------------------------------------------------
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?MODULE, {debug, TrueOrFalse}).

	
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init([]) -> {ok, Ctx::#ctx{}}.

init([]) ->
    ?ei("~p: init: args = [], pid = ~p\n", [?MODULE, self()]),

    PD = ets:new(co_proc_dict, [protected, named_table, ordered_set]),
    TD = ets:new(co_term_dict, [protected, named_table, ordered_set]),
    {ok, #ctx {proc_dict = PD, term_dict = TD}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{reg, Term::term(), Pid::pid()} |
	{unreg, Term::term()} |
	{clear, Pid::pid()} |
	{debug, TrueOrFalse::boolean()} |
	stop.

-spec handle_call(Request::call_request(),
		  From::{pid(), term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {stop, Reason::term(), Reply::term(), Ctx::#ctx{}}.

handle_call({reg, Term, Pid}, _From, Ctx=#ctx {term_dict = TD, proc_dict = PD}) 
  when is_pid(Pid) ->
    ?dbg("handle_call: reg Term = ~w, Pid = ~w", [Term, Pid]),    
    case ets:lookup(TD, Term) of
	[] ->
	    ets:insert(TD, {Term, Pid}),
	    case ets:lookup(PD, Pid) of
		[] ->
		    %% New process
		    Mon = erlang:monitor(process, Pid),
		    ets:insert(PD, {Pid, Mon, [Term]}),
		    {reply, ok, Ctx};
		[{Pid, Mon, TermList}] when is_reference(Mon) ->
		    ets:insert(PD, {Pid, Mon, TermList ++ [Term]}),
		    {reply, ok, Ctx};
		[{Pid, {dead, _Reason} = Mon, _TermList}]  ->
		    ets:insert(PD, {Pid, Mon, []}),
		    {reply, {error, process_dead}, Ctx}
	    end;
	[{Term, Pid}] ->
	    %% No change
	    {reply, ok, Ctx};
	[_Entry] ->
	    {reply, {error, already_registered}, Ctx}
    end;
handle_call({unreg, Term}, _From, Ctx=#ctx {term_dict = TD, proc_dict = PD}) ->
    ?dbg("handle_call: unreg Term = ~w", [Term]),    
    case ets:lookup(TD, Term) of
	[{Term, Pid}] ->
	    ets:delete(TD, Term),
	    [{Pid, Mon, TermList}] = ets:lookup(PD, Pid),
	    case TermList -- [Term] of
		[] -> 
		    %% Last entry removed
		    erlang:demonitor(Mon),
		    ets:delete(PD, Pid),
		    {reply, ok, Ctx};
		NewList ->
		    ets:insert(PD, {Pid, Mon, NewList}),
		    {reply, ok, Ctx}
	    end;
	[] ->
	    {reply, ok, Ctx}
    end;
handle_call({clear, Pid}, _From, Ctx=#ctx {term_dict = TD, proc_dict = PD}) ->
    ?dbg("handle_call: clear Pid = ~w", [Pid]),    
    case ets:lookup(PD, Pid) of
	[{Pid, Mon, _TermList}] ->
	    try ets:match_delete(TD, {'_', Pid}) of
		true -> ok
	    catch 
		error:Reason ->
		    ?ew("~p: Delete of terms for ~p failed, reason ~p\n", 
			[?MODULE, Pid, Reason]),
		    ok
	    end,
	    case Mon of
		{dead, _R} -> do_nothing;
		_M -> erlang:demonitor(Mon)
	    end,
	    ets:delete(PD, Pid),
	    {reply, ok, Ctx};
	[]->
	    {reply, ok, Ctx}
    end;
handle_call({debug, TrueOrFalse}, _From, Ctx) ->
    put(dbg, TrueOrFalse),
    {reply, ok, Ctx};
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_cast(_Msg, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Handles 'DOWN' messages for monitored processes.
%% @end
%%--------------------------------------------------------------------
-type info()::
	{'DOWN', Ref::reference(), process, Pid::pid(), Reason::term()} |
	term().


-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}}.

handle_info({'DOWN',_Ref, process, Pid, Reason}, 
	    Ctx=#ctx {term_dict = TD, proc_dict = PD}) ->
    ?ew("~p: Monitored process ~p died\n", [?MODULE, Pid]),
    ets:match_delete(TD, {'_', Pid}),
    ets:insert(PD, {Pid, {dead, Reason}, []}),
    {noreply, Ctx};
handle_info(_Info, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, Ctx) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _Ctx) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @spec code_change(OldVsn, Ctx, Extra) -> {ok, NewCtx}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.

%%%===================================================================
%%% Internal functions
%%%===================================================================



