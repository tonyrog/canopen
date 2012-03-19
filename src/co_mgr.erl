%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%  CANopen manager interface.
%%%  A co_mgr and a co_node with serial number 0 are started.
%%%
%%% File: co_mgr.erl <br/>
%%% Created:  5 Jun 2010 by Tony Rogvall 
%%% @end

-module(co_mgr).

-include("canopen.hrl").
-include("sdo.hrl").
-include("co_debug.hrl").

%% api
-export([start/0, start/1, stop/0]).
-export([fetch/5]).
-export([load/1]).
-export([store/5]).
-export([require/1]).
-export([setnid/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% Test functions
-export([debug/1]).
-export([loop_data/0]).


-define(CO_MGR, co_mgr).

-record(mgr_ctx,
	{
	  def_nid,
	  ctx
	}).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the CANOpen SDO manager and a co_node with
%% Serial = 16#0, unless it is already running.
%% @end
%%--------------------------------------------------------------------
-spec start() -> {ok, Pid::pid()} | {error, Reason::atom()}.
start() ->
    start([]).

%%--------------------------------------------------------------------
%% @doc
%% Starts the CANOpen SDO manager and a co_node with
%% Serial = 16#0, unless it is already running.
%%
%% Options: See {@link co_api:start_link/1}.
%%         
%% @end
%%--------------------------------------------------------------------
-spec start(Options::list()) ->  {ok, Pid::pid()} | {error, Reason::atom()}.

start(Options) ->
    %% Check if co_mgr already running
    F =	case proplists:get_value(unlinked,Options,false) of
	    true -> start;
	    false -> start_link
	end,

    case co_proc:lookup(?MGR_NODE) of
	MPid when is_pid(MPid) ->
	    ok;
	{error, not_found} ->
	    {ok, _NewMPid} = gen_server:F({local, ?CO_MGR}, ?MODULE, Options, [])
    end.


%%--------------------------------------------------------------------
%% @doc
%% Stops the CANOpen SDO manager if it is running.
%% @end
%%--------------------------------------------------------------------
-spec stop() ->  ok | {error, Reason::atom()}.

stop() ->
    case whereis(?CO_MGR) of
	Pid when is_pid(Pid) ->
	    gen_server:call(Pid, stop);
	undefined ->
	    {error, no_manager_running}
    end.


require(Mod) ->
    gen_server:call(?CO_MGR, {require, Mod}).

%% Set the default nodeid - for short interface
setnid(Nid) ->
    gen_server:call(?CO_MGR, {setnid, Nid}).

    
    
%%--------------------------------------------------------------------
%% @doc
%% Loads object dictionary from file to the manager.
%% @end
%%--------------------------------------------------------------------
-spec load(File::string()) -> ok | {error, Reason::atom()}.
load(File) ->
    co_api:load_dict(?CO_MGR, File).

%%--------------------------------------------------------------------
%% @doc
%% Fetch object specified by Index, Subind from remote CANOpen
%% node identified by NodeId.<br/>
%% TransferMode controls whether block or segment transfer is used between
%% the CANOpen nodes.<br/>
%% Destination can be:
%% <ul>
%% <li> {app, Pid, Module} - data is sent to the application specified
%% by Pid and Module. </li>
%% <li> {value, Type} - data is decoded and returned to caller. </li>
%% <li> data - data is returned to caller. </li>
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
	_Info -> co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, Term)
    end;
fetch(NodeId, Ix, Si, TransferMode, {value, Type}) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_integer(Type) ->
    case co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, data) of
	{ok, Data} ->
	    case co_codec:decode(Data, Type) of
		{Value, _} -> {ok, Value};
		Error -> Error
	    end;
	Error -> Error
    end;
fetch(NodeId, Ix, Si, TransferMode, data = Term) ->
    co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, Term).

