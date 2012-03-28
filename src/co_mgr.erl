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

%% regular api
-export([start/0, start/1, stop/0]).
-export([fetch/5,fetch/4]).
-export([store/5,store/4]).
-export([load/1]).

%% api when using definition files
-export([client_require/1]).
-export([client_set_nid/1]).
-export([client_set_mode/1]).
-export([client_store/4, client_store/3, client_store/2]).
-export([client_fetch/3, client_fetch/2, client_fetch/1]).
-export([client_notify/4, client_notify/3, client_notify/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% spawned function
-export([execute_request/5]).

%% Test functions
-export([debug/1]).
-export([loop_data/0, loop_data/1]).


-define(CO_MGR, co_mgr).
-record(node,
	{
	  nid,             %% CAN node id
	  serial=0,        %% serial 
	  product=unknown, %% product code
	  state=up         %% up/down/sleep
	}).


-record(mgr,
	{
	  def_nid,         %% default node for short operations
	  def_trans_mode = segment, %% default transfer mode
	  nodes = [],      %% nodes detected
	  pids = [],       %% list of outstanding operations
	  ctx,             %% current context
	  ctx_list =[]     %% [{mod,<ctx>}] 
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
    put(dbg, proplists:get_value(debug,Options,false)), 
    ?dbg(mgr, "start: Opts = ~p", [Options]),

    F =	case proplists:get_value(linked,Options,true) of
	    true -> start_link;
	    false -> start
	end,

    case co_proc:alive() of
	true -> do_nothing;
	false -> co_proc:start_link(Options)
    end,

    case co_proc:lookup(?CO_MGR) of
	MPid when is_pid(MPid) ->
	    ok;
	{error, not_found} ->
	    ?dbg(mgr, "Starting co_mgr with function = ~p", [F]),
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
fetch(NodeId, Ix, Si, TransferMode, {value, Type}) when is_atom(Type) ->
    fetch(NodeId, Ix, Si, TransferMode, {value, co_lib:encode_type(Type)}); 
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

-spec fetch(NodeId::integer(), {Ix::integer(), Si::integer()},
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  {value, Type::integer()} |
			  data) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::atom()}.
		   
fetch(NodeId, {Ix, Si}, TransferMode, Term) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si) ->
fetch(NodeId, Ix, Si, TransferMode, Term).

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
store(NodeId, Ix, Si, TransferMode, {value, Value, Type}) when is_atom(Type) ->
 store(NodeId, Ix, Si, TransferMode, {value, Value, co_lib:encode_type(Type)});
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

-spec store(NodeId::integer(), {Ix::integer(), Si::integer()},
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer()} |
		      {data, Bin::binary}) ->
		   ok | 
		   {error, Reason::atom()}.

store(NodeId, {Ix, Si}, TransferMode,  Term) 
  when is_integer(NodeId), 
       is_integer(Ix), 
       is_integer(Si) ->
store(NodeId, Ix, Si, TransferMode,  Term).

%% API used by co_script

client_require(Mod) 
  when is_atom(Mod) ->
    ?dbg(mgr, "client_require: module ~p", [Mod]),
    gen_server:call(?CO_MGR, {require, Mod}).

%% Set the default nodeid - for short interface
client_set_nid(Nid) 
  when is_integer(Nid) andalso Nid < 2#1000000000000000000000000 -> %% Max 24 bit
    gen_server:call(?CO_MGR, {set_nid, Nid}).

%% Set the default transfer mode
client_set_mode(Mode) 
  when Mode == block;
       Mode == segment ->
    gen_server:call(?CO_MGR, {set_mode, Mode}).

%% Store value
client_store(Nid, Index, SubInd, Value) ->
    gen_server:call(?CO_MGR, {store, Nid, Index, SubInd, Value}).

client_store(Index, SubInd, Value) ->
    gen_server:call(?CO_MGR, {store, Index, SubInd, Value}).

client_store(Index, Value) ->
    gen_server:call(?CO_MGR, {store, Index, 0, Value}).

%% Fetch value
client_fetch(Nid, Index, SubInd) ->
    gen_server:call(?CO_MGR, {fetch, Nid, Index, SubInd}).

client_fetch(Index, SubInd)  ->
    gen_server:call(?CO_MGR, {fetch, Index, SubInd}).

client_fetch(Index)  ->
    gen_server:call(?CO_MGR, {fetch, Index, 0}).

%% Send notification
client_notify(Nid, Index, Subind, Value) ->
    gen_server:cast(?CO_MGR, {notify, Nid, Index, Subind, Value}).

client_notify(Index, Subind, Value) ->
    gen_server:cast(?CO_MGR, {notify, Index, Subind, Value}).
  
client_notify(Index, Value) ->
    gen_server:cast(?CO_MGR, {notify, Index, 0, Value}).

%% For testing
%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?CO_MGR, {debug, TrueOrFalse}).

