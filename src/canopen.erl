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
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% CANopen application.
%%%
%%% File: canopen.erl <br/>
%%% Created: 15 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(canopen).

-behaviour(application).

%% Application API
-export([start/2, 
	 stop/1]).

%% Shortcut API
-export([start/0,
	 stop/0]).


%%--------------------------------------------------------------------
%% @doc
%% Starts the canopen application, that is, the canopen supervisor.<br/>
%% Arguments are ignored, instead the options for the application servers are 
%% retreived from the application environment (sys.config).
%%
%% @end
%%--------------------------------------------------------------------
-spec start(StartType:: normal | 
			{takeover, Node::atom()} | 
			{failover, Node::atom()}, 
	    StartArgs::term()) -> 
		   {ok, Pid::pid()} |
		   {ok, Pid::pid(), State::term()} |
		   {error, Reason::term()}.

start(_StartType, _StartArgs) ->
    case application:get_env(canopen, serial) of
	undefined -> 
	    {error, no_serial_specified};
	{ok,Serial} ->
	    canopen_sup:start_link(Serial)
    end.


%%--------------------------------------------------------------------
%% @doc
%% Stops the application.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(State::term()) -> ok | {error, Error::term()}.

stop(_State) ->
    exit(normal).

%% @private
start() ->
    (catch error_logger:tty(false)),
    try application:ensure_all_started(canopen)
    catch 
	%% Old OTP version
	error:undef ->
	    call([sasl, lager, ale, eapi, uart, can, canopen], 
		 start)
    end.

%% @private
stop() ->
    call([can, uart, eapi, ale, lager],
	 stop).

call([], _F) ->
    ok;
call([App|Apps], F) ->
    error_logger:info_msg("~p: ~p\n", [F,App]),
    case application:F(App) of
	{error,{not_started,App1}} ->
	    call([App1,App|Apps], F);
	{error,{already_started,App}} ->
	    call(Apps, F);
	ok ->
	    call(Apps, F);
	Error ->
	    Error
    end.

