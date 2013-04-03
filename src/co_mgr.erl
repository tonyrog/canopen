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
-export([fetch/6,fetch/5,fetch/4]).
-export([store/6,store/5,store/4]).

%% api when using definition files
-export([client_require/1]).
-export([client_set_nid/1]).
-export([client_set_mode/1]).
-export([client_store/4, client_store/3, client_store/2]).
-export([client_fetch/3, client_fetch/2, client_fetch/1]).
-export([client_notify/5, client_notify/4, client_notify/3]).
-export([translate/1, translate/2]).

%% gen_server callbacks
-export([init/1, 
         handle_call/3, 
         handle_cast/2, 
         handle_info/2,
	 terminate/2, 
         code_change/3]).

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
	  ctx_list =[],    %% [{mod,<ctx>}] 
	  debug           
	}).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% See {link start/1}.
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
    co_lib:debug(proplists:get_value(debug,Options,false)), 
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
	    {ok, _NewMPid} = 
		gen_server:F({local, ?CO_MGR}, ?MODULE, Options, [])
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
%% Fetch Data/Value from object specified by Index, Subind from remote CANOpen
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
-spec fetch({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  {value, Type::integer() | atom()} |
			  data,
	    TimeOut::timeout() | default) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::term()}.
		   
fetch(NodeId = {_TypeOfNid, Nid}, 
      Ix, Si, TransferMode,
      {app, Pid, Mod} = Destination,
      TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_pid(Pid),
       is_atom(Mod),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, 
			      Destination, TimeOut)
    end;
fetch(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, {value, Type}, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_atom(Type),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    fetch(NodeId, Ix, Si, TransferMode, 
	  {value, co_lib:encode_type(Type)}, TimeOut); 
fetch(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, {value, Type}, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_integer(Type),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    case co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, data, TimeOut) of
	{ok, Data} ->
	    try co_codec:decode(Data, Type) of
		{Value, _Rest} -> {ok, Value}
	    catch
		error:Error -> {error, Error}
	    end;
	Error -> Error
    end;
fetch(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, 
      data = Destination, TimeOut)  
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    co_api:fetch(?MGR_NODE, NodeId, Ix, Si, TransferMode, Destination, TimeOut).

%%--------------------------------------------------------------------
%% @doc
%% See {@link fetch/6}.
%% @end
%%--------------------------------------------------------------------
-spec fetch({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    {Ix::integer(), Si::integer()} | integer(),
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  {value, Type::integer() | atom()} |
			  data,
	    TimeOut::timeout() | default) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::term()};
	   ({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  {value, Type::integer() | atom()} |
			  data) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::term()}.
	  	   
fetch(NodeId = {_TypeOfNid, Nid}, {Ix, Si}, TransferMode, Destination, Timeout) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment) ->
    fetch(NodeId, Ix, Si, TransferMode, Destination, Timeout);
fetch(NodeId = {_TypeOfNid, Nid}, Ix, TransferMode, Destination, Timeout) 
  when is_integer(Nid), 
       is_integer(Ix),
       (TransferMode == block orelse TransferMode == segment) ->
    fetch(NodeId, Ix, 0, TransferMode, Destination, Timeout);
fetch(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, Destination)
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment) ->
    fetch(NodeId, Ix, Si, TransferMode, Destination, default).

%%--------------------------------------------------------------------
%% @doc
%% See {@link fetch/6}.
%% @end
%%--------------------------------------------------------------------
-spec fetch({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    {Ix::integer(), Si::integer()} | integer(),
	    TransferMode:: block | segment,
	    Destination:: {app, Pid::pid(), Mod::atom()} | 
			  {value, Type::integer() | atom()} |
			  data) ->
		   ok | 
		   {ok, Value::term()} | 
		   {ok, Data::binary()} |
		   {error, Reason::term()}.
		   
fetch(NodeId = {_TypeOfNid, Nid}, {Ix, Si}, TransferMode, Destination) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment) ->
    fetch(NodeId, Ix, Si, TransferMode, Destination);
