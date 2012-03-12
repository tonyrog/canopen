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
    try supervisor:start_link({local, ?MODULE}, ?MODULE, Args) of
	{ok, Pid} ->
	    io:format("~p: start_link: started process ~p\n", [?MODULE,Pid]),
	    {ok, Pid, {normal, Args}};
	Error -> 
	    io:format("~p: start_link: start_link failed, reason ~p\n", 
		      [?MODULE,Error]),
	    Error
    catch 
	error:Reason ->
	    io:format("~p: start_link: Try failed, reason ~p\n", 
		      [?MODULE,Reason]),
	    Reason

    end.

%%--------------------------------------------------------------------
%% @spec stop() -> ok
%% @doc
%% Stops the supervisor.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
    exit(normal).


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
    io:format("~p: init: Args = ~p\n", [?MODULE, Args]),
    Serial = proplists:get_value(serial, Args, 0),
    Opts = proplists:get_value(options, Args, []),
    CU = can_udp,
    CP = co_proc,
    CN = co_node,
    SA = co_sys_app,
    OA = co_os_app,
    %% can_router started by can application
    CanUdp = {CU, {CU, start, [0]}, permanent, 5000, worker, [CU]}, %% start_link ??
    CoProc = {CP, {CP, start_link, [[]]}, permanent, 5000, worker, [CP]},
    CoNode = {CN, {CN, start_link, [Serial, Opts]}, permanent, 5000, worker, [CN]},
    SysApp = {SA, {SA, start_link, [Serial]}, permanent, 5000, worker, [SA]},
    OsApp = {OA, {OA, start_link, [Serial]}, permanent, 5000, worker, [OA]},
    Processes = [CanUdp, CoProc, CoNode, SysApp, OsApp],
    io:format("~p: About to start ~p\n", 
	      [?MODULE, Processes]),
    {ok, { {rest_for_one, 0, 300}, Processes} }.