%%--------------------------------------------------------------------
%% @doc
%% Stores object specified by Index, Subind at remote CANOpen
%% node identified by NodeId.<br/>
%% TransferMode controls whether block or segment transfer is used between
%% the CANOpen nodes.<br/>
%% Destination can be:
%% <ul>
%% <li> {app, Pid, Module} - data is fetched from the application specified
%% by Pid and Module. </li>
%% <li> {value, Value, Type} - value is supplied by caller and encoded
%% before the transfer.  </li>
%% <li> {data, Data} - data is supplied by caller. T</li>
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
	_Info -> co_api:store(?MGR_NODE, NodeId, Ix, Si, TransferMode, Term)
    end;
store(NodeId, Ix, Si, TransferMode, {value, Value, Type}) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_integer(Type) ->
    co_api:store(?MGR_NODE, NodeId, Ix, Si, TransferMode, 
		  {data, co_codec:encode(Value, Type)});
store(NodeId, Ix, Si, TransferMode, {data, Bin} = Term)
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si), 
       is_binary(Bin) ->
    co_api:store(?MGR_NODE, NodeId, Ix, Si, TransferMode, Term).


%% For testing
%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?CO_MGR, {debug, TrueOrFalse}).

loop_data() ->
    gen_server:call(?CO_MGR, loop_data).


%%====================================================================
%% gen_server callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Description: Initiates the server
%% @end
%%--------------------------------------------------------------------
-spec init(Opts::list()) -> 
		  {ok, Context::record()} |
		  {ok, Context::record(), Timeout::integer()} |
		  ignore               |
		  {stop, Reason::atom()}.
init(Opts) ->
    %% Trace output enable/disable
    put(dbg, proplists:get_value(debug,Opts,false)), 

    case co_proc:lookup(?MGR_NODE) of
	NPid when is_pid(NPid) ->
	    ok;
	{error, not_found} ->
	    ?dbg(mgr, "init: starting co_node with serial = 0", []),
	    {ok, _NewNPid}  = co_api:start_link(?MGR_NODE,  
						 [{nodeid, 0}] ++ Opts)
    end,

    {ok, #mgr_ctx {def_nid = undefined, ctx = undefined}}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request::stop,
		  From::pid(), Ctx::record()) ->
			 {reply, Reply::term(), Ctx::record()} |
			 {reply, Reply::term(), Ctx::record(), Timeout::timeout()} |
			 {noreply, Ctx::record()} |
			 {noreply, Ctx::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Reply::term(), Ctx::record()} |
			 {stop, Reason::term(), Ctx::record()}.

handle_call({debug, TrueOrFalse}, _From, Ctx) ->
    put(dbg, TrueOrFalse),
    {reply, ok, Ctx};
handle_call(loop_data, _From, Ctx) ->
    io:format("Loop data = ~p\n", [Ctx]),
    {reply, ok, Ctx};
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};
handle_call(_Request, _From, Ctx) ->
    ?dbg(mgr, "handle_call: Unknown request ~p", [ _Request]),
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), Ctx::record()) -> 
			 {noreply, Ctx::record()} |
			 {noreply, Ctx::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::record()}.

handle_cast(_Msg, Ctx) ->
    ?dbg(mgr, "handle_cast: Unknown msg ~p", [_Msg]),
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Handles 'DOWN' messages for monitored processes.
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info::term(), Ctx::record()) -> 
			 {noreply, Ctx::record()} |
			 {noreply, Ctx::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::record()}.

handle_info(_Info, Ctx) ->
    ?dbg(mgr, "handle_info: Unknown info ~p", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, Ctx) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _Ctx) ->
    case co_proc:lookup(?MGR_NODE) of
	Pid when is_pid(Pid) ->
	    ?dbg(mgr, "terminate: Stoping co_node 0", []),
	    co_api:stop(?MGR_NODE);
	{error, not_found} ->
	    do_nothing
    end,
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @spec code_change(OldVsn, Ctx, Extra) -> {ok, NewCtx}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Ctx, _Extra) ->
    ?dbg(mgr, "code_change: Old version ~p", [_OldVsn]),
    {ok, Ctx}.

