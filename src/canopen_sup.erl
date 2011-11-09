%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2011, Tony Rogvall
%%% @doc
%%%    Supervisor for canopen application.
%%% @end
%%% Created :  5 November 2011
%%%-------------------------------------------------------------------

-module(canopen_sup).

-behaviour(supervisor).

%% API
-export([start_link/1, stop/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

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

stop(_StartArgs) ->
    ok.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init(Args) ->
    io:format("~p: Starting up\n", [?MODULE]),
    I = co_node,
    CoNode = {I, {I, start_link, [Args]}, permanent, 5000, worker, [I]},
    io:format("~p: About to start ~p\n", [?MODULE,CoNode]),
    {ok, { {one_for_one, 0, 300}, [CoNode]} }.