fetch(NodeId = {_TypeOfNid, Nid}, Ix, TransferMode, Destination) 
  when is_integer(Nid), 
       is_integer(Ix),
       (TransferMode == block orelse TransferMode == segment) ->
    fetch(NodeId, Ix, 0, TransferMode, Destination).

%%--------------------------------------------------------------------
%% @doc
%% Stores Data/Value at object specified by Index, Subind at remote CANOpen
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
-spec store({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer() | atom()} |
		      {data, Bin::binary()},
	    TimeOut::timeout() | default) ->
		   ok | 
		   {error, Reason::term()}.

store(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, 
      {app, Pid, Mod} = Source, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_pid(Pid),
       is_atom(Mod),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    case process_info(Pid) of
	undefined -> {error, non_existing_application};
	_Info -> co_api:store(?MGR_NODE, NodeId, Ix, Si, 
			      TransferMode, Source, TimeOut)
    end;
store(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, 
      {value, Value, Type}, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_atom(Type),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
 store(NodeId, Ix, Si, TransferMode, 
       {value, Value, co_lib:encode_type(Type)}, TimeOut);
store(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, 
      {value, Value, Type}, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_integer(Type),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
    co_api:store(?MGR_NODE, NodeId, Ix, Si, TransferMode, 
		  {data, co_codec:encode(Value, Type)}, TimeOut);
store(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, 
      {data, Bin} = Source, TimeOut)
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si), 
       (TransferMode == block orelse TransferMode == segment),
       is_binary(Bin),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default)  ->
   co_api:store(?MGR_NODE, NodeId, Ix, Si, TransferMode, Source, TimeOut).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  store/6}.
%% @end
%%--------------------------------------------------------------------
-spec store({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    {Ix::integer(), Si::integer()} | integer(),
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer() | atom()} |
		      {data, Bin::binary()},
	    TimeOut::timeout() | default) ->
		   ok | 
		   {error, Reason::term()};
	   ({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    Ix::integer(), Si::integer(),
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer() | atom()} |
		      {data, Bin::binary()}) ->
		   ok | 
		   {error, Reason::term()}.

store(NodeId = {_TypeOfNid, Nid}, {Ix, Si}, TransferMode, Source, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default) ->
    store(NodeId, Ix, Si, TransferMode, Source, TimeOut);
store(NodeId = {_TypeOfNid, Nid}, Ix, TransferMode, Source, TimeOut) 
  when is_integer(Nid), 
       is_integer(Ix),
       (TransferMode == block orelse TransferMode == segment),
       ((is_integer(TimeOut) andalso TimeOut > 0) orelse TimeOut == default) ->
    store(NodeId, Ix, 0, TransferMode, Source, TimeOut);
store(NodeId = {_TypeOfNid, Nid}, Ix, Si, TransferMode, Source)
  when is_integer(Nid), 
       is_integer(Ix),
       (TransferMode == block orelse TransferMode == segment) ->
    store(NodeId, Ix, Si, TransferMode, Source, default).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  store/6}.
