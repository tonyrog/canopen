%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%    Supervisor for canopen application.
%%%
%%% File: canopen_sup.erl <br/>
%%% Created:  5 November 2011 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------

-module(canopen_sup).

-behaviour(supervisor).

%% API
-export([start_link/1, stop/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @spec start_link(Args) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%% Starts the supervisor.
%%
%%   Args = [{serial, Serial}, {options, Options}]
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    case supervisor:start_link({local, ?MODULE}, ?MODULE, Args) of
	{ok, Pid} ->
	    io:format("~p: start_link: started process ~p\n", [?MODULE,Pid]),
	    {ok, Pid, {normal, Args}};
	Error -> 
	    io:format("~p: start_link: Failed to start process, reason ~p\n", 
		      [?MODULE,Error]),
	    Error
    end.

%%--------------------------------------------------------------------
%% @spec stop() -> ok
%% @doc
%% Stops the supervisor.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
    ok.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @doc
%% Starts the co_proc and the co_node.
%%
%% @end
%%--------------------------------------------------------------------
init(Args) ->
    io:format("~p: Starting up\n", [?MODULE]),
    CP = co_proc,
    CoProc = {CP, {CP, start_link, []}, permanent, 5000, worker, [CP]},
    CN = co_node,
    CoNode = {CN, {CN, start_link, [Args]}, permanent, 5000, worker, [CN]},
    io:format("~p: About to start ~p and ~p\n", [?MODULE,CoProc, CoNode]),
    {ok, { {all_for_one, 0, 300}, [CoProc, CoNode]} }.


