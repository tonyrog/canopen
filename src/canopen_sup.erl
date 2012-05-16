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
    error_logger:info_msg("~p: start_link: args = ~p\n", [?MODULE, Args]),
    try supervisor:start_link({local, ?MODULE}, ?MODULE, Args) of
	{ok, Pid} ->
	    {ok, Pid, {normal, Args}};
	Error -> 
	    error_logger:error_msg("~p: start_link: Failed to start process, "
				   "reason ~p\n",  [?MODULE, Error]),
	    Error
    catch 
	error:Reason ->
	    error_logger:error_msg("~p: start_link: Try failed, reason ~p\n", 
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
    error_logger:info_msg("~p: init: args = ~p,\n pid = ~p\n", [?MODULE, Args, self()]),
    Serial = proplists:get_value(serial, Args, 0),
    Opts = proplists:get_value(options, Args, []),
    CU = can_udp,
    CP = co_proc,
    CN = co_api,
    SA = co_sys_app,
    OA = co_os_app,
    %% can_router started by can application
    CanUdp = {CU, {CU, start, [0]}, permanent, 5000, worker, [CU]}, %% start_link ??
    CoProc = {CP, {CP, start_link, [[]]}, permanent, 5000, worker, [CP]},
    CoNode = {co_node, {CN, start_link, [Serial, Opts]}, permanent, 5000, worker, [CN]},
    SysApp = {SA, {SA, start_link, [Serial]}, permanent, 5000, worker, [SA]},
    OsApp = {OA, {OA, start_link, [Serial]}, permanent, 5000, worker, [OA]},
    Processes = [CanUdp, CoProc, CoNode, SysApp, OsApp],
    error_logger:info_msg("~p: About to start ~p\n", [?MODULE, Processes]),
    {ok, { {rest_for_one, 0, 300}, Processes} }.