%% @end
%%--------------------------------------------------------------------
-spec store({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    {Ix::integer(), Si::integer()} | integer(),
	    TransferMode:: block | segment,
	    Source:: {app, Pid::pid(), Mod::atom()} | 
		      {value, Value::term(), Type::integer() | atom()} |
		      {data, Bin::binary()}) ->
		   ok | 
		   {error, Reason::term()}.

store(NodeId = {_TypeOfNid, Nid}, {Ix, Si}, TransferMode, Source) 
  when is_integer(Nid), 
       is_integer(Ix), 
       is_integer(Si),
       (TransferMode == block orelse TransferMode == segment) ->
    store(NodeId, Ix, Si, TransferMode, Source);
store(NodeId = {_TypeOfNid, Nid}, Ix, TransferMode, Source) 
  when is_integer(Nid), 
       is_integer(Ix),
       (TransferMode == block orelse TransferMode == segment) ->
    store(NodeId, Ix, 0, TransferMode, Source).

%% API used by co_script
%%--------------------------------------------------------------------
%% @doc
%% Installs Module definitions in the manager.
%% @end
%%--------------------------------------------------------------------
-spec client_require(Mod::atom()) ->
			    ok | {error, Reason::term()}.

client_require(Mod) 
  when is_atom(Mod) ->
    ?dbg(mgr, "client_require: module ~p", [Mod]),
    gen_server:call(?CO_MGR, {require, Mod}).


%%--------------------------------------------------------------------
%% @doc
%% Set the default nodeid - for short interface.
%% @end
%%--------------------------------------------------------------------
-spec client_set_nid({TypeOfNid::nodeid | xnodeid, Nid::integer()}) ->
			    ok | {error, Reason::term()}.

client_set_nid({xnodeid,Nid} = NodeId) 
  when is_integer(Nid) andalso Nid < 2#1000000000000000000000000 -> %% Max 24 bit
    gen_server:call(?CO_MGR, {set_nid, NodeId});
client_set_nid({nodeid,Nid} = NodeId) 
  when is_integer(Nid) andalso Nid < 127 -> 
    gen_server:call(?CO_MGR, {set_nid, NodeId}).


%%--------------------------------------------------------------------
%% @doc
%% Set the default transfer mode.
%% @end
%%--------------------------------------------------------------------
-spec client_set_mode(Mod:: block | segment) ->
			    ok | {error, Reason::term()}.

client_set_mode(Mode) 
  when Mode == block;
       Mode == segment ->
    gen_server:call(?CO_MGR, {set_mode, Mode}).

%%--------------------------------------------------------------------
%% @doc
%% Stores Value at object specified by Index, Subind at remote CANOpen
%% node identified by NodeId.<br/>
%% Atoms defined in the loaded modules can be used instead of integers
%% for Index and SubInd.
%% @end
%%--------------------------------------------------------------------
-spec client_store({TypeOfNid::nodeid | xnodeid, Nid::integer()},
		   Index::integer() | atom(), 
		   SubInd::integer() | atom(), 
		   Value::term()) ->
			    ok | {error, Reason::term()}.

client_store(Nid, Index, SubInd, Value) ->
    gen_server:call(?CO_MGR, {store, Nid, Index, SubInd, Value}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_store/4}.
%% @end
%%--------------------------------------------------------------------
-spec client_store(Index::integer() | atom(), 
		   SubInd::integer() | atom(), 
		   Value::term()) ->
			    ok | {error, Reason::term()}.

client_store(Index, SubInd, Value) ->
    gen_server:call(?CO_MGR, {store, Index, SubInd, Value}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_store4}.
%% SubInd = 0.
%% @end
%%--------------------------------------------------------------------
-spec client_store(Index::integer() | atom(), 
		   Value::term()) ->
			    ok | {error, Reason::term()}.

client_store(Index, Value) ->
    gen_server:call(?CO_MGR, {store, Index, 0, Value}).


%%--------------------------------------------------------------------
%% @doc
%% Fetch Value for object specified by Index, Subind from remote CANOpen
%% node identified by NodeId.<br/>
%% TransferMode controls whether block or segment transfer is used between
%% the CANOpen nodes.<br/>
%% Atoms defined in the loaded modules can be used instead of integers
%% for Index and SubInd.
%% @end
%%--------------------------------------------------------------------
-spec client_fetch({TypeOfNid::nodeid | xnodeid, Nid::integer()},
		   Index::integer() | atom(),
		   SubInd::integer() | atom()) -> 
			  Value::term() | {error, Reason::term()}.

client_fetch(Nid, Index, SubInd) ->
    gen_server:call(?CO_MGR, {fetch, Nid, Index, SubInd}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_fetch/3}.
%% @end
%%--------------------------------------------------------------------
-spec client_fetch(Index::integer() | atom(),
		   SubInd::integer() | atom()) -> 
			  Value::term() | {error, Reason::term()}.

client_fetch(Index, SubInd)  ->
    gen_server:call(?CO_MGR, {fetch, Index, SubInd}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_fetch/3}.
%% SubInd = 0.
%% @end
%%--------------------------------------------------------------------
-spec client_fetch(Index::integer() | atom()) ->
			  Value::term() | {error, Reason::term()}.

client_fetch(Index)  ->
    gen_server:call(?CO_MGR, {fetch, Index, 0}).

%%--------------------------------------------------------------------
%% @doc
%% Send notification of with CobId constructed from Func and NodeId. <br/>
%% Atoms defined in the loaded modules can be used instead of integers
%% for Index and SubInd.
%% See {@link co_api:notify/4}.
%% @end
%%--------------------------------------------------------------------
-spec client_notify({TypeOfNid::nodeid | xnodeid, Nid::integer()},
		    Func::atom(),
		    Index::integer() | atom(),
		    SubInd::integer() | atom(), 
		    Value::term()) ->
			   ok | {error, Reason::term()}.

client_notify(Nid, Func, Index, Subind, Value) ->
    gen_server:cast(?CO_MGR, {notify, Nid, Func, Index, Subind, Value}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_notify/4}.
%% @end
%%--------------------------------------------------------------------
-spec client_notify(Func::atom(),
		    Index::integer() | atom(),
		    SubInd::integer() | atom(), 
		    Value::term()) ->
			   ok | {error, Reason::term()}.

client_notify(Func, Index, Subind, Value) ->
    gen_server:cast(?CO_MGR, {notify, Func, Index, Subind, Value}).
  
%%--------------------------------------------------------------------
%% @doc
%% See {@link  client_notify/4}.
%% SubInd = 0.
%% @end
%%--------------------------------------------------------------------
-spec client_notify(Func::atom(),
		    Index::integer() | atom(), 
		    Value::term()) ->
			   ok | {error, Reason::term()}.

client_notify(Func, Index, Value) ->
    gen_server:cast(?CO_MGR, {notify, Func, Index, 0, Value}).

%%--------------------------------------------------------------------
%% @doc
%% Looks up index in def files.
%% @end
%%--------------------------------------------------------------------
-spec translate(Index::atom(), SubInd::atom()) -> 
		       {IndexI::integer(), SubIndI::integer()} | 
		       {error, Reason::term()}.

translate(Index, SubInd) 
  when is_atom(Index), is_atom(SubInd) ->
    gen_server:call(?CO_MGR, {translate, Index, SubInd}).

%%--------------------------------------------------------------------
%% @doc
%% See {@link  translate/2}.
%% SubInd = 0.
%% @end
%%--------------------------------------------------------------------
-spec translate(Index::atom()) ->
			  IndexI::integer() | 
				  {error, Reason::term()}.

translate(Index) 
  when is_atom(Index) ->
    gen_server:call(?CO_MGR, {translate, Index, 0}).

%% For testing
%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?CO_MGR, {debug, TrueOrFalse}).