loop_data(Qual) when Qual == no_ctx ->
    gen_server:call(?CO_MGR, {loop_data, Qual}).
loop_data() ->
    gen_server:call(?CO_MGR, {loop_data, all}).

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

    co_proc:reg(?CO_MGR),

    case co_proc:lookup(?MGR_NODE) of
	NPid when is_pid(NPid) ->
	    ok;
	{error, not_found} ->
	    ?dbg(mgr, "init: starting co_node with serial = 0", []),
	    {ok, _NewNPid}  = co_api:start_link(?MGR_NODE,  
						 [{nodeid, 0}] ++ Opts)
    end,

    process_flag(trap_exit, true),
    
    {ok, #mgr {def_nid = 0, ctx = undefined}}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request::stop |
			   {setnid, Nid::integer()} |
			   {setmode, Mode:: block | segment} |
			   {debug, TrueOrFalse::boolean()} |
			   {loop_data, Qual:: all | no_ctx},
		  From::pid(), Mgr::record()) ->
			 {reply, Reply::term(), Mgr::record()} |
			 {reply, Reply::term(), Mgr::record(), Timeout::timeout()} |
			 {noreply, Mgr::record()} |
			 {noreply, Mgr::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Reply::term(), Mgr::record()} |
			 {stop, Reason::term(), Mgr::record()}.

