%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% File    : canopen.erl <br/>
%%% Description : CANopen application.
%%%
%%% Created : 15 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------

-module(canopen).

-behaviour(application).

-export([start/0, start/2, stop/1]).
%%--------------------------------------------------------------------
%% @spec start(StartType, StartArgs) -> {ok, Pid} |
%%                                      {ok, Pid, State} |
%%                                      {error, Reason}
%%      StartType = normal | {takeover, Node} | {failover, Node}
%%      StartArgs = term()
%% @doc
%% Starts the canopen application, that is, the canopen suprevisor.
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

%% @private
start() ->
    start(normal, []).

%%--------------------------------------------------------------------
%% @spec stop(State) -> ok
%%
%% @doc
%% Stops the CANopen application.
%% @end
%%--------------------------------------------------------------------
stop(_State) ->
    ok.
