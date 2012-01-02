%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%  CANOPEN manager interface
%%% @end
%%% Created :  5 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_mgr).

-include("sdo.hrl").

-export([start/0, start/1, stop/0]).
-export([fetch/5]).
-export([load/1]).
-export([store/5]).

-define(CO_MGR, co_mgr).

start() ->
    start([]).
start(Opts) ->
    co_node:start_link([{serial, 16#000000}, {options, [{name,?CO_MGR}|Opts]}]).

stop() ->
    co_node:stop(?CO_MGR).

load(File) ->
    co_node:load_dict(?CO_MGR, File).

-spec fetch(NodeId::integer(), Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Term:: {app, Pid::pid(), Mod::atom()} | 
		   {value, Type::integer()} |
		   data) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::atom()}.
		   
fetch(NodeId, Ix, Si, TransferMode, {app, Pid, Mod} = Term) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_pid(Pid),
       is_atom(Mod) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:fetch(?CO_MGR, NodeId, Ix, Si, TransferMode, Term)
    end;
fetch(NodeId, Ix, Si, TransferMode, {value, Type}) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_integer(Type) ->
    case co_node:fetch(?CO_MGR, NodeId, Ix, Si, TransferMode, data) of
	{ok, Data} ->
	    case co_codec:decode(Data, Type) of
		{Value, _} -> {ok, Value};
		Error -> Error
	    end;
	Error -> Error
    end;
fetch(NodeId, Ix, Si, TransferMode, data = Term) ->
    co_node:fetch(?CO_MGR, NodeId, Ix, Si, TransferMode, Term).

store(NodeId, Ix, Si, TransferMode, {app, Pid, Mod} = Term) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_pid(Pid),
       is_atom(Mod) ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_node:store(?CO_MGR, NodeId, Ix, Si, TransferMode, Term)
    end;
store(NodeId, Ix, Si, TransferMode, {value, Value, Type}) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_integer(Type) ->
    co_node:store(?CO_MGR, NodeId, Ix, Si, TransferMode, 
		  {data, co_codec:encode(Value, Type)});
store(NodeId, Ix, Si, TransferMode, {data, Bin} = Term)
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_binary(Bin) ->
    co_node:store(?CO_MGR, NodeId, Ix, Si, TransferMode, Term).