handle_call({set_nid,Nid}, _From, Mgr) ->
    {reply, ok, Mgr#mgr { def_nid = Nid }};
handle_call({set_mode,Mode}, _From, Mgr) ->
    {reply, ok, Mgr#mgr { def_trans_mode = Mode }};
handle_call({require,Mod}, _From, Mgr) ->
    {Reply,_DCtx,Mgr1} = load_ctx(Mod, Mgr),
    {reply, Reply, Mgr1};
handle_call({store,Nid,Index,SubInd,Value}, From, Mgr) ->
    do_store(Nid,Index,SubInd,Value, From, Mgr);
handle_call({store,Index,SubInd,Value}, From, Mgr=#mgr {def_nid = DefNid}) 
  when DefNid =/= 0 ->
    do_store(DefNid, Index, SubInd, Value, From, Mgr);
handle_call({fetch,Nid,Index,SubInd}, From, Mgr) ->
    do_fetch(Nid,Index,SubInd, From, Mgr);
handle_call({fetch,Index,SubInd}, From, Mgr=#mgr {def_nid = DefNid})
  when DefNid =/= 0 ->
    do_fetch(DefNid, Index, SubInd, From, Mgr);
handle_call({debug, TrueOrFalse}, _From, Mgr) ->
    put(dbg, TrueOrFalse),
    {reply, ok, Mgr};
handle_call({loop_data, all}, _From, Mgr) ->
    io:format("Loop data = ~p\n", [Mgr]),
    {reply, ok, Mgr};
handle_call({loop_data, no_ctx}, _From, Mgr) ->
    io:format("Loop data:\n"
	      "Default nid = ~.16.0#\n"
	      "Default transfer mode = ~p\n"
	      "Nodes ~p\n"
	      "Pids ~p\n"
	      "Ctxs ~p\n",
	      [Mgr#mgr.def_nid, Mgr#mgr.def_trans_mode,  Mgr#mgr.nodes, Mgr#mgr.pids, 
	       [Mod || {Mod, _} <-  Mgr#mgr.ctx_list]]),
    {reply, ok, Mgr};
handle_call(stop, _From, Mgr) ->
    {stop, normal, ok, Mgr};
handle_call(_Request, _From, Mgr) ->
    ?dbg(mgr, "handle_call: Unknown request ~p", [ _Request]),
    {reply, {error,bad_call}, Mgr}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), Mgr::record()) -> 
			 {noreply, Mgr::record()} |
			 {noreply, Mgr::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Mgr::record()}.

handle_cast({notify, Nid, Index, SubInd, Value}, Mgr) ->
    do_notify(Nid, Index, SubInd, Value, Mgr);
handle_cast({notify, Index, SubInd, Value}, Mgr=#mgr {def_nid = DefNid})
  when DefNid =/= 0 ->
    do_notify(DefNid, Index, SubInd, Value, Mgr);
handle_cast(_Msg, Mgr) ->
    ?dbg(mgr, "handle_cast: Unknown msg ~p", [_Msg]),
    {noreply, Mgr}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Handles 'DOWN' messages for monitored processes.
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info::term(), Mgr::record()) -> 
			 {noreply, Mgr::record()} |
			 {noreply, Mgr::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Mgr::record()}.

handle_info({'EXIT', Pid, Reason}, Mgr=#mgr {pids = PList}) ->
    ?dbg(?NAME, "handle_info: EXIT for process ~p received, reason ~p", 
	 [Pid, Reason]),
    case lists:member(Pid, PList) of
	true -> 
	    case Reason of
		normal -> do_nothing;
		_Other -> io:format("WARNING, request failed, reason ~p\n", [Reason])
	    end,
	    {noreply, Mgr#mgr {pids = PList -- [Pid]}};
	false ->
	    {noreply, Mgr}
    end;
handle_info(_Info, Mgr) ->
    ?dbg(mgr, "handle_info: Unknown info ~p", [_Info]),
    {noreply, Mgr}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, Mgr) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _Mgr) ->
   ?dbg(mgr, "terminate: reason ~p", [_Reason]),
    case co_proc:lookup(?MGR_NODE) of
	Pid when is_pid(Pid) ->
	    ?dbg(mgr, "terminate: Stopping co_node 0", []),
	    co_api:stop(?MGR_NODE);
	{error, not_found} ->
	    do_nothing
    end,
    co_proc:reg(?CO_MGR),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @spec code_change(OldVsn, Mgr, Extra) -> {ok, NewMgr}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Mgr, _Extra) ->
    ?dbg(mgr, "code_change: Old version ~p", [_OldVsn]),
    {ok, Mgr}.


%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
load_ctx(Mod, Mgr) ->
    ?dbg(mgr, "load_ctx: Loading ~p", [Mod]),
    case lists:keyfind(Mod, 1, Mgr#mgr.ctx_list) of
	false ->
	    try co_lib:load_definition(Mod) of
		{ok, DCtx} ->
		    ?dbg(mgr, "load_ctx: Loaded ~p", [Mod]),
		    List = [{Mod,DCtx}|Mgr#mgr.ctx_list],
		    {ok, DCtx, Mgr#mgr { ctx=DCtx, ctx_list = List }};
		{Error, _} ->
		    ?dbg(mgr, "load_ctx: failed loading ~p", [Mod]),
		    {Error, [], Mgr}
	    catch
		error:Reason ->
		    {{error,Reason}, [], Mgr}
	    end;
	{Mod, DCtx} ->
	    ?dbg(mgr, "load_ctx: ~p already loaded", [Mod]),
	    {ok, DCtx, Mgr#mgr { ctx = DCtx }}
    end.
    
do_store(Nid,Index,SubInd,Value,Client, 
       Mgr=#mgr {pids = PList, def_trans_mode = TransMode}) ->
    Ctx = context(Nid, Mgr),
    case translate_index(Ctx,Index,SubInd,Value) of
	{ok,{Ti,Tsi, Tv } = _T} ->
	    ?dbg(mgr, "do_store: translated  ~p", [_T]),
	    Pid = 
		spawn_request(store, 
			      [Nid, Ti, Tsi, TransMode, Tv],
			      Client,
			      {store, Nid, Index, SubInd, Value, Tv, Ctx},
			      get(dbg)),
	    {noreply, Mgr#mgr { pids = [Pid | PList] }};
	Error ->
	    ?dbg(mgr,"do_store: translation failed, error: ~p\n", [Error]),
	    {reply, Error, Mgr}
    end.
  

do_fetch(Nid,Index,SubInd, Client, 
       Mgr=#mgr {pids = PList, def_trans_mode = TransMode}) ->
    Ctx = context(Nid, Mgr),
    ?dbg(mgr, "do_fetch: translate  ~p:~p", [Index, SubInd]),
    case translate_index(Ctx,Index,SubInd,no_value) of
	{ok,{Ti,Tsi,Tv} = _T} ->
	    ?dbg(mgr, "do_fetch: translated  ~p", [_T]),
	    Pid = 
		spawn_request(fetch, 
			      [Nid, Ti, Tsi, TransMode, Tv],
			      Client,
			      {fetch, Nid, Index, SubInd, Tv, Ctx},
			      get(dbg)),
	    {noreply,  Mgr#mgr { pids = [Pid | PList] }};
	Error ->
	    ?dbg(mgr,"do_fetch: translation failed, error: ~p\n", [Error]),
	    {reply, Error, Mgr}
    end.

spawn_request(F, Args, Client, Request, Dbg) ->
    Pid = proc_lib:spawn_link(?MODULE, execute_request, 
			      [F, Args, Client, Request, Dbg]),
    ?dbg(mgr, "spawn_request: spawned  ~p", [Pid]),
    Pid.

execute_request(F, Args, Client, Request, Dbg) ->
    put(dbg, Dbg),
    ?dbg(mgr, "execute_request: F = ~p Args = ~w)", [F, Args]),
    Reply = apply(?MODULE,F,Args),
    ?dbg(mgr, "execute_request: reply  ~p", [Reply]),
    handle_reply(Reply, Client, Request).

handle_reply({ok, Value}, Client, {fetch, _Nid, _Index, _SubInd, Type, Ctx}) ->
    ?dbg(mgr,"handle_reply: Formatting ~p, type ~p", [Value, Type]),
    Reply = format_value(Value, Type, Ctx),
    gen_server:reply(Client, Reply);
handle_reply({error, ECode}, Client, _Request) ->
    gen_server:reply(Client, {error, co_sdo:decode_abort_code(ECode)});
handle_reply(Other, Client, _Request) -> %% ok ???
    ?dbg(mgr,"handle_reply: Other ~p", [Other]),
    gen_server:reply(Client, Other).

do_notify(Nid,Index,SubInd,Value, Mgr) ->
    Ctx = context(Nid, Mgr),
    case translate_index(Ctx,Index,SubInd,Value) of
	{ok,{Ti,Tsi,{Tv, Type}} = _T} ->
	    ?dbg(mgr, "do_notify: translated  ~p", [_T]),
	    try co_codec:encode(Tv, {Type, 32}) of
		Data ->
		    ?dbg(mgr,"do_notify: ~w ~p ~p ~p\n", [Nid,Ti,Tsi,Data]),
		    co_api:notify(Nid,Ti,Tsi,Data)
	    catch error:_Reason ->
		    ?dbg(mgr,"do_notify: encode failed ~w ~p ~p ~p, reason ~p\n", 
			      [Nid, Index, SubInd, Value, _Reason])
	    end;
	_Error ->
	    ?dbg(mgr,"do_notify: translation failed, error: ~p\n", [_Error]),
	    error
    end,
    {noreply, Mgr}.
    

%% try translate symbolic index and Value
translate_index(undefined,_Index,_SubInd,_Value) ->
    {error, no_context};
translate_index(_Ctx,Index,SubInd,Value) 
  when ?is_index(Index), ?is_subind(SubInd),is_integer(Value) ->
    {ok,{Index,SubInd,{Value, integer}}};
translate_index(Ctx,Index,SubInd,Value) 
  when  ?is_index(Index), ?is_subind(SubInd) ->
    Res = co_lib:entry(Index, SubInd, Ctx),
    translate_index2(Ctx, Res, Index, SubInd, Value);
translate_index(Ctx,Index,SubInd,Value) 
  when is_atom(Index);
       is_list(Index)->
    Res = co_lib:object(Index, Ctx),
    ?dbg(mgr,"translate_index: found ~p\n", [Res]),
    translate_index1(Ctx, Res, Index, SubInd, Value);
translate_index(_Ctx,_Index,_Subind,_Value) ->
    {error,argument}.

translate_index1(_Ctx, {error, _Error} = _E ,_Index,_SubInd,_Value) ->
    ?dbg(mgr,"translate_index1: not found ~p\n", [_E]),
    {error, argument};
translate_index1(Ctx, Obj,_Index,SubInd,Value) 
  when ?is_subind(SubInd);
       is_list(SubInd);
       is_atom(SubInd) ->
    Ti = Obj#objdef.index,
    Res = co_lib:entry(SubInd, Obj, Ctx), 
    ?dbg(mgr,"translate_index1: found ~p\n", [Res]),
    translate_index2(Ctx, Res, Ti, SubInd, Value).

translate_index2(_Ctx, {error, _Error} = _E, Index, SubInd, no_value) ->
    ?dbg(mgr,"translate_index2: not found ~p\n", [_E]),
    %% For fetch 
    {ok, {Index, SubInd, data}};
translate_index2(_Ctx, {error, _Error} = _E, _Index, _SubInd, _Value) ->
    ?dbg(mgr,"translate_index2: not found ~p\n", [_E]),
    {error,argument};
translate_index2(Ctx, E=#entdef {index = S}, Index, SubInd, Value) 
  when ?is_subind(SubInd) andalso not is_integer(S) ->
    %% Found entry with index as range use original sub_index
    translate_index2(Ctx, E#entdef {index = SubInd}, Index, SubInd, Value);
translate_index2(_Ctx, _E=#entdef {type = Type, index = SubInd}, Index, _S, no_value) ->
    %% For fetch 
    {ok,{Index,SubInd,{value, co_lib:encode_type(Type)}}};
translate_index2(Ctx, _E=#entdef {type = Type, index = SubInd}, Index, _S, Value) ->
    case translate_value(Type, Value, Ctx) of
	{ok,IValue} ->
	    {ok,{Index,SubInd,{value, IValue,co_lib:encode_type(Type)}}};
	error ->
	    {error,argument}
    end.

   

translate_value({enum,Base,_Id},Value,Ctx) when is_integer(Value) ->    
    translate_value(Base, Value, Ctx);
translate_value({enum,Base,Id},Value,Ctx) when is_atom(Value) ->
    case co_lib:enum_by_id(Id, Ctx) of
	error -> error;
	{ok,Enums} ->
	    case lists:keysearch(Value, 1, Enums) of
		false -> error;
		{value,{_,IValue}} ->
		    translate_value(Base, IValue, Ctx)
	    end
    end;
translate_value({bitfield,Base,_Id},Value,Ctx) when is_integer(Value) ->    
    translate_value(Base, Value, Ctx);
translate_value({bitfield,Base,Id},Value,Ctx) when is_atom(Value) ->
    case co_lib:enum_by_id(Id, Ctx) of
	error -> error;
	{ok,Enums} ->
	    case lists:keysearch(Value, 1, Enums) of
		false -> error;
		{value,{_,IValue}} ->
		    translate_value(Base, IValue, Ctx)
	    end
    end;
translate_value({bitfield,Base,Id},Value,Ctx) when is_list(Value) ->
    case co_lib:enum_by_id(Id, Ctx) of
	error -> error;
	{ok,Enums} ->
	    IValue = 
		lists:foldl(
		  fun(V, Bits) ->
			  case lists:keysearch(V, 1, Enums) of
			      false -> 0;
			      {value,{_,Val}} -> Bits bor Val
			  end
		  end, 0, Value),
	    translate_value(Base, IValue, Ctx)
    end;
translate_value(boolean, true, _)  -> {ok, 1};
translate_value(boolean, false, _) -> {ok, 0};
translate_value(Type, Value, _Ctx) when is_atom(Type), is_integer(Value) ->
    %% FIXME
    {ok, Value};
translate_value(_, _, _) ->
    error.


%% translate Node ID to dctx
context(Nid, Mgr) ->
    case lists:keysearch(Nid, #node.nid, Mgr#mgr.nodes) of
	false ->
	    Mgr#mgr.ctx;  %% use current context
	{value,N} ->
	    Mod = N#node.product,
	    case lists:keysearch(Mod, #node.nid, Mgr#mgr.ctx_list) of
		false ->
		    Mgr#mgr.ctx;  %% use current context
		{value,{_,MCtx}} ->
		    MCtx
	    end
    end.


format_value(Value, Type, DCtx) ->
    case Type of
	boolean    -> ite(Value==0, "false", "true");
	unsigned8  -> unsigned(Value,16#ff);
	unsigned16 -> unsigned(Value,16#ffff);
	unsigned24 -> unsigned(Value,16#ffffff);
	unsigned32 -> unsigned(Value,16#ffffffff);

	integer8  -> signed(Value, 16#7f);
	integer16 -> signed(Value, 16#7fff);
	integer24 -> signed(Value, 16#7fffff);
	integer32 -> signed(Value, 16#7fffffff);

	{enum,Type1,EId} ->
	    case co_lib:enum_by_id(EId, DCtx) of
		{ok,Enums} ->
		    case lists:keysearch(Value, 2, Enums) of
			false ->
			    format_value(Value, Type1, DCtx);
			{value,{Key,_}} ->
			    atom_to_list(Key)
		    end;
		error ->
		    format_value(Value, Type1, DCtx)
	    end;
	{bitfield,Type1,EId} ->
	    case co_lib:enum_by_id(EId, DCtx) of
		{ok,Enums} ->
		    Fields = bitfield(Value, Enums),
		    io_lib:format("~p", [Fields]);
		error ->
		    format_value(Value, Type1, DCtx)
	    end;
	_ ->
	    %%integer_to_list(Value) ??
	    Value
    end.

ite(true,Then,_Else) -> Then;
ite(false,_Then,Else) -> Else.

bitfield(Value,Enums) ->
    bitfield(Value,Enums,[]).

bitfield(0,_,Acc) ->
    Acc;
bitfield(Value,[{Key,Val}|Enums],Acc) ->
    if (Val band Value) == Val ->
	    bitfield(Value band (bnot Val), Enums, [Key|Acc]);
       true ->
	    bitfield(Value, Enums, Acc)
    end;
bitfield(_, [], Acc) ->
    Acc.


unsigned(V, Mask) ->
    %%integer_to_list(V band Mask). ??
    (V band Mask).

signed(V, UMask) ->
    if V band (bnot UMask) == 0 ->
	    (V band UMask);
       true ->
	    %%[$-|integer_to_list(((bnot V) band UMask)+1)] ??
	    [$-|(((bnot V) band UMask)+1)]
    end.
