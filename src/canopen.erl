%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%% File    : canopen.erl
%%% Description : CANopen application
%%%
%%% Created : 15 Jan 2008 
%%% @end
%%%-------------------------------------------------------------------

-module(canopen).

-behaviour(application).

-export([start/0, start/2, stop/1]).
%%--------------------------------------------------------------------
%% @private
%% @spec start(StartType, StartArgs) -> {ok, Pid} |
%%                                      {ok, Pid, State} |
%%                                      {error, Reason}
%%      StartType = normal | {takeover, Node} | {failover, Node}
%%      StartArgs = term()
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    io:format("~p: Starting up\n", [?MODULE]),
    case application:get_env(serial) of
	undefined -> 
	    {error, no_serial_specified};
	{ok,Serial} ->
	    Opts = case application:get_env(options) of
		       undefined -> [];
		       {ok, O} -> O
		   end,
	    Args = [{serial, Serial}, {options, Opts}],
	    io:format("~p: Args=~p\n", [?MODULE,Args]),
	    canopen_sup:start_link(Args)
    end.

start() ->
    start(normal, []).

stop(_State) ->
    ok.
