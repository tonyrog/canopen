%%%---- BEGIN COPYRIGHT -------------------------------------------------------
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lonne <malotte@malotte.net>
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

-include("canopen.hrl").

%% API
-export([start_link/1, 
	 stop/0]).

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
start_link(Serial) ->
    try supervisor:start_link({local, ?MODULE}, ?MODULE, [Serial]) of
	{ok, Pid} ->
	    {ok, Pid, {normal, [Serial]}};
	Error -> 
	    ?ee("~p: start_link: Failed to start process, "
		"reason ~p",  [?MODULE, Error]),
	    Error
    catch 
	error:Reason ->
	    ?ee("~p: start_link: Try failed, reason ~p", [?MODULE,Reason]),
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
init([Serial]) ->
    lager:debug("serial = ~p,\n pid = ~p", [Serial, self()]),
    Opts = application:get_env(canopen, options, []),
    lager:debug("options = ~p", [Opts]),
    CP = co_proc,
    CN = co_api,
    SA = co_sys_app,
    OA = co_os_app,
    %% can_router started by can application
    CoProc = {CP, 
	      {CP, start_link, [[]]}, 
	      permanent, 5000, worker, [CP]},
    CoNode = {co_node, 
	      {CN, start_link, [Serial, Opts]}, 
	      permanent, 5000, worker, [CN]},
    SysApp = {SA, 
	      {SA, start_link, [Serial]},
	      permanent, 5000, worker, [SA]},
    OsApps = case application:get_env(canopen, os_commands_enabled, false) of
		 true ->
		     [{OA, 
		       {OA, start_link, [Serial]}, 
		       permanent, 5000, worker, [OA]}];
		 false ->
		     lager:debug("no os command app"),
		     []
	     end,
    Processes = [CoProc, CoNode, SysApp] ++ OsApps,
    lager:debug("about to start ~p", [Processes]),
    {ok, { {rest_for_one, 0, 300}, Processes} }.


