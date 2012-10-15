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
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen application.
%%%
%%% File: canopen.erl <br/>
%%% Created: 15 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(canopen).

-behaviour(application).

-export([start/0, start/2, stop/1]).
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
    error_logger:info_msg("~p: start: arguments ignored.\n", [?MODULE]),
    case application:get_env(serial) of
	undefined -> 
	    {error, no_serial_specified};
	{ok,Serial} ->
	    Opts = case application:get_env(options) of
		       undefined -> [];
		       {ok, O} -> O
		   end,
	    Args = [{serial, Serial}, {options, Opts}],
	    canopen_sup:start_link(Args)
    end.

%% @private
start() ->
    application:start(eapi),
    application:start(uart),  %% for can_usb
    application:start(can),
    application:start(canopen).

%%--------------------------------------------------------------------
%% @doc
%% Stops the application.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(State::term()) -> ok | {error, Error::term()}.

stop(_State) ->
    ok.
