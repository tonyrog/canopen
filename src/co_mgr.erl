%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%  CANOPEN manager interface
%%% @end
%%% Created :  5 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_mgr).

-export([start/0, start/1, stop/0]).
-export([fetch/3, fetch/4, fetch/5]).
-export([load/1]).
-export([fetch_block/3, fetch_block/4, fetch_block/5]).
-export([store/4, store/5]).
-export([store_block/4, store_block/5]).

-define(CO_MGR_NAME, ?MODULE).

start() ->
    start([]).
start(Opts) ->
    co_node:start_link([{serial, 0}, {options, [{name,co_mgr}|Opts]}]).

stop() ->
    co_node:stop(?CO_MGR_NAME).

load(File) ->
    co_node:load_dict(?CO_MGR_NAME, File).

fetch(NodeId, Ix, Si, Pid, Mod) when is_pid(Pid) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:fetch_block(?CO_MGR_NAME, NodeId, Ix, Si, {Pid, Mod})
    end.

fetch(NodeId, IX, SI, Type) ->
    case fetch(NodeId, IX, SI) of
	{ok, Data} ->
	    case co_codec:decode(Data, Type) of
		{Value, _} -> {ok, Value};
		Error -> Error
	    end;
	Error -> Error
    end.

%% FIXME: deduce the type from IX:SI for standard or profile objects
fetch(NodeId, IX, SI) ->
    co_node:fetch(?CO_MGR_NAME, NodeId, IX, SI).

fetch_block(NodeId, Ix, Si, Pid, Mod) when is_pid(Pid) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:fetch(?CO_MGR_NAME, NodeId, Ix, Si, {Pid, Mod})
    end.
fetch_block(NodeId, IX, SI, Type) ->
    case fetch_block(NodeId, IX, SI) of
	{ok, Data} ->
	    case co_codec:decode(Data, Type) of
		{Value, _} -> {ok, Value};
		Error -> Error
	    end;
	Error -> Error
    end. 

fetch_block(NodeId, IX, SI) ->
    co_node:fetch_block(?CO_MGR_NAME, NodeId, IX, SI).

store(NodeId, Ix, Si, Pid, Mod) when is_pid(Pid) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:store(?CO_MGR_NAME, NodeId, Ix, Si, {Pid, Mod})
    end;
store(NodeId, IX, SI, Value, Type) ->
    store(NodeId, IX, SI, co_codec:encode(Value, Type)).

store(NodeId, IX, SI, Bin) when is_binary(Bin) ->
    co_node:store(?CO_MGR_NAME, NodeId, IX, SI, Bin).

store_block(NodeId, Ix, Si, Pid, Mod) when is_pid(Pid) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:store_block(?CO_MGR_NAME, NodeId, Ix, Si, {Pid, Mod})
    end;
store_block(NodeId, IX, SI, Value, Type) ->
    store_block(NodeId, IX, SI, co_codec:encode(Value, Type)).

store_block(NodeId, IX, SI, Bin) when is_binary(Bin) ->
    co_node:store_block(?CO_MGR_NAME, NodeId, IX, SI, Bin).
