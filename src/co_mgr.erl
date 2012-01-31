%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%  CANopen manager interface
%%% @end
%%% Created :  5 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_mgr).

-include("sdo.hrl").

-export([start/0, start/1, stop/0]).
-export([fetch/5]).
-export([load/1]).
-export([store/5]).

-define(CO_MGR, co_mgr).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Description: Starts the CANOpen SDO manager, that is, a co_node with
%% Serial = 16#0 and Name = co_mgr, unless it is already running.
%% @end
%%--------------------------------------------------------------------
-spec start() -> {ok, Pid::pid()} | {error, Reason::atom()}.
start() ->
    start([]).

%%--------------------------------------------------------------------
%% @doc
%% Description: Starts the CANOpen SDO manager, that is, a co_node with
%% Serial = 16#0 and Name = co_mgr, unless it is already running.
%%
%% Options: See {@link co_node:start_link/1}.
%%         
%% @end
%%--------------------------------------------------------------------
-spec start(Options::list()) ->  {ok, Pid::pid()} | {error, Reason::atom()}.

start(Options) ->
    %% Check if already running
    case whereis(co_mgr) of
	Pid when is_pid(Pid) ->
	    ok;
	undefined ->
	    co_node:start_link([{serial, 16#000000}, 
				{options, [{name,?CO_MGR}|Options]}])
    end.


%%--------------------------------------------------------------------
%% @doc
%% Description: Stops the CANOpen SDO manager if it is running.
%% @end
%%--------------------------------------------------------------------
-spec stop() ->  ok | {error, Reason::atom()}.

stop() ->
    case whereis(co_mgr) of
	Pid when is_pid(Pid) ->
	    co_node:stop(?CO_MGR);
	undefined ->
	    {error, no_manager_running}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Description: Loads object dictionary from file to the manager.
%% @end
%%--------------------------------------------------------------------
-spec load(File::string()) -> ok | {error, Reason::atom()}.
load(File) ->
    co_node:load_dict(?CO_MGR, File).

%%--------------------------------------------------------------------
%% @doc
%% Description: Fetch object specified by Index, Subind from remote CANOpen
%% node identified by NodeId.<br/>
%% TransferMode controls whether block or segment transfer is used between
%% the CANOpen nodes.<br/>
%% Destination can be:
%% <ul>
%% <li> {app, Pid, Module} - data is sent to the application specified
%% by Pid and Module. </li>
%% <li> {value, Type} - data is decoded and returned to caller. 
%% NOT IMPLEMENTED YET</li>
%% <li> data - data is returned to caller. NOT IMPLEMENTED YET</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec fetch(NodeId::integer(), Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
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

%%--------------------------------------------------------------------
%% @doc
%% Description: Stores object specified by Index, Subind at remote CANOpen
%% node identified by NodeId.<br/>
%% TransferMode controls whether block or segment transfer is used between
%% the CANOpen nodes.<br/>
%% Destination can be:
%% <ul>
%% <li> {app, Pid, Module} - data is fetched from the application specified
%% by Pid and Module. </li>
%% <li> {value, Value, Type} - value is supplied by caller and encoded
%% before the transfer. NOT IMPLEMENTED YET </li>
%% <li> {data, Data} - data is supplied by caller. NOT IMPLEMENTED YET</li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
-spec store(NodeId::integer(), Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer()} |
		      {data, Bin::binary}) ->
		   ok | 
		   {error, Reason::atom()}.

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