%% @private
loop_data(Qual) when Qual == no_ctx ->
    gen_server:call(?CO_MGR, {loop_data, Qual}).
%% @private
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
		  {ok, Mgr::#mgr{}}.

init(Opts) ->
    %% Trace output enable/disable
    Dbg = proplists:get_value(debug,Opts,false),
    co_lib:debug(Dbg), 

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
    
    {ok, #mgr {def_nid = 0, ctx = undefined, debug = Dbg}}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	stop |
	{setnid, {TypeOfNid::nodeid | xnodeid, Nid::integer()}} |
	{setmode, Mode:: block | segment} |
	{store, {TypeOfNid::nodeid | xnodeid, Nid::integer()},
	 Ix::integer(), Si::integer(), Value::term()} |
	{store, Ix::integer(), Si::integer(), Value::term()} |
	{fetch, {TypeOfNid::nodeid | xnodeid, Nid::integer()},
	 Ix::integer() | atom(), Si::integer() | atom()} |
	{fetch, Ix::integer(), Si::integer()} |
	{translate, Ix::atom(), Si::atom()} |
	{debug, TrueOrFalse::boolean()} |
	{loop_data, Qual:: all | no_ctx}.

-spec handle_call(Request::call_request(),
		  From::pid(), Mgr::#mgr{}) ->
			 {reply, Reply::term(), Mgr::#mgr{}} |
			 {noreply, Mgr::#mgr{}} |
			 {stop, Reason::term(), Reply::term(), Mgr::#mgr{}}.

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

handle_call({translate,Index,SubInd}, _From, Mgr=#mgr {def_nid = DefNid})
  when DefNid =/= 0 ->
    do_translate(DefNid, Index, SubInd, Mgr);

handle_call({debug, TrueOrFalse}, _From, Mgr) ->
    co_lib:debug(TrueOrFalse),
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
-type cast_msg()::
	{notify, {TypeOfNid::nodeid | xnodeid, Nid::integer()},
	 Func::atom(), Ix::integer(), Si::integer(), Value::term()} |
	{notify, Func::atom(), Ix::integer(), Si::integer(), Value::term()}.

-spec handle_cast(Msg::cast_msg(), Mgr::#mgr{}) -> 
			 {noreply, Mgr::#mgr{}} |
			 {noreply, Mgr::#mgr{}, Timeout::timeout()} |
			 {stop, Reason::term(), Mgr::#mgr{}}.

handle_cast({notify, Nid, Func, Index, SubInd, Value}, Mgr) ->
    do_notify(Nid, Func, Index, SubInd, Value, Mgr);
handle_cast({notify, Func, Index, SubInd, Value}, Mgr=#mgr {def_nid = DefNid})
  when DefNid =/= 0 ->
    do_notify(DefNid, Func, Index, SubInd, Value, Mgr);

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
-type info()::
	{'EXIT', Pid::pid(), Reason::term()} |
	term().

-spec handle_info(Info::info(), Mgr::#mgr{}) -> 
			 {noreply, Mgr::#mgr{}}.

handle_info({'EXIT', Pid, Reason}, Mgr=#mgr {pids = PList}) ->
    ?dbg(mgr, "handle_info: EXIT for process ~p received, reason ~p", 
	 [Pid, Reason]),
    case lists:member(Pid, PList) of
	true -> 
	    case Reason of
		normal -> 
		    do_nothing;
		_Other -> 
		    error_logger:warning_msg("Request failed, reason ~p\n", 
					     [Reason])
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
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Mgr::#mgr{}) -> 
		       no_return().

terminate(_Reason, _Mgr) ->
   ?dbg(mgr, "terminate: reason ~p", [_Reason]),
    case co_proc:lookup(?MGR_NODE) of
	Pid when is_pid(Pid) ->
	    ?dbg(mgr, "terminate: Stopping co_node 0", []),
	    co_api:stop(?MGR_NODE);
	{error, not_found} ->
	    do_nothing
    end,
    co_proc:unreg(?CO_MGR),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Mgr::#mgr{}, Extra::term()) -> 
			 {ok, NewMgr::#mgr{}}.

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
       Mgr=#mgr {pids = PList, def_trans_mode = TransMode, debug = Dbg}) ->
    Ctx = context(Nid, Mgr),
    case translate_index(Ctx,Index,SubInd,Value) of
	{ok,{Ti,Tsi, Tv } = _T} ->
	    ?dbg(mgr, "do_store: translated  ~p", [_T]),
	    Pid = 
		spawn_request(store, 
			      [Nid, Ti, Tsi, TransMode, Tv],
			      Client,
			      {store, Nid, Index, SubInd, Value, Tv, Ctx},
			      Dbg),
	    {noreply, Mgr#mgr { pids = [Pid | PList] }};
	Error ->
	    ?dbg(mgr,"do_store: translation failed, error: ~p\n", [Error]),
	    {reply, Error, Mgr}
    end.
  

do_fetch(Nid,Index,SubInd, Client, 
       Mgr=#mgr {pids = PList, def_trans_mode = TransMode, debug = Dbg}) ->
    Ctx = context(Nid, Mgr),
    ?dbg(mgr, "do_fetch: translate ~p:~p", [Index, SubInd]),
    case translate_index(Ctx,Index,SubInd,no_value) of
	{ok,{Ti,Tsi,Tv} = _T} ->
	    ?dbg(mgr, "do_fetch: translated  ~p", [_T]),
	    Pid = 
		spawn_request(fetch, 
			      [Nid, Ti, Tsi, TransMode, Tv],
			      Client,
			      {fetch, Nid, Index, SubInd, Tv, Ctx},
			      Dbg),
	    {noreply,  Mgr#mgr { pids = [Pid | PList] }};
	Error ->
	    ?dbg(mgr,"do_fetch: translation failed, error: ~p\n", [Error]),
	    {reply, Error, Mgr}
    end.

do_translate(Nid,Index,SubInd, Mgr) ->
    Ctx = context(Nid, Mgr),
    ?dbg(mgr, "do_translate: translate ~p:~p", [Index, SubInd]),
    case translate_index(Ctx,Index,SubInd,no_value) of
	{ok,{Ti,Tsi,_Tv} = _T} ->
	    ?dbg(mgr, "do_translate: translated  ~p", [_T]),
	    {reply, {Ti,Tsi}, Mgr};
	Error ->
	    ?dbg(mgr,"do_translate: translation failed, error: ~p\n", [Error]),
	    {reply, Error, Mgr}
    end.

spawn_request(F, Args, Client, Request, Dbg) ->
    Pid = proc_lib:spawn_link(?MODULE, execute_request, 
			      [F, Args, Client, Request, Dbg]),
    ?dbg(mgr, "spawn_request: spawned  ~p", [Pid]),
    Pid.

%% @private
execute_request(F, Args, Client, Request, Dbg) ->
    co_lib:debug(Dbg),
    ?dbg(mgr, "execute_request: F = ~p Args = ~w)", [F, Args]),
    Reply = apply(?MODULE,F,Args),
    ?dbg(mgr, "execute_request: reply  ~p", [Reply]),
    handle_reply(Reply, Client, Request).

handle_reply({ok, Value}, Client, 
	     {fetch, _Nid, _Index, _SubInd, {value, Type}, Ctx}) ->
    Reply = format_value(Value, co_lib:decode_type(Type), Ctx),
    ?dbg(mgr,"handle_reply: Format ~p, type ~p => ~p", [Value, Type, Reply]),
    gen_server:reply(Client, Reply);
handle_reply({ok, Data}, Client, 
	     {fetch, _Nid, _Index, _SubInd, data, _Ctx}) ->
    ?dbg(mgr,"handle_reply: Formatting ~p, not possible", [Data]),
    gen_server:reply(Client, Data);
handle_reply({error, ECode}, Client, _Request) ->
    gen_server:reply(Client, {error, co_sdo:decode_abort_code(ECode)});
handle_reply(ok, Client, _Request) -> 
    ?dbg(mgr,"handle_reply: ok", []),
    gen_server:reply(Client, ok);
handle_reply(Other, Client, _Request) -> %% ok ???
    ?dbg(mgr,"handle_reply: Other ~p", [Other]),
    gen_server:reply(Client, Other).

do_notify(Nid, Func,Index,SubInd, Value, Mgr) ->
    Ctx = context(Nid, Mgr),
    case translate_index(Ctx,Index,SubInd,Value) of
	{ok,{Ti,Tsi,{value, Tv, Type}} = _T} ->
	    ?dbg(mgr, "do_notify: translated  ~p", [_T]),
	    try co_codec:encode(Tv, {Type, 32}) of
		Data ->
		    ?dbg(mgr,"do_notify: ~w ~w ~.16.0#:~w ~w\n", [Nid,Func,Ti,Tsi,Data]),
		    co_api:notify_from(Nid,Func,Ti,Tsi,Data)
	    catch error:_Reason ->
		    ?dbg(mgr,"do_notify: encode failed ~w ~w ~.16.0#~w ~w, reason ~p\n", 
			      [Nid, Func, Index, SubInd, Value, _Reason])
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
    {ok,{Index,SubInd,{value, Value, integer}}};
translate_index(Ctx,Index,SubInd,Value) 
  when  ?is_index(Index), ?is_subind(SubInd) ->
    Res = co_lib:entry(Index, SubInd, Ctx),
    translate_index2(Ctx, Res, Index, SubInd, Value);
translate_index(Ctx,Index,SubInd,Value) 
  when is_atom(Index);
       is_list(Index) ->
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
    ?dbg(mgr,"translate_index2: found entry with index as range use "
	 "original sub_index",[]),
    translate_index2(Ctx, E#entdef {index = SubInd}, Index, SubInd, Value);
translate_index2(_Ctx, _E=#entdef {type = Type, index = SubInd}, Index, _S, 
		 no_value) ->
    ?dbg(mgr,"translate_index2: for fetch, found entry, type ~p ",[Type]),
    {ok,{Index,SubInd,{value, co_lib:encode_type(Type)}}};
translate_index2(Ctx, _E=#entdef {type = Type, index = SubInd}, Index, _S, 
		 Value) ->
    ?dbg(mgr,"translate_index2: found entry, type ~p, value ~p ",
	 [Type, Value]),
    case translate_value(Type, Value, Ctx) of
	{ok,TValue} ->
	    ?dbg(mgr,"translate_index2: translated value ~p ", [TValue]),
	    {ok,{Index,SubInd,{value, TValue, co_lib:encode_type(Type)}}};
	error ->
	    {error,argument}
    end.

   

translate_value({enum,Base,_Id},Value,Ctx) when is_integer(Value) ->    
    translate_value(Base, Value, Ctx);
translate_value({enum,Base,Id},Value,Ctx) when is_atom(Value) ->
    case co_lib:enum_by_id(Id, Ctx) of
	{error, _E} -> error;
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
	{error, _E} -> error;
	{ok,Enums} ->
	    case lists:keysearch(Value, 1, Enums) of
		false -> error;
		{value,{_,IValue}} ->
		    translate_value(Base, IValue, Ctx)
	    end
    end;
translate_value({bitfield,Base,Id},Value,Ctx) when is_list(Value) ->
    case co_lib:enum_by_id(Id, Ctx) of
	{error, _E} -> error;
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


format_value(Value, Type, _DCtx) ->
   ?dbg(mgr,"format_value: Formatting ~p, type ~p", [Value, Type]),
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

	_ ->
	    %% integer_to_list(Value)
	    Value
    end.

ite(true,Then,_Else) -> Then;
ite(false,_Then,Else) -> Else.

%% To be done ??
%% output_value(Value, Type, DCtx) ->
%%     case Type of
%% 	{enum,Type1,EId} ->
%% 	    case co_lib:enum_by_id(EId, DCtx) of
%% 		{ok,Enums} ->
%% 		    case lists:keysearch(Value, 2, Enums) of
%% 			false ->
%% 			    format_value(Value, Type1, DCtx);
%% 			{value,{Key,_}} ->
%% 			    atom_to_list(Key)
%% 		    end;
%% 		{error, _E} ->
%% 		    format_value(Value, Type1, DCtx)
%% 	    end;
%% 	{bitfield,Type1,EId} ->
%% 	    case co_lib:enum_by_id(EId, DCtx) of
%% 		{ok,Enums} ->
%% 		    Fields = bitfield(Value, Enums),
%% 		    io_lib:format("~p", [Fields]);
%% 		{error, _E} ->
%% 		    format_value(Value, Type1, DCtx)
%% 	    end.

%% bitfield(Value,Enums) ->
%%     bitfield(Value,Enums,[]).

%% bitfield(0,_,Acc) ->
%%     Acc;
%% bitfield(Value,[{Key,Val}|Enums],Acc) ->
%%     if (Val band Value) == Val ->
%% 	    bitfield(Value band (bnot Val), Enums, [Key|Acc]);
%%        true ->
%% 	    bitfield(Value, Enums, Acc)
%%     end;
%% bitfield(_, [], Acc) ->
%%     Acc.


unsigned(V, Mask) ->
    %%integer_to_list(V band Mask).
    (V band Mask).

signed(V, UMask) ->
    if V band (bnot UMask) == 0 ->
	    (V band UMask);
       true ->
	    %%[$-|integer_to_list(((bnot V) band UMask)+1)]
	    (((bnot V) band UMask)+1)
    end.
