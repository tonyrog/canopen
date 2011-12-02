%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%% File    : co_node.erl
%%% Description : can_node
%%%
%%% Created : 10 Jan 2008 
%%% @end
%%%-------------------------------------------------------------------
-module(co_node).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("co_app.hrl").

%% API
-export([start_link/1, stop/1]).
-export([attach/1, detach/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

%% Application interface
-export([subscribe/2, unsubscribe/2]).
-export([reserve/3, unreserve/2]).
-export([my_subscriptions/1, my_subscriptions/2]).
-export([my_reservations/1, my_reservations/2]).
-export([all_subscribers/1, all_subscribers/2]).
-export([all_reservers/1, reserver/2]).
-export([notify/3, notify/4]). %% To send MPOs

%% CANopen application internal
-export([add_entry/2, get_entry/2]).
-export([load_dict/2]).
-export([set/3, set/4, value/2]).
-export([store/5, fetch/4]).
-export([store_block/5, fetch_block/4]).
-export([subscribers/2]).
-export([reserver_with_module/2]).
-export([tpdo_mapping/2, rpdo_mapping/2]).

%% Debug interface
-export([dump/1]).
-export([change_session_timeout/2]).

-import(lists, [foreach/2, reverse/1, seq/2, map/2, foldl/3]).

-ifdef(debug).
-define(dbg(Fmt,As), io:format(Fmt, As)).
-else.
-define(dbg(Fmt, As), ok).
-endif.

-define(COBID_TO_CANID(ID),
	if ?is_cobid_extended((ID)) ->
		((ID) band ?COBID_ENTRY_ID_MASK) bor ?CAN_EFF_FLAG;
	   true ->
		((ID) band ?CAN_SFF_MASK)
	end).

-define(CANID_TO_COBID(ID),
	if ?is_can_id_eff((ID)) ->
		((ID) band ?CAN_EFF_MASK) bor ?COBID_ENTRY_EXTENDED;
	   true ->
		((ID) band ?CAN_SFF_MASK)
	end).
	

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @spec start_links(Args) -> {ok,Pid} | ignore | {error,Error}
%%
%%   Args = [{serial, Serial}, {options, Opts}]
%%   Opts = {vendor, VendorID} |
%%          extended |                  
%%          {time_stamp,  timeout()} |  
%%          {sdo_timeout, timeout()} |  
%%          {blk_timeout, timeout()} |  
%%          {pst, integer()} |          
%%          {max_blksize, integer()} |  
%%          {use_crc, boolean()}        
%%
%% @doc
%% Description: Starts the server.
%%
%% Options: 
%%          extended - use extended (29-bit) ID <br/>
%%          {time_stamp,  timeout()} - ( 60000 )  1m <br/>
%%          {sdo_timeout, timeout()} - ( 1000 ) <br/>
%%          {blk_timeout, timeout()} - ( 500 ) <br/>
%%          {pst, integer()}         - ( 16 ) <br/>
%%          {max_blksize, integer()} - ( 74 = 518 bytes) <br/>
%%          {use_crc, boolean()}     - use crc for block (true) <br/>
%%         
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    ?dbg("~p: start_link: Args = ~p\n", [?MODULE, Args]),
        
    Serial = proplists:get_value(serial, Args, 0),
    Opts = proplists:get_value(options, Args, []),

    S = serial(Serial),
    NodeId = 
	case proplists:get_value(extended,Opts,false) of
	     false -> S bsr 8;
	     true  -> (S bsr 8) bor ?COBID_ENTRY_EXTENDED
	 end,

    Name = name(Opts, S),
    ?dbg("~p: Starting co_node with Name = ~p, Serial = ~.16#, NodeId = ~.16#\n",
	 [?MODULE, Name, S, NodeId]),
    gen_server:start({local, Name}, ?MODULE, [S,NodeId,Name,Opts], []).

%%
%% Get serial number, accepts both string and number
%%

serial(Serial) when is_integer(Serial) ->
    Serial band 16#FFFFFFFF;
serial(_Serial) ->
    erlang:error(badarg).
    
name(Opts, Serial) ->
    case proplists:lookup(name, Opts) of
	{name,Name} when is_atom(Name) ->
	    Name;
	none ->
	    list_to_atom(co_lib:serial_to_string(Serial))
    end.

%%--------------------------------------------------------------------
%% @spec stop(Serial) -> ok | {error, Error}
%%
%% @doc
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop(Serial) ->
    gen_server:call(serial_to_pid(Serial), stop).

%%--------------------------------------------------------------------
%% @spec attach(Serial) -> ok | {error, Error}
%%
%% @doc
%% Attches the calling process to the CANnode Serial.
%%
%% @end
%%--------------------------------------------------------------------
attach(Serial) ->
    gen_server:call(serial_to_pid(Serial), {attach, self()}).

%%--------------------------------------------------------------------
%% @spec detach(Serial) -> ok | {error, Error}
%%
%% @doc
%% Detaches the calling process from the CANnode Serial.
%%
%% @end
%%--------------------------------------------------------------------
detach(Serial) ->
    gen_server:call(serial_to_pid(Serial), {detach, self()}).

%%--------------------------------------------------------------------
%% @spec subscribe(Serial, Index) -> ok | {error, Error}
%%
%% @doc
%% Adds a subscription to changes of the Dictionary Object in position Index.
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
subscribe(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {subscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @spec unsubscribe(Serial, Index) -> ok | {error, Error}
%%
%% @doc
%% Removes a subscription to changes of the Dictionary Object in position Index.
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
unsubscribe(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {unsubscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @spec my_subscriptions(Serial, Pid) -> [Index] | {error, Error}
%%
%% @doc
%% Returns the Indexes for which Pid has subscriptions.
%%
%% @end
%%--------------------------------------------------------------------
my_subscriptions(Serial, Pid) ->
    gen_server:call(serial_to_pid(Serial), {subscriptions, Pid}).

%%--------------------------------------------------------------------
%% @spec my_subscriptions(Serial) -> [Index] | {error, Error}
%%
%% @doc
%% Returns the Indexes for which the calling process has subscriptions.
%%
%% @end
%%--------------------------------------------------------------------
my_subscriptions(Serial) ->
    gen_server:call(serial_to_pid(Serial), {subscriptions, self()}).

%%--------------------------------------------------------------------
%% @spec all_subscribers(Serial) -> [Pid] | {error, Error}
%%
%% @doc
%% Returns the Pids that subscribes to any Index.
%%
%% @end
%%--------------------------------------------------------------------
all_subscribers(Serial) ->
    gen_server:call(serial_to_pid(Serial), {subscribers}).

%%--------------------------------------------------------------------
%% @spec all_subscribers(Serial, Ix) -> [Pid] | {error, Error}
%%
%% @doc
%% Returns the Pids that subscribes to Index.
%%
%% @end
%%--------------------------------------------------------------------
all_subscribers(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {subscribers, Ix}).

%%--------------------------------------------------------------------
%% @spec reserve(Serial, Index, Module) -> ok | {error, Error}
%%
%% @doc
%% Adds a reservation to an index.
%% Module:get_entry will be called if needed.
%% Index can also be a range {Index1, Index2}.
%%
%% @end
%%--------------------------------------------------------------------
reserve(Serial, Ix, Module) ->
    gen_server:call(serial_to_pid(Serial), {reserve, Ix, Module, self()}).

%%--------------------------------------------------------------------
%% @spec unreserve(Serial, Index) -> ok | {error, Error}
%%
%% @doc
%% Removes a reservation to changes of the Dictionary Object in position Index.
%% Index can also be a range {Index1, Index2}.
%%
%% @end
%%--------------------------------------------------------------------
unreserve(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {unreserve, Ix, self()}).

%%--------------------------------------------------------------------
%% @spec my_reservations(Serial, Pid) -> [Index] | {error, Error}
%%
%% @doc
%% Returns the Indexes for which Pid has reservations.
%%
%% @end
%%--------------------------------------------------------------------
my_reservations(Serial, Pid) ->
    gen_server:call(serial_to_pid(Serial), {reservations, Pid}).

%%--------------------------------------------------------------------
%% @spec my_reservations(Serial) -> [Index] | {error, Error}
%%
%% @doc
%% Returns the Indexes for which the calling process has reservations.
%%
%% @end
%%--------------------------------------------------------------------
my_reservations(Serial) ->
    gen_server:call(serial_to_pid(Serial), {reservations, self()}).

%%--------------------------------------------------------------------
%% @spec all_reservers(Serial) -> [Pid] | {error, Error}
%%
%% @doc
%% Returns the Pids that has reserved any index.
%%
%% @end
%%--------------------------------------------------------------------
all_reservers(Serial) ->
    gen_server:call(serial_to_pid(Serial), {reservers}).

%%--------------------------------------------------------------------
%% @spec reserver(Serial, Ix) -> [Pid] | {error, Error}
%%
%% @doc
%% Returns the Pid that has reserved index if any.
%%
%% @end
%%--------------------------------------------------------------------
reserver(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {reserver, Ix}).

%%--------------------------------------------------------------------
%% @spec add_entry(Serial, Entry) -> ok | {error, Error}
%%
%% @doc
%% Adds Entry to the Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
add_entry(Serial, Ent) ->
    gen_server:call(serial_to_pid(Serial), {add_entry, Ent}).

%%--------------------------------------------------------------------
%% @spec get_entry(Serial, Index) -> ok | {error, Error}
%%
%% @doc
%% Gets the Entry at Index in Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
get_entry(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {get_entry,Ix}).

%%--------------------------------------------------------------------
%% @spec load_dict(Serial, File) -> ok | {error, Error}
%%
%% @doc
%% Loads a new Object Dictionary from File.
%%
%% @end
%%-------------------------------------------------------------------
load_dict(Serial, File) ->
    gen_server:call(serial_to_pid(Serial), {load_dict, File}).
    

%%--------------------------------------------------------------------
%% @spec set(Serial, Index, Value) -> ok | {error, Error}
%%
%% @doc
%% Sets Index to Value.
%%
%% @end
%%--------------------------------------------------------------------
set(Serial, Ix, Value) when ?is_index(Ix) ->
    gen_server:call(serial_to_pid(Serial), {set,Ix,0,Value}).
set(Serial, Ix, Si, Value) when ?is_index(Ix), ?is_subind(Si) ->
    gen_server:call(serial_to_pid(Serial), {set,Ix,Si,Value}).    

%% Set raw value (used to update internal read only tables etc)
direct_set(Serial, Ix, Si, Value) when ?is_index(Ix), ?is_subind(Si) ->
    gen_server:call(serial_to_pid(Serial), {direct_set,Ix,Si,Value}).
direct_set(Serial, Ix, Value) when ?is_index(Ix) ->
    gen_server:call(serial_to_pid(Serial), {direct_set,Ix,0,Value}).

%%--------------------------------------------------------------------
%% @spec value(Serial, Index) -> Value | {error, Error}
%%
%% @doc
%% Gets Value for Index.
%%
%% @end
%%--------------------------------------------------------------------
value(Serial, Ix) ->
    gen_server:call(serial_to_pid(Serial), {value,Ix}).

%% 
%% Note on COBID for SDO service
%%
%% The manager may have a IX_SDO_SERVER list (1200 - 127F)
%% Then look there:
%% If not then check the COBID.
%% if COBID has the form of:
%%    0000-xxxxxxx, assume 7bit-NodeID
%% if COBID has the form of:
%%    0010000-xxxxxxxxxxxxxxxxxxxxxxxxx, assume 25bit-NodeID
%% If COBID is either a NodeID  (7-bit or 29-bit25-bit)
%% 
%%

%%--------------------------------------------------------------------
%% @spec store(Serial, CobId, Index, SubInd, Value) -> noreply | {error, Error}
%%
%% @doc
%% Starts a store session to store Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
store(Serial, COBID, IX, SI, Value) 
  when ?is_index(IX), ?is_subind(SI), is_binary(Value) ->
    gen_server:call(serial_to_pid(Serial), {store,false,COBID,IX,SI,Value}).

%%--------------------------------------------------------------------
%% @spec store_block(Serial, CobId, Index, SubInd, Value) -> noreply | {error, Error}
%%
%% @doc
%% Starts a store session to store Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
store_block(Serial, COBID, IX, SI, Value) 
  when ?is_index(IX), ?is_subind(SI), is_binary(Value) ->
    gen_server:call(serial_to_pid(Serial), {store,true,COBID,IX,SI,Value}).

%%--------------------------------------------------------------------
%% @spec fetch(Serial, CobId, Index, SubInd) -> noreply | {error, Error}
%%
%% @doc
%% Starts a fetch session to fetch Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
fetch(Serial, COBID, IX, SI)
  when ?is_index(IX), ?is_subind(SI) ->
    gen_server:call(serial_to_pid(Serial), {fetch,false,COBID,IX,SI}).

%%--------------------------------------------------------------------
%% @spec fetch_block(Serial, CobId, Index, SubInd) -> noreply | {error, Error}
%%
%% @doc
%% Starts a fetch session to fetch Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
fetch_block(Serial, COBID, IX, SI)
  when ?is_index(IX), ?is_subind(SI) ->
    gen_server:call(serial_to_pid(Serial), {fetch,true,COBID,IX,SI}).


%%--------------------------------------------------------------------
%% @spec dump(Serial) -> ok | {error, Error}
%%
%% @doc
%% Dumps the loop data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
dump(Serial) ->
    gen_server:call(serial_to_pid(Serial), dump).

%%--------------------------------------------------------------------
%% @spec change_session_timeout(Serial, NewTimeout::integer()) -> ok | {error, Error}
%%
%% @doc
%% Changes the session time out. (For testing)
%%
%% @end
%%--------------------------------------------------------------------
change_session_timeout(Serial, NewTimeout) ->
    gen_server:call(serial_to_pid(Serial), {change_session_timeout, NewTimeout}).

%% convert a node serial name to a local name
serial_to_pid(Sn) when is_integer(Sn) ->
    list_to_atom(co_lib:serial_to_string(Sn));
serial_to_pid(Serial) when is_list(Serial) ->
    serial_to_pid(co_lib:string_to_serial(Serial));
serial_to_pid(Pid) when is_pid(Pid); is_atom(Pid) ->
    Pid.




%%--------------------------------------------------------------------
%% @spec notify(Nid, Index, Value) -> ok | {error, Error}
%%
%% @doc
%% Send notification (from Nid). <br/>
%% SubInd is set to 0.<br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
notify(Nid,Index,Value) ->
    notify(Nid,Index,0,Value).

%%--------------------------------------------------------------------
%% @spec notify(Nid, Index, SubInd, Value) -> ok | {error, Error}
%%
%% @doc
%% Send notification (from Nid). <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
notify(Nid,Index,Subind,Value) ->
    io:format("~p: notify: Nid = ~.16#, Index = ~7.16.0#:~w, Value = ~8.16.0B\n",
	      [self(), Nid, Index, Subind, Value]),

    if ?is_nodeid_extended(Nid) ->
	    ?dbg("~p: notify: Nid ~.16# is extended\n",[self(), Nid]),
	    CobId = ?XCOB_ID(?PDO1_TX, Nid);
	true ->
	    ?dbg("~p: notify: Nid ~.16# is not extended\n",[self(), Nid]),
	    CobId = ?COB_ID(?PDO1_TX, Nid)
    end,
    FrameID = ?COBID_TO_CANID(CobId),
    Frame = #can_frame { id=FrameID, len=0, 
			 data=(<<16#80,Index:16/little,Subind:8,Value:32/little>>) },
    ?dbg("~p: notify: Sending frame ~p from Nid = ~.16# (CobId = ~.16#, CanId = ~.16#)\n",
	 [self(), Frame, Nid, CobId, FrameID]),
    can:send(Frame).

%%--------------------------------------------------------------------
%% @spec rpdo_mapping(I, Dixt) -> Map | {error, Error}
%%
%% @doc
%% Get the RPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
rpdo_mapping(I, Dict) ->
    pdo_mapping(I+?IX_RPDO_MAPPING_FIRST,Dict).

%%--------------------------------------------------------------------
%% @spec tpdo_mapping(I, Dixt) -> Map | {error, Error}
%%
%% @doc
%% Get the TPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
tpdo_mapping(I, Dict) ->
    pdo_mapping(I+?IX_TPDO_MAPPING_FIRST,Dict).

%%--------------------------------------------------------------------
%% @spec subscribers(Tab, Index) -> [Pid] | {error, Error}
%%
%% @doc
%% Get all subscribers in Tab for Index. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
subscribers(Tab, Ix) when ?is_index(Ix) ->
    ets:foldl(
      fun({ID,ISet}, Acc) ->
	      case co_iset:member(Ix, ISet) of
		  true -> [ID|Acc];
		  false -> Acc
	      end
      end, [], Tab).

%%--------------------------------------------------------------------
%% @spec reserver_with_module(Tab, Index) -> {Pid, Mod} | []
%%
%% @doc
%% Get the reserver in Tab for Index if any. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
reserver_with_module(Tab, Ix) when ?is_index(Ix) ->
    case ets:lookup(Tab, Ix) of
	[] -> [];
	[{Ix, Mod, Pid}] -> {Pid, Mod}
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore               |
%%                     {stop, Reason}
%% @doc
%% Description: Initiates the server
%% @end
%%--------------------------------------------------------------------
init([Serial, NodeId, NodeName, Opts]) ->
    can_router:start(),
    can_udp:start(0),

    Dict = create_dict(),
    SubTable = create_sub_table(),
    ResTable = create_res_table(),
    SdoCtx = #sdo_ctx {
      timeout         = proplists:get_value(sdo_timeout,Opts,1000),
      blk_timeout     = proplists:get_value(blk_timeout,Opts,500),
      pst             = proplists:get_value(pst,Opts,16),
      max_blksize     = proplists:get_value(max_blksize,Opts,7),
      use_crc         = proplists:get_value(use_crc,Opts,true),
      dict            = Dict,
      sub_table       = SubTable,
      res_table       = ResTable
     },
    CobTable = create_cob_table(NodeId),
    Ctx = #co_ctx {
      id     = NodeId,
      name   = NodeName,
      vendor = proplists:get_value(vendor,Opts,0),
      serial = Serial,
      state  = ?Initialisation,
      node_map = ets:new(node_map, [{keypos,1}]),
      nmt_table = ets:new(nmt_table, [{keypos,#nmt_entry.id}]),
      sub_table = SubTable,
      res_table = ResTable,
      dict = Dict,
      cob_table = CobTable,
      app_list = [],
      tpdo_list = [],
      toggle = 0,
      data = [],
      sdo  = SdoCtx,
      sdo_list = [],
      time_stamp_time = proplists:get_value(time_stamp, Opts, 60000)
     },

    can_router:attach(),

    Ctx1 = case proplists:get_value(dict_file, Opts) of
	       undefined -> Ctx;
	       File -> 
		   case load_dict_internal(filename:join(code:priv_dir(canopen), File), Ctx) of
		       {ok, NewCtx} -> NewCtx;
		       {error, _Error, OldCtx} -> Ctx %% or exit ???
		   end
	   end,

    process_flag(trap_exit, true),
    if NodeId =:= 0 ->
	    {ok, Ctx1#co_ctx { state = ?Operational }};
       true ->
	    {ok, reset_application(Ctx1)}
    end.


%%
%%
%%
reset_application(Ctx) ->
    io:format("Node '~s' id=~w reset_application\n", [Ctx#co_ctx.name, Ctx#co_ctx.id]),
    reset_communication(Ctx).

reset_communication(Ctx) ->
    io:format("Node '~s' id=~w reset_communication\n",
	      [Ctx#co_ctx.name, Ctx#co_ctx.id]),
    initialization(Ctx).

initialization(Ctx) ->
    io:format("Node '~s' id=~w initialization\n",
	      [Ctx#co_ctx.name, Ctx#co_ctx.id]),
    BootMessage = #can_frame { id = ?NODE_GUARD_ID(Ctx#co_ctx.id),
			       len = 1, data = <<0>> },
    can:send(BootMessage),
    Ctx#co_ctx { state = ?PreOperational }.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_call(Request, From, State) -> {reply, Reply, State} |  
%%                                            {reply, Reply, State, Timeout} |
%%                                            {noreply, State} |
%%                                            {noreply, State, Timeout} |
%%                                            {stop, Reason, Reply, State} |
%%                                            {stop, Reason, State}
%% Request = {set, Index, SubInd, Value} | 
%%           {direct_set, Index, SubInd, Value} | 
%%           {value, {index, SubInd}} | 
%%           {value, Index} | 
%%           {store, Block, CobId, Index, SubInd, Bin} | 
%%           {fetch, Block, CobId, Index, SubInd} | 
%%           {add_entry, Entry} | 
%%           {get_entry, Entry} | 
%%           {load_dict, File} | 
%%           {attach, Pid} | 
%%           {detach, Pid}  
%% @doc
%% Description: Handling call messages.
%% @end
%%--------------------------------------------------------------------

handle_call({set,IX,SI,Value}, _From, Ctx) ->
    {Reply,Ctx1} = set_dict_value(IX,SI,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({direct_set,IX,SI,Value}, _From, Ctx) ->
    {Reply,Ctx1} = direct_set_dict_value(IX,SI,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({value,{Ix, Si}}, _From, Ctx) ->
    Result = co_dict:value(Ctx#co_ctx.dict, Ix, Si),
    {reply, Result, Ctx};
handle_call({value,Ix}, _From, Ctx) ->
    Result = co_dict:value(Ctx#co_ctx.dict, Ix, 0),
    {reply, Result, Ctx};

handle_call({store,Block,COBID,IX,SI,Bin}, From, Ctx) ->
    case lookup_sdo_server(COBID,Ctx) of
	ID={Tx,Rx} ->
	    case co_sdo_cli_fsm:store(Ctx#co_ctx.sdo,Block,From,Tx,Rx,IX,SI,Bin) of
		{error, Reason} ->
		    io:format("unable to start co_sdo_cli_fsm: ~p\n", [Reason]),
		    {reply, Reason, Ctx};
		{ok, Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    ?dbg("~s: store: added session id=~p\n", [Ctx#co_ctx.name, ID]),
		    Sessions = Ctx#co_ctx.sdo_list,
		    {noreply, Ctx#co_ctx { sdo_list = [S|Sessions]}}
	    end;
	undefined ->
	    {reply, {error, badarg}, Ctx}
    end;

handle_call({fetch,Block,COBID,IX,SI}, From, Ctx) ->
    case lookup_sdo_server(COBID,Ctx) of
	ID={Tx,Rx} ->
	    case co_sdo_cli_fsm:fetch(Ctx#co_ctx.sdo,Block,From,Tx,Rx,IX,SI) of
		{error, Reason} ->
		    io:format("unable to start co_sdo_cli_fsm: ~p\n", [Reason]),
		    {reply, Reason, Ctx};
		{ok, Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    ?dbg("~s: fetch: added session id=~p\n", [Ctx#co_ctx.name, ID]),
		    Sessions = Ctx#co_ctx.sdo_list,
		    {noreply, Ctx#co_ctx { sdo_list = [S|Sessions]}}
	    end;
	undefined ->
	    {reply, {error, badarg}, Ctx}
    end;

handle_call({add_entry,Entry}, _From, Ctx) when is_record(Entry, dict_entry) ->
    try set_dict_entry(Entry, Ctx) of
	Error = {error,_} ->
	    {reply, Error, Ctx};
	Ctx1 ->
	    {reply, ok, Ctx1}
    catch
	error:Reason ->
	    {reply, {error,Reason}, Ctx}
    end;

handle_call({get_entry,Index}, _From, Ctx) ->
    Result = co_dict:lookup_entry(Ctx#co_ctx.dict, Index),
    {reply, Result, Ctx};

handle_call({load_dict, File}, _From, Ctx) ->
    case load_dict_internal(File, Ctx) of
	{ok, Ctx1} ->
	    {reply, ok, Ctx1};
	{error, Error, Ctx1} ->
	    {reply, Error, Ctx1}
    end;

handle_call({attach,Pid}, _From, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	false ->
	    Mon = erlang:monitor(process, Pid),
	    App = #app { pid=Pid, mon=Mon },
	    Ctx1 = Ctx#co_ctx { app_list = [App |Ctx#co_ctx.app_list] },
	    {reply, {ok, Ctx1#co_ctx.id}, Ctx1};
	{value,_} ->
	    {reply, {error, already_attached, Ctx#co_ctx.id}, Ctx}
    end;

handle_call({detach,Pid}, _From, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	false ->
	    {reply, {error, not_attached}, Ctx};
	{value, App} ->
	    remove_subscriptions(Ctx#co_ctx.sub_table, Pid),
	    remove_reservations(Ctx#co_ctx.res_table, Pid),
	    erlang:demonitor(App#app.mon, [flush]),
	    Ctx1 = Ctx#co_ctx { app_list = Ctx#co_ctx.app_list -- [App]},
	    {reply, ok, Ctx1}
    end;

handle_call({subscribe,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_subscription(Ctx#co_ctx.sub_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({subscribe,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_subscription(Ctx#co_ctx.sub_table, Ix, Pid),
    {reply, Res, Ctx};

handle_call({unsubscribe,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.sub_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({unsubscribe,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_subscription(Ctx#co_ctx.sub_table, Ix, Pid),
    {reply, Res, Ctx};

handle_call({subscriptions,Pid}, _From, Ctx) when is_pid(Pid) ->
    Subs = subscriptions(Ctx#co_ctx.sub_table, Pid),
    {reply, Subs, Ctx};

handle_call({subscribers,Ix}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.sub_table, Ix),
    {reply, Subs, Ctx};

handle_call({subscribers}, _From, Ctx)  ->
    Subs = subscribers(Ctx#co_ctx.sub_table),
    {reply, Subs, Ctx};

handle_call({reserve,{Ix1, Ix2},Module,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_reservation(Ctx#co_ctx.res_table, Ix1, Ix2, Module, Pid),
    {reply, Res, Ctx};

handle_call({reserve,Ix, Module, Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = add_reservation(Ctx#co_ctx.res_table, [Ix], Module, Pid),
    {reply, Res, Ctx};

handle_call({unreserve,{Ix1, Ix2},Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_reservation(Ctx#co_ctx.res_table, Ix1, Ix2, Pid),
    {reply, Res, Ctx};

handle_call({unreserve,Ix,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = remove_reservation(Ctx#co_ctx.res_table, [Ix], Pid),
    {reply, Res, Ctx};

handle_call({reservations,Pid}, _From, Ctx) when is_pid(Pid) ->
    Res = reservations(Ctx#co_ctx.res_table, Pid),
    {reply, Res, Ctx};

handle_call({reserver,Ix}, _From, Ctx)  ->
    PidInList = reserver_pid(Ctx#co_ctx.res_table, Ix),
    {reply, PidInList, Ctx};

handle_call({reservers}, _From, Ctx)  ->
    Res = reservers(Ctx#co_ctx.res_table),
    {reply, Res, Ctx};

handle_call(dump, _From, Ctx) ->
    io:format("  NAME: ~p\n", [Ctx#co_ctx.name]),
    io:format("    ID: ~8.16.0B\n", [Ctx#co_ctx.id]),
    io:format("VENDOR: ~8.16.0B\n", [Ctx#co_ctx.vendor]),
    io:format("SERIAL: ~8.16.0B\n", [Ctx#co_ctx.serial]),
    io:format(" STATE: ~s\n", [co_format:state(Ctx#co_ctx.state)]),

    io:format("---- NMT TABLE ----\n"),
    ets:foldl(
      fun(E,_) ->
	      io:format("  ID: ~w\n", 
			[E#nmt_entry.id]),
	      io:format("    VENDOR: ~8.16.0B\n", 
			[E#nmt_entry.vendor]),
	      io:format("    SERIAL: ~8.16.0B\n", 
			[E#nmt_entry.serial]),
	      io:format("     STATE: ~s\n", 
			[co_format:state(E#nmt_entry.state)])
      end, ok, Ctx#co_ctx.nmt_table),
    io:format("---- NODE MAP TABLE ----\n"),
    ets:foldl(
      fun({Sn,NodeId},_) ->
	      io:format("~8.16.0B => ~w\n", [Sn, NodeId])
      end, ok, Ctx#co_ctx.node_map),
    io:format("---- COB TABLE ----\n"),
    ets:foldl(
      fun({CobId, X},_) ->
	      io:format("~8.16.0B => ~p\n", [CobId, X])
      end, ok, Ctx#co_ctx.cob_table),
    io:format("---- SUB TABLE ----\n"),
    ets:foldl(
      fun({Pid, IxList},_) ->
	      io:format("~p => \n", [Pid]),
	      lists:foreach(
		fun(Ixs) ->
			case Ixs of
			    {IxStart, IxEnd} ->
				io:format("[~7.16.0#-~7.16.0#]\n", [IxStart, IxEnd]);
			    Ix ->
				io:format("~7.16.0#\n",[Ix])
			end
		end,
		IxList)
      end, ok, Ctx#co_ctx.sub_table),
    io:format("---- RES TABLE ----\n"),
    ets:foldl(
      fun({Ix, Mod, Pid},_) ->
	      io:format("~7.16.0# reserved by ~p, module ~s\n",[Ix, Pid, Mod])
      end, ok, Ctx#co_ctx.res_table),
    io:format("------------------------\n"),
    {reply, ok, Ctx};

handle_call({change_session_timeout, NewTimeout}, _From, Ctx) ->
    Sdo = Ctx#co_ctx.sdo#sdo_ctx {timeout = NewTimeout},
    {reply, ok, Ctx#co_ctx {sdo = Sdo}};
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};
handle_call(_Request, _From, Ctx) ->
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%% @end
%%--------------------------------------------------------------------
handle_cast({pdo_event,I}, Ctx) ->
    Index = ?IX_TPDO_PARAM_FIRST + I,
    case co_dict:value(Ctx#co_ctx.dict, {Index,?SI_PDO_COB_ID}) of
	{ok,COBID} ->
	    case lookup_cobid(COBID, Ctx) of
		{tpdo,_,Pid} ->
		    co_tpdo:transmit(Pid),
		    {noreply,Ctx};
		_ ->
		    {noreply,Ctx}
	    end;
	_Error ->
	    {noreply,Ctx}
    end;
handle_cast(_Msg, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
handle_info(Frame, Ctx) when is_record(Frame, can_frame) ->
    Ctx1 = handle_can(Frame, Ctx),
    {noreply, Ctx1};

handle_info({timeout,Ref,sync}, Ctx) when Ref =:= Ctx#co_ctx.sync_tmr ->
    %% Send a SYNC frame
    %% FIXME: check that we still are sync producer?
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.sync_id),
    Frame = #can_frame { id=FrameID, len=0, data=(<<>>) },
    can:send(Frame),
    Ctx1 = Ctx#co_ctx { sync_tmr = start_timer(Ctx#co_ctx.sync_time, sync) },
    {noreply, Ctx1};

handle_info({timeout,Ref,time_stamp}, Ctx) when Ref =:= Ctx#co_ctx.time_stamp_tmr ->
    %% FIXME: Check that we still are time stamp producer
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.time_stamp_id),
    Time = time_of_day(),
    Data = co_codec:encode(Time, ?TIME_OF_DAY),
    Size = byte_size(Data),
    Frame = #can_frame { id=FrameID, len=Size, data=Data },
    can:send(Frame),
    ?dbg("~s: handle_info: Sent time stamp ~p\n", [Ctx#co_ctx.name, Time]),
    Ctx1 = Ctx#co_ctx { time_stamp_tmr = start_timer(Ctx#co_ctx.time_stamp_time, time_stamp) },
    {noreply, Ctx1};

handle_info({'DOWN',Ref,process,_Pid,Reason}, Ctx) ->
    case lists:keysearch(Ref, #sdo.mon, Ctx#co_ctx.sdo_list) of
	{value,_S} ->
	    if Reason =/= normal ->
		    io:format("~p: session died: ~p\n", [?MODULE, Reason]);
	       true ->
		    ok
	    end,
	    Sessions = lists:keydelete(Ref, #sdo.mon, Ctx#co_ctx.sdo_list),
	    {noreply, Ctx#co_ctx { sdo_list = Sessions }};
	false ->
	    case lists:keysearch(Ref, #app.mon, Ctx#co_ctx.app_list) of
		false ->
		    {noreply, Ctx};
		{value,A} ->
		    io:format("can_node: id=~w application died\n", [A#app.pid]),
		    remove_subscriptions(Ctx#co_ctx.sub_table, A#app.pid), %% Or reset ??
		    reset_reservations(Ctx#co_ctx.res_table, A#app.pid),
		    %% FIXME: restart application? application_mod ?
		    {noreply, Ctx#co_ctx { app_list = Ctx#co_ctx.app_list--[A]}}
	    end
    end;
handle_info(_Info, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, Ctx) ->
    Self = self(),

    %% Stop all subscribers?? or inform them ??
    lists:foreach(
      fun(Pid) -> 
	      case Pid of
		  Self -> 
		      do_nothing;
		  _NotSelf ->
		      ?dbg("~s: terminate: Killing application with pid = ~p\n", 
			   [Ctx#co_ctx.name, Pid]),
		      %% Or gen_server:cast(Pid, co_node_terminated) ??	 
		      exit(Pid, co_node_terminated)

	      end
      end,
      subscribers(Ctx#co_ctx.sub_table)),

    %% Stop all tpdo-servers ??
    lists:foreach(
      fun(T) ->
	      case T#tpdo.pid of
		  Self  -> do_nothing; %% ??
		  Pid -> 
		      ?dbg("~s: terminate: Killing TPDO with pid = ~p\n", 
			   [Ctx#co_ctx.name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.tpdo_list),

    ?dbg("~s: terminate: cleaned up, exiting\n", [Ctx#co_ctx.name]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%%
%% Load a dictionary
%% 
load_dict_internal(File, Ctx) ->
    ?dbg("~p: load_dict_internal: Loading file = ~p\n", [?MODULE, File]),
    try co_file:load(File) of
	{ok,Os} ->
	    %% Install all objects
	    foreach(
	      fun({Obj,Es}) ->
		      foreach(fun(E) -> ets:insert(Ctx#co_ctx.dict, E) end, Es),
		      ets:insert(Ctx#co_ctx.dict, Obj)
	      end, Os),
	    %% Now update cob table
	    Ctx1 = 
		foldl(fun({Obj,_Es},Ctx0) ->
			      I = Obj#dict_object.index,
			      handle_notify(I, Ctx0)
		      end, Ctx, Os),
	    {ok, Ctx1};
	Error ->
	    {error, Error, Ctx}
    catch
	error:Reason ->
	    ?dbg("~p: load_dict_internal: Failed Loading file, reason = ~p\n", 
		 [?MODULE, Reason]),

	    {error, Reason, Ctx}
    end.

%%
%% Handle can messages
%%
handle_can(Frame, Ctx) when ?is_can_frame_rtr(Frame) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg("~s: handle_can: COBID=~8.16.0B\n", [Ctx#co_ctx.name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt  ->
	    %% Handle Node guard
	    Ctx;
	{tpdo,true,Pid} ->
	    co_tpdo:rtr(Pid),
	    Ctx;
	_ -> 
	    Ctx
    end;
handle_can(Frame, Ctx) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg("~s: handle_can: COBID=~8.16.0B\n", [Ctx#co_ctx.name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt        -> handle_nmt(Frame, Ctx);
	sync       -> handle_sync(Frame, Ctx);
	emcy       -> handle_emcy(Frame, Ctx);
	time_stamp  -> handle_time_stamp(Frame, Ctx);
	node_guard -> handle_node_guard(Frame, Ctx);
	lss        -> handle_lss(Frame, Ctx);
	{rpdo,Offset} -> handle_rpdo(Frame, Offset, COBID, Ctx);
	{sdo_tx,Rx} ->
	    if Ctx#co_ctx.state=:= ?Operational; 
	       Ctx#co_ctx.state =:= ?PreOperational ->	    
		    handle_sdo_tx(Frame, COBID, Rx, Ctx);
	       true ->
		    Ctx
	    end;
	{sdo_rx,Tx} ->
	    if Ctx#co_ctx.state=:= ?Operational; 
	       Ctx#co_ctx.state =:= ?PreOperational ->	    
		    handle_sdo_rx(Frame, COBID, Tx, Ctx);
	       true ->
		    Ctx
	    end;
	_NotKnown ->
	    %% Test if MPDO
	    <<F:1, Addr:7, Ix:16/little, Si:8, Data:32/little>> = 
		Frame#can_frame.data,
	    case {F, Addr} of
		{1, 0} ->
		    %% DAM-MPDO, destination is a group
		    handle_dam_mpdo(Ctx, ?XNODE_ID(COBID), Ix, Si, Data);
		_Other ->
		    ?dbg("~s: handle_can: frame not handled: Frame = ~p\n", 
			 [Ctx#co_ctx.name, Frame]),
		    Ctx
	    end
    end.

%%
%% NMT 
%%
handle_nmt(M, Ctx) when M#can_frame.len >= 2 ->
    ?dbg("~s: handle_nmt: ~p\n", [Ctx#co_ctx.name, M]),
    <<NodeId,Cs,_/binary>> = M#can_frame.data,
    if NodeId == 0; NodeId == Ctx#co_ctx.id ->
	    case Cs of
		?NMT_RESET_NODE ->
		    reset_application(Ctx);
		?NMT_RESET_COMMUNICATION ->
		    reset_communication(Ctx);
		?NMT_ENTER_PRE_OPERATIONAL ->
		    Ctx#co_ctx { state = ?PreOperational };
		?NMT_START_REMOTE_NODE ->
		    Ctx#co_ctx { state = ?Operational };
		?NMT_STOP_REMOTE_NODE ->
		    Ctx#co_ctx { state = ?Stopped };
		_ ->
		    ?dbg("handle_nmt: unknown cs=~w\n", [Cs]),
		    Ctx
	    end;
       true ->
	    %% not for me
	    Ctx
    end.


handle_node_guard(Frame, Ctx) when ?is_can_frame_rtr(Frame) ->
    ?dbg("~s: handle_node_guard: request ~p\n", [Ctx#co_ctx.name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    if NodeId == 0; NodeId == Ctx#co_ctx.id ->
	    Data = Ctx#co_ctx.state bor Ctx#co_ctx.toggle,
	    can:send(#can_frame { id = ?NODE_GUARD_ID(Ctx#co_ctx.id),
				  len = 1,
				  data = <<Data>> }),
	    Toggle = Ctx#co_ctx.toggle bxor 16#80,
	    Ctx#co_ctx { toggle = Toggle };
       true ->
	    %% ignore, not for me
	    Ctx
    end;
handle_node_guard(Frame, Ctx) when Frame#can_frame.len >= 1 ->
    ?dbg("~s: handle_node_guard: ~p\n", [Ctx#co_ctx.name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    case Frame#can_frame.data of
	<<_Toggle:1, State:7, _/binary>> when NodeId =/= Ctx#co_ctx.id ->
	    %% Verify toggle if NodeId=slave and we are Ctx#co_ctx.id=master
	    update_nmt_entry(NodeId, [{state,State}], Ctx);
	_ ->
	    Ctx
    end.

%%
%% LSS
%% 
handle_lss(M, Ctx) ->
    ?dbg("~s: handle_lss: ~p\n", [Ctx#co_ctx.name,M]),
    Ctx.

%%
%% SYNC
%%
handle_sync(_Frame, Ctx) ->
    ?dbg("~s: handle_sync: ~p\n", [Ctx#co_ctx.name,_Frame]),
    lists:foreach(
      fun(T) -> co_tpdo:sync(T#tpdo.pid) end, Ctx#co_ctx.tpdo_list),
    Ctx.

%%
%% TIME STAMP - update local time offset
%%
handle_time_stamp(Frame, Ctx) ->
    ?dbg("~s: handle_timestamp: ~p\n", [Ctx#co_ctx.name,Frame]),
    try co_codec:decode(Frame#can_frame.data, ?TIME_OF_DAY) of
	{T, _Bits} when is_record(T, time_of_day) ->
	    ?dbg("~s: Got timestamp: ~p\n", [Ctx#co_ctx.name, T]),
	    set_time_of_day(T),
	    Ctx;
	_ ->
	    Ctx
    catch
	error:_ ->
	    Ctx
    end.

%%
%% EMERGENCY - this is the consumer side detecting emergency
%%
handle_emcy(_Frame, Ctx) ->
    ?dbg("~s: handle_emcy: ~p\n", [Ctx#co_ctx.name,_Frame]),
    Ctx.

%%
%% Recive PDO - unpack into the dictionary
%%
handle_rpdo(Frame, Offset, _COBID, Ctx) ->
    ?dbg("~s: handle_rpdo: ~p\n", [Ctx#co_ctx.name,Frame]),
    rpdo_unpack(Offset,Frame#can_frame.data, Ctx).

%% CLIENT side:
%% SDO tx - here we receive can_node response
%% FIXME: conditional compile this
%%
handle_sdo_tx(Frame, Tx, Rx, Ctx) ->
    ?dbg("~s: handle_sdo_tx: src=~p, ~s\n",
	      [Ctx#co_ctx.name, Tx,
	       co_format:format_sdo(co_sdo:decode_tx(Frame#can_frame.data))]),
    ID = {Tx,Rx},
    ?dbg("~s: handle_sdo_tx: session id=~p\n", [Ctx#co_ctx.name, ID]),
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    ?dbg("~s: handle_sdo_tx: session not found\n", [Ctx#co_ctx.name]),
	    %% no such session active
	    Ctx
    end.

%% SERVER side
%% SDO rx - here we receive client requests
%% FIXME: conditional compile this
%%
handle_sdo_rx(Frame, Rx, Tx, Ctx) ->
    ?dbg("~s: handle_sdo_rx: ~s\n", 
	      [Ctx#co_ctx.name,
	       co_format:format_sdo(co_sdo:decode_rx(Frame#can_frame.data))]),
    ID = {Rx,Tx},
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    ?dbg("~s: handle_sdo_rx: Frame sent to old process ~p\n", 
		 [Ctx#co_ctx.name,S#sdo.pid]),
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    %% FIXME: handle expedited and spurios frames here
	    %% like late aborts etc here !!!
	    case co_sdo_srv_fsm:start(Ctx#co_ctx.sdo,Rx,Tx) of
		{error, Reason} ->
		    io:format("unable to start co_sdo_srv_fsm: ~p\n",
			      [Reason]),
		    Ctx;
		{ok,Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    ?dbg("~s: handle_sdo_rx: Frame sent to new process ~p\n", 
			 [Ctx#co_ctx.name,Pid]),		    
		    gen_fsm:send_event(Pid, Frame),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    Ctx#co_ctx { sdo_list = [S|Sessions]}
	    end
    end.

%%
%% DAM-MPDO
%%
handle_dam_mpdo(Ctx, RId, Ix, Si, Data) ->
    ?dbg("~s: handle_dam_mpdo: Index = ~7.16.0#\n", [Ctx#co_ctx.name,Ix]),
    case lists:usort(subscribers(Ctx#co_ctx.sub_table, Ix) ++
		     reserver_pid(Ctx#co_ctx.res_table, Ix)) of
	[] ->
	    ?dbg("~s: No subscribers for index ~7.16.0#\n", [Ctx#co_ctx.name, Ix]);
	PidList ->
	    lists:foreach(
	      fun(Pid) ->
		      ?dbg("~s: Process ~p subscribes to index ~7.16.0#\n", 
			   [Ctx#co_ctx.name, Pid, Ix]),
		      Pid ! {notify, RId, Ix, Si, Data}
	      end, PidList)
    end,
    Ctx.

%% NMT requests (call from within node process)
set_node_state(Ctx, NodeId, State) ->
    update_nmt_entry(NodeId, [{state,State}], Ctx).

do_node_guard(Ctx, 0) ->
    foreach(
      fun(I) ->
	      update_nmt_entry(I, [{state,?UnknownState}], Ctx)
      end,
      lists:seq(0, 127)),
    send_nmt_node_guard(0);
do_node_guard(Ctx, I) when I > 0, I =< 127 ->
    update_nmt_entry(I, [{state,?UnknownState}], Ctx),
    send_nmt_node_guard(I).


send_nmt_state_change(NodeId, Cs) ->
    can:send(#can_frame { id = ?NMT_ID,
			  len = 2,
			  data = <<Cs:8, NodeId:8>>}).

send_nmt_node_guard(NodeId) ->
    ID = ?COB_ID(?NODE_GUARD,NodeId) bor ?CAN_RTR_FLAG,
    can:send(#can_frame { id = ID,
			  len = 0, data = <<>>}).

send_x_node_guard(NodeId, Cmd, Ctx) ->
    Crc = crc:checksum(<<(Ctx#co_ctx.serial):32/little>>),
    Data = <<Cmd:8, (Ctx#co_ctx.serial):32/little, Crc:16/little,
	     (Ctx#co_ctx.state):8>>,
    can:send(#can_frame { id = ?COB_ID(?NODE_GUARD,NodeId),
			  len = 8, data = Data}),
    Ctx.

%% lookup / create nmt entry
lookup_nmt_entry(NodeId, Ctx) ->
    case ets:lookup(Ctx#co_ctx.nmt_table, NodeId) of
	[] ->
	    #nmt_entry { id = NodeId };
	[E] ->
	    E
    end.

%%
%% Load dictionary from file
%% FIXME: map
%%    IX_COB_ID_SYNC_MESSAGE  => cob_table
%%    IX_COB_ID_TIME_STAMP    => cob_table
%%    IX_COB_ID_EMERGENCY     => cob_table
%%    IX_SDO_SERVER_FIRST - IX_SDO_SERVER_LAST =>  cob_table
%%    IX_SDO_CLIENT_FIRST - IX_SDO_CLIENT_LAST =>  cob_table
%%    IX_RPDO_PARAM_FIRST - IX_RPDO_PARAM_LAST =>  cob_table
%%    IX_TPDO_PARAM_FIRST - IX_TPDO_PARAM_LAST =>  cob_table
%% 
set_dict_object({O,Es}, Ctx) when is_record(O, dict_object) ->
    lists:foreach(fun(E) -> ets:insert(Ctx#co_ctx.dict, E) end, Es),
    ets:insert(Ctx#co_ctx.dict, O),
    I = O#dict_object.index,
    handle_notify(I, Ctx).

set_dict_entry(E, Ctx) when is_record(E, dict_entry) ->
    {I,_} = E#dict_entry.index,
    ets:insert(Ctx#co_ctx.dict, E),
    handle_notify(I, Ctx).

set_dict_value(IX,SI,Value,Ctx) ->
    try co_dict:set(Ctx#co_ctx.dict, IX,SI,Value) of
	ok -> {ok, handle_notify(IX, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.

direct_set_dict_value(IX,SI,Value,Ctx) ->
    try co_dict:direct_set(Ctx#co_ctx.dict, IX,SI,Value) of
	ok -> {ok, handle_notify(IX, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.

%%
%% Dictionary entry has been updated
%% Emulate co_node as subscriber to dictionary updates
%%
handle_notify(I, Ctx) ->
    NewCtx = handle_notify1(I, Ctx),
    inform_subscribers(I, NewCtx),
    NewCtx.

handle_notify1(I, Ctx) ->
    ?dbg("~s: handle_notify: Index=~7.16.0#\n",[Ctx#co_ctx.name, I]),
    case I of
	?IX_COB_ID_SYNC_MESSAGE ->
	    update_sync(Ctx);
	?IX_COM_CYCLE_PERIOD ->
	    update_sync(Ctx);
	?IX_COB_ID_TIME_STAMP ->
	    update_time_stamp(Ctx);
	?IX_COB_ID_EMERGENCY ->
	    update_emcy(Ctx);
	_ when I >= ?IX_SDO_SERVER_FIRST, I =< ?IX_SDO_SERVER_LAST ->
	    case load_sdo_parameter(I, Ctx) of
		undefined -> Ctx;
		SDO ->
		    Rx = SDO#sdo_parameter.client_to_server_id,
		    Tx = SDO#sdo_parameter.server_to_client_id,
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    Ctx
	    end;
	_ when I >= ?IX_SDO_CLIENT_FIRST, I =< ?IX_SDO_CLIENT_LAST ->
	    case load_sdo_parameter(I, Ctx) of
		undefined -> Ctx;
		SDO ->
		    Tx = SDO#sdo_parameter.client_to_server_id,
		    Rx = SDO#sdo_parameter.server_to_client_id,
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    Ctx
	    end;
	_ when I >= ?IX_RPDO_PARAM_FIRST, I =< ?IX_RPDO_PARAM_LAST ->
	    ?dbg("~s: handle_notify: update RPDO offset=~7.16.0#\n", 
		 [Ctx#co_ctx.name, (I-?IX_RPDO_PARAM_FIRST)]),
	    case load_pdo_parameter(I, (I-?IX_RPDO_PARAM_FIRST), Ctx) of
		undefined -> 
		    Ctx;
		Param ->
		    if not (Param#pdo_parameter.valid) ->
			    ets:delete(Ctx#co_ctx.cob_table,
				       Param#pdo_parameter.cob_id);
		       true ->
			    ets:insert(Ctx#co_ctx.cob_table, 
				       {Param#pdo_parameter.cob_id,
					{rpdo,Param#pdo_parameter.offset}})
		    end,
		    Ctx
	    end;
	_ when I >= ?IX_TPDO_PARAM_FIRST, I =< ?IX_TPDO_PARAM_LAST ->
	    ?dbg("~s: handle_notify: update TPDO: offset=~7.16.0#\n",
		 [Ctx#co_ctx.name, I - ?IX_TPDO_PARAM_FIRST]),
	    case load_pdo_parameter(I, (I-?IX_TPDO_PARAM_FIRST), Ctx) of
		undefined -> Ctx;
		Param ->
		    case update_tpdo(Param, Ctx) of
			{new, {T,Ctx1}} ->
			    ?dbg("~s: handle_notify: TPDO:new\n",[Ctx#co_ctx.name]),
			    ets:insert(Ctx#co_ctx.cob_table, 
				       {Param#pdo_parameter.cob_id,
					{tpdo,Param#pdo_parameter.rtr_allowed,T#tpdo.pid}}),
			    Ctx1;
			{existing,T} ->
			    ?dbg("~s: handle_notify: TPDO:existing\n",
				 [Ctx#co_ctx.name]),
			    co_tpdo:update_param(T#tpdo.pid, Param),
			    Ctx;
			{deleted,Ctx1} ->
			    ?dbg("~s: handle_notify: TPDO:deleted\n",
				 [Ctx#co_ctx.name]),
			    ets:delete(Ctx#co_ctx.cob_table, Param#pdo_parameter.cob_id),
			    Ctx1;
			none ->
			    ?dbg("~s: handle_notify: TPDO:none\n",[Ctx#co_ctx.name]),
			    Ctx
		    end
	    end;
	_ when I >= ?IX_TPDO_MAPPING_FIRST, I =< ?IX_TPDO_MAPPING_LAST ->
	    Offset = I - ?IX_TPDO_MAPPING_FIRST,
	    ?dbg("~s: handle_notify: update TPDO-MAP: offset=~w\n", 
		 [Ctx#co_ctx.name, Offset]),
	    J = ?IX_TPDO_PARAM_FIRST + Offset,
	    COBID = co_dict:direct_value(Ctx#co_ctx.dict,J,?SI_PDO_COB_ID),
	    case lookup_cobid(COBID, Ctx) of
		{tpdo,_RtrAllowed,Pid} ->
		    co_tpdo:update_map(Pid),
		    Ctx;
		_ ->
		    Ctx
	    end;
	_ ->
	    ?dbg("~s: handle_notify: index not in cob table ix=~7.16.0#\n", 
		 [Ctx#co_ctx.name, I]),
	    Ctx
    end.

%% Load time_stamp COBID - maybe start co_time_stamp server
update_time_stamp(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_TIME_STAMP,0) of
	ID ->
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_TIME_PRODUCER =/= 0 ->
		    Time = Ctx#co_ctx.time_stamp_time,
		    ?dbg("~s: update_time_stamp: Timestamp server time=~p\n", 
			 [Ctx#co_ctx.name, Time]),
		    if Time > 0 ->
			    Tmr = start_timer(Ctx#co_ctx.time_stamp_time,
					      time_stamp),
			    Ctx#co_ctx { time_stamp_tmr=Tmr, 
					 time_stamp_id=COBID };
		       true ->
			    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
			    Ctx#co_ctx { time_stamp_tmr=Tmr,
					 time_stamp_id=COBID}
		    end;
	       ID band ?COBID_ENTRY_TIME_CONSUMER =/= 0 ->
		    %% consumer
		    ?dbg("~s: update_time_stamp: Timestamp consumer\n", 
			 [Ctx#co_ctx.name]),
		    Tmr = stop_timer(Ctx#co_ctx.time_stamp_tmr),
		    %% FIXME: delete old COBID!!!
		    ets:insert(Ctx#co_ctx.cob_table, {COBID,time_stamp}),
		    Ctx#co_ctx { time_stamp_tmr=Tmr, time_stamp_id=COBID}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.


%% Load emcy COBID 
update_emcy(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_EMERGENCY,0) of
	ID ->
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_INVALID =/= 0 ->
		    Ctx#co_ctx { emcy_id = COBID };
	       true ->
		    Ctx#co_ctx { emcy_id = 0 }
	    end
    catch
	error:_ ->
	    Ctx#co_ctx { emcy_id = 0 }  %% FIXME? keep or reset?
    end.

%% Either SYNC_MESSAGE or CYCLE_WINDOW is updated
update_sync(Ctx) ->
    try co_dict:direct_value(Ctx#co_ctx.dict,?IX_COB_ID_SYNC_MESSAGE,0) of
	ID ->
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    if ID band ?COBID_ENTRY_SYNC =/= 0 ->
		    %% producer - sync server
		    try co_dict:direct_value(Ctx#co_ctx.dict,
					     ?IX_COM_CYCLE_PERIOD,0) of
			Time when Time > 0 ->
			    %% we do not have micro :-(
			    Ms = (Time + 999) div 1000,  
			    Tmr = start_timer(Ms, sync),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time = Ms,
					 sync_id=COBID };
			_ ->
			    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
			    Ctx#co_ctx { sync_tmr=Tmr,sync_time=0,
					 sync_id=COBID}
		    catch
			error:_Reason ->
			    Ctx
		    end;
	       true ->
		    %% consumer
		    Tmr = stop_timer(Ctx#co_ctx.sync_tmr),
		    ets:insert(Ctx#co_ctx.cob_table, {COBID,sync}),
		    Ctx#co_ctx { sync_tmr=Tmr, sync_time=0,sync_id=COBID}
	    end
    catch
	error:_Reason ->
	    Ctx
    end.
    

update_tpdo(Param, Ctx) ->
    case lists:keytake(Param#pdo_parameter.cob_id, #tpdo.cob_id,
		       Ctx#co_ctx.tpdo_list) of
	false ->
	    if Param#pdo_parameter.valid ->
		    {ok,Pid} = co_tpdo:start(Ctx#co_ctx.dict, Param),
		    Mon = erlang:monitor(process, Pid),
		    T = #tpdo { cob_id = Param#pdo_parameter.cob_id,
				pid = Pid,
				mon = Mon },
		    TList = [T | Ctx#co_ctx.tpdo_list],
		    {new, {T, Ctx#co_ctx { tpdo_list = TList }}};
	       true ->
		    none
	    end;
	{value,T,TList} ->
	    if Param#pdo_parameter.valid ->
		    {existing, T};
	       true ->
		    erlang:demonitor(T#tpdo.mon),
		    co_tpdo:stop(T#tpdo.pid),
		    {deleted,Ctx#co_ctx { tpdo_list = TList }}
	    end
    end.


load_pdo_parameter(I, Offset, Ctx) ->
    case load_list(Ctx#co_ctx.dict, [{I, ?SI_PDO_COB_ID}, 
			  {I,?SI_PDO_TRANSMISSION_TYPE, 255},
			  {I,?SI_PDO_INHIBIT_TIME, 0},
			  {I,?SI_PDO_EVENT_TIMER, 0}]) of
	[ID,Trans,Inhibit,Timer] ->
	    Valid = (ID band ?COBID_ENTRY_INVALID) =:= 0,
	    RtrAllowed = (ID band ?COBID_ENTRY_RTR_DISALLOWED) =:=0,
	    COBID = ID band (?COBID_ENTRY_ID_MASK bor ?COBID_ENTRY_EXTENDED),
	    #pdo_parameter { offset = Offset,
			     valid = Valid,
			     rtr_allowed = RtrAllowed,
			     cob_id = COBID,
			     transmission_type=Trans,
			     inhibit_time = Inhibit,
			     event_timer = Timer };
	_ ->
	    undefined
    end.
    

load_sdo_parameter(I, Ctx) ->
    case load_list(Ctx#co_ctx.dict, [{I,?SI_SDO_CLIENT_TO_SERVER},{I,?SI_SDO_SERVER_TO_CLIENT},
			  {I,?SI_SDO_NODEID,undefined}]) of
	[CS,SC,NodeID] ->
	    #sdo_parameter { client_to_server_id = CS, 
			     server_to_client_id = SC,
			     node_id = NodeID };
	_ ->
	    undefined
    end.

load_list(Dict, List) ->
    load_list(Dict, List, []).

load_list(Dict, [{IX,SI}|List], Acc) ->
    try co_dict:direct_value(Dict,IX,SI) of
	Value -> load_list(Dict, List, [Value|Acc])
    catch
	error:_ -> undefined
    end;
load_list(Dict, [{IX,SI,Default}|List],Acc) ->
    try co_dict:direct_value(Dict,IX,SI) of
	Value -> load_list(Dict, List, [Value|Acc])
    catch
	error:_ ->
	    load_list(Dict, List, [Default|Acc])
    end;
load_list(_Dict, [], Acc) ->
    reverse(Acc).

%% 
%% Create and initialize dictionary
%%
create_dict() ->
    Dict = co_dict:new(public),
    %% install mandatory default items
    co_dict:add_object(Dict, #dict_object { index=?IX_ERROR_REGISTER,
					    access=?ACCESS_RO,
					    struct=?OBJECT_VAR,
					    type=?UNSIGNED8 },
		       [#dict_entry { index={?IX_ERROR_REGISTER, 0},
				      access=?ACCESS_RO,
				      type=?UNSIGNED8,
				      value=0}]),
    co_dict:add_object(Dict, #dict_object { index=?IX_PREDEFINED_ERROR_FIELD,
					    access=?ACCESS_RO,
					    struct=?OBJECT_ARRAY,
					    type=?UNSIGNED32 },
		       [#dict_entry { index={?IX_PREDEFINED_ERROR_FIELD,0},
				      access=?ACCESS_RW,
				      type=?UNSIGNED8,
				      value=0}]),
    Dict.
    
%%
%% Initialized the default connection set
%% For the extended format we always set the COBID_ENTRY_EXTENDED bit
%% This match for the none extended format
%% We may handle the mixed mode later on....
%%
create_cob_table(Nid) ->
    T = ets:new(cob_table, [public]),
    if ?is_nodeid_extended(Nid) ->
	    SDORx = ?XCOB_ID(?SDO_RX,Nid),
	    SDOTx = ?XCOB_ID(?SDO_TX,Nid),
	    ets:insert(T, {?XCOB_ID(?NMT, 0), nmt});
	true ->
	    SDORx = ?COB_ID(?SDO_RX,Nid),
	    SDOTx = ?COB_ID(?SDO_TX,Nid),
	    ets:insert(T, {?COB_ID(?NMT, 0), nmt})
    end,
    ets:insert(T, {SDORx, {sdo_rx, SDOTx}}),
    ets:insert(T, {SDOTx, {sdo_tx, SDORx}}),
    T.

%% Create subscription table
create_sub_table() ->
    T = ets:new(sub_table, [public,ordered_set]),
    add_subscription(T, ?IX_COB_ID_SYNC_MESSAGE, self()),
    add_subscription(T, ?IX_COM_CYCLE_PERIOD, self()),
    add_subscription(T, ?IX_COB_ID_TIME_STAMP, self()),
    add_subscription(T, ?IX_COB_ID_EMERGENCY, self()),
    add_subscription(T, ?IX_SDO_SERVER_FIRST,?IX_SDO_SERVER_LAST, self()),
    add_subscription(T, ?IX_SDO_CLIENT_FIRST,?IX_SDO_CLIENT_LAST, self()),
    add_subscription(T, ?IX_RPDO_PARAM_FIRST, ?IX_RPDO_PARAM_LAST, self()),
    add_subscription(T, ?IX_TPDO_PARAM_FIRST, ?IX_TPDO_PARAM_LAST, self()),
    add_subscription(T, ?IX_TPDO_MAPPING_FIRST, ?IX_TPDO_MAPPING_LAST, self()),
    T.
    
add_subscription(Tab, Ix, Pid) ->
    add_subscription(Tab, Ix, Ix, Pid).

add_subscription(Tab, Ix1, Ix2, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					  Ix1 =< Ix2, 
					  (is_pid(Pid) orelse is_atom(Pid)) ->
    ?dbg("~p: add_subscription: ~7.16.0#:~7.16.0# for ~w\n", 
	 [?MODULE, Ix1, Ix2, Pid]),
    I = co_iset:new(Ix1, Ix2),
    case ets:lookup(Tab, Pid) of
	[] -> ets:insert(Tab, {Pid, I});
	[{_,ISet}] -> ets:insert(Tab, {Pid, co_iset:union(ISet, I)})
    end.

    
remove_subscriptions(Tab, Pid) ->
    ets:delete(Tab, Pid).

remove_subscription(Tab, Ix, Pid) ->
    remove_subscription(Tab, Ix, Ix, Pid).

remove_subscription(Tab, Ix1, Ix2, Pid) when Ix1 =< Ix2 ->
    ?dbg("~p: remove_subscription: ~7.16.0#:~7.16.0# for ~w\n", 
	 [?MODULE, Ix1, Ix2, Pid]),
    case ets:lookup(Tab, Pid) of
	[] -> ok;
	[{Pid,ISet}] -> 
	    case co_iset:difference(ISet, co_iset:new(Ix1, Ix2)) of
		[] ->
		    ?dbg("~p: remove_subscription: last index for ~w\n", 
			 [?MODULE, Pid]),
		    ets:delete(Tab, Pid);
		ISet1 -> 
		    ?dbg("~p: remove_subscription: new index set ~p for ~w\n", 
			 [?MODULE, ISet1,Pid]),
		    ets:insert(Tab, {Pid,ISet1})
	    end
    end.

subscriptions(Tab, Pid) when is_pid(Pid) ->
    case ets:lookup(Tab, Pid) of
	[] -> [];
	[{Pid, Iset, _Opts}] -> Iset
    end.

subscribers(Tab) ->
    lists:usort([Pid || {Pid, _Ixs} <- ets:tab2list(Tab)]).

inform_subscribers(I, Ctx) ->			
    lists:foreach(
      fun(Pid) ->
	      case self() of
		  Pid -> do_nothing;
		  _OtherPid ->
		      ?dbg("~s: inform_subscribers: Sending object changed to ~p\n", 
			   [Ctx#co_ctx.name, Pid]),
		      gen_server:cast(Pid, {object_changed, I}) 
	      end
      end,
      lists:usort(subscribers(Ctx#co_ctx.sub_table, I) ++ 
		  reserver_pid(Ctx#co_ctx.res_table, I))).

create_res_table() ->
    ets:new(res_table, [public,ordered_set]).

reservations(Tab, Pid) when is_pid(Pid) ->
    lists:usort([Ix || {Ix, _M, P} <- ets:tab2list(Tab), P == Pid]).

	
add_reservation(_Tab, [], _Mod, _Pid) ->
    ok;
add_reservation(Tab, [Ix | Tail], Mod, Pid) ->
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ?dbg("~p: add_reservation: ~7.16.0# for ~w\n",[?MODULE, Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, Mod, dead}] ->  %% M or Mod ???
	    ok, 
	    ?dbg("~p: add_reservation: renewing ~7.16.0# for ~w\n",[?MODULE, Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, Pid}] -> 
	    ok, 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, OtherPid}] ->        
	    ?dbg("~p: add_reservation: index already reserved  by ~p\n", 
		 [?MODULE, OtherPid]),
	    {error, index_already_reserved}
    end.


add_reservation(_Tab, Ix1, Ix2, _Mod, Pid) when Ix1 < ?MAN_SPEC_MIN;
						Ix2 < ?MAN_SPEC_MIN->
    ?dbg("~p: add_reservation: not possible for ~7.16.0#:~7.16.0# for ~w\n", 
	 [?MODULE, Ix1, Ix2, Pid]),
    {error, not_possible_to_reserve};
add_reservation(Tab, Ix1, Ix2, Mod, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					      Ix1 =< Ix2, 
					      is_pid(Pid) ->
    ?dbg("~p: add_reservation: ~7.16.0#:~7.16.0# for ~w\n", 
	 [?MODULE, Ix1, Ix2, Pid]),
    add_reservation(Tab, lists:seq(Ix1, Ix2), Mod, Pid).
	    

   
remove_reservations(Tab, Pid) ->
    remove_reservation(Tab, reservations(Tab, Pid), Pid).

remove_reservation(_Tab, [], _Pid) ->
    ok;
remove_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg("~p: remove_reservation: ~7.16.0# for ~w\n", [?MODULE, Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, OtherPid}] -> 	    
	    ?dbg("~p: remove_reservation: index reserved by other pid ~p\n", 
		 [?MODULE, OtherPid]),
	    {error, index_reservered_by_other}
    end.

remove_reservation(Tab, Ix1, Ix2, Pid) when Ix1 =< Ix2 ->
    ?dbg("~p: remove_reservation: ~7.16.0#:~7.16.0# for ~w\n", 
	 [?MODULE, Ix1, Ix2, Pid]),
    remove_reservation(Tab, lists:seq(Ix1, Ix2), Pid).

reset_reservations(Tab, Pid) ->
    reset_reservation(Tab, reservations(Tab, Pid), Pid).

reset_reservation(_Tab, [], _Pid) ->
    ok;
reset_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg("~p: reset_reservation: ~7.16.0# for ~w\n", [?MODULE, Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    ets:insert(Tab, {Ix, M, dead}),
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, _M, OtherPid}] -> 	    
	    ?dbg("~p: reset_reservation: index reserved by other pid ~p\n", 
		 [?MODULE, OtherPid]),
	    {error, index_reservered_by_other}
    end.

reservers(Tab) ->
    lists:usort([Pid || {_Ix, _M, Pid} <- ets:tab2list(Tab)]).

reserver_pid(Tab, Ix) when ?is_index(Ix) ->
    case ets:lookup(Tab, Ix) of
	[] -> [];
	[{Ix, _Mod, Pid}] -> [Pid]
    end.

lookup_sdo_server(COBID, Ctx) ->
    case lookup_cobid(COBID, Ctx) of
	{sdo_rx, SDOTx} -> 
	    {SDOTx,COBID};
	undefined ->
	    if ?is_nodeid_extended(COBID) ->
		    NodeID = COBID band ?COBID_ENTRY_ID_MASK,
		    Tx = ?XCOB_ID(?SDO_TX,NodeID),
		    Rx = ?XCOB_ID(?SDO_RX,NodeID),
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    {Tx,Rx};
	       ?is_nodeid(COBID) ->
		    NodeID = COBID band 16#7F,
		    Tx = ?COB_ID(?SDO_TX,NodeID),
		    Rx = ?COB_ID(?SDO_RX,NodeID),
		    ets:insert(Ctx#co_ctx.cob_table, {Rx,{sdo_rx,Tx}}),
		    ets:insert(Ctx#co_ctx.cob_table, {Tx,{sdo_tx,Rx}}),
		    {Tx,Rx};
	       true ->
		    undefined
	    end;
	_ -> undefined
    end.

lookup_cobid(COBID, Ctx) ->
    case ets:lookup(Ctx#co_ctx.cob_table, COBID) of
	[{_,Entry}] -> Entry;
	[] -> undefined
    end.

%%
%% Update the Node map table (Serial => NodeId)
%%  Check if nmt entry for node id has a consistent Serial
%%  if not then remove bad mapping
%%
update_node_map(NodeId, Serial, Ctx) ->
    case ets:lookup(Ctx#co_ctx.nmt_table, NodeId) of
	[E] when E#nmt_entry.serial =/= Serial ->
	    %% remove old mapping
	    ets:delete(Ctx#co_ctx.node_map, E#nmt_entry.serial),
	    %% update new mapping
	    update_nmt_entry(NodeId, [{serial,Serial}], Ctx);
	_ ->
	    ok
    end,
    ets:insert(Ctx#co_ctx.node_map, {Serial,NodeId}),
    Ctx.
    
%%    
%% Update the NMT entry (NodeId => #nmt_entry { serial, vendor ... })
%%
update_nmt_entry(NodeId, Opts, Ctx) ->
    E = lookup_nmt_entry(NodeId, Ctx),
    E1 = update_nmt_entry(Opts, E),
    ets:insert(Ctx#co_ctx.nmt_table, E1),
    Ctx.


update_nmt_entry([{Key,Value}|Kvs],E) when is_record(E, nmt_entry) ->
    E1 = update_nmt_value(Key, Value,E),
    update_nmt_entry(Kvs,E1);
update_nmt_entry([], E) ->
    E#nmt_entry { time=now() }.

update_nmt_value(Key,Value,E) when is_record(E, nmt_entry) ->
    case Key of
	id       -> E#nmt_entry { time=Value};
	vendor   -> E#nmt_entry { vendor=Value};
	product  -> E#nmt_entry { product=Value};
	revision -> E#nmt_entry { revision=Value};
	serial   -> E#nmt_entry { serial=Value};
	state    -> E#nmt_entry { state=Value}
    end.
	    
%%
%% 
%%
cob_map(PdoEnt,_S) when is_integer(PdoEnt) ->
    PdoEnt;
cob_map({pdo,Invalid,Rtr,Ext,Cob}, _S) when is_integer(Cob) ->
    ?PDO_ENTRY(Invalid,Rtr,Ext,Cob);
cob_map({pdo,Invalid,Rtr,Ext,DynCob}, S) ->
    NodeId = dyn_nodeid(DynCob, S),
    Cob = case DynCob of
	      {cob,1}   -> ?PDO1_TX_ID(NodeId);
	      {cob,1,_} -> ?PDO1_TX_ID(NodeId);
	      {cob,2}   -> ?PDO2_TX_ID(NodeId);
	      {cob,2,_} -> ?PDO2_TX_ID(NodeId);
	      {cob,3}   -> ?PDO3_TX_ID(NodeId);
	      {cob,3,_} -> ?PDO3_TX_ID(NodeId);
	      {cob,4}   -> ?PDO4_TX_ID(NodeId);
	      {cob,4,_} -> ?PDO4_TX_ID(NodeId)
	  end,
    ?PDO_ENTRY(Invalid,Rtr,Ext,Cob).

	
%% dynamically lookup nodeid (by serial)
dyn_nodeid({cob,_I},Ctx) ->
    Ctx#co_ctx.id;
dyn_nodeid({cob,_I,Serial},Ctx) ->
    case ets:lookup(Ctx#co_ctx.node_map, Serial) of
	[]       -> ?COBID_ENTRY_INVALID;
	[{_,NodeId}] -> NodeId
    end.

%%
%% Unpack PDO Data from external TPDO 
%%
rpdo_unpack(I, Data, Ctx) ->
    case rpdo_mapping(I, Ctx#co_ctx.dict) of
	{pdo,{Ts,Is}} ->
	    {Ds,_}= co_codec:decode(Data, Ts),
	    rpdo_set(Is, Ds, Ctx);
	Error ->
	    io:format("rpdo_unpack: error = ~p\n", [Error]),
	    Ctx
    end.

rpdo_set([{IX,SI}|Is], [Value|Vs], Ctx) ->
    if IX >= ?BOOLEAN, IX =< ?UNSIGNED32 -> %% skip entry
	    rpdo_set(Is, Vs, Ctx);
       true ->
	    {_Reply,Ctx1} = set_dict_value(IX,SI,Value,Ctx),
	    rpdo_set(Is, Vs, Ctx1)
    end;
rpdo_set([], [], Ctx) ->
    Ctx.


%% read PDO mapping  => {ok,[{Type,Len}],[Index]}
pdo_mapping(IX, Dict) ->
    case co_dict:value(Dict, IX, 0) of
	{ok,N} when N >= 0, N =< 64 ->
	    pdo_mapping(pdo,IX,1,N,Dict);
	{ok,254} -> %% SAM-MPDO
	    {mpdo,[]};
	{ok,255} -> %% DAM-MPDO
	    pdo_mapping(mpdo,IX,1,1,Dict);
	Error ->
	    Error
    end.

pdo_mapping(MType,IX,SI,Sn,Dict) ->
    pdo_mapping(MType,IX,SI,Sn,[],[],Dict).

pdo_mapping(MType,_IX,SI,Sn,Ts,Is,_Dict) when SI > Sn ->
    {MType, {reverse(Ts),reverse(Is)}};
pdo_mapping(MType,IX,SI,Sn,Ts,Is,Dict) ->
    case co_dict:value(Dict,IX,SI) of
	{ok,Map} ->
	    ?dbg("~p: pdo_mapping: ~7.16.0#:~w = ~11.16.0#\n", 
		 [?MODULE, IX,SI,Map]),
	    Index = {I,S} = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	    ?dbg("~p: pdo_mapping: entry[~w] = {~7.16.0#:~w}\n", 
		 [?MODULE, SI,I,S]),
	    case co_dict:lookup_entry(Dict,Index) of
		{ok,E} ->
		    pdo_mapping(MType,IX,SI+1,Sn,
				[{E#dict_entry.type,?PDO_MAP_BITS(Map)}|Ts],
				[Index|Is], Dict);
		Error ->
		    Error
	    end;
	Error ->
	    ?dbg("~p: pdo_mapping: ~7.16.0#:~w = Error ~w\n", 
		 [?MODULE, IX,SI,Error]),
	    Error
    end.

%% Set error code - and send the emergency object (if defined)
%% FIXME: clear error list when code 0000
set_error(Error, Code, Ctx) ->
    case lists:member(Code, Ctx#co_ctx.error_list) of
	true -> 
	    Ctx;  %% condition already reported, do NOT send
	false ->
	    co_dict:direct_set(Ctx#co_ctx.dict,?IX_ERROR_REGISTER, 0, Error),
	    NewErrorList = update_error_list([Code | Ctx#co_ctx.error_list], 1, Ctx),
	    if Ctx#co_ctx.emcy_id =:= 0 ->
		    ok;
	       true ->
		    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.emcy_id),
		    Data = <<Code:16/little,Error,0,0,0,0,0>>,
		    Frame = #can_frame { id = FrameID, len=0, data=Data },
		    can:send(Frame)
	    end,
	    Ctx#co_ctx { error_list = NewErrorList }
    end.

update_error_list([], SI, Ctx) ->
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,0},
				       access = ?ACCESS_RW,
				       type  = ?UNSIGNED8,
				       value = SI }),
    [];
update_error_list(_Cs, SI, Ctx) when SI >= 254 ->
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,0},
				       access = ?ACCESS_RW,
				       type  = ?UNSIGNED8,
				       value = 254 }),
    [];
update_error_list([Code|Cs], SI, Ctx) ->
    %% FIXME: Code should be 16 bit MSB ?
    co_dict:update_entry(Ctx#co_ctx.dict,
			 #dict_entry { index = {?IX_PREDEFINED_ERROR_FIELD,SI},
				       access = ?ACCESS_RO,
				       type  = ?UNSIGNED32,
				       value = Code }),
    [Code | update_error_list(Cs, SI+1, Ctx)].
    



				       

%% Optionally start a timer
start_timer(0, _Type) -> false;
start_timer(Time, Type) -> erlang:start_timer(Time,self(),Type).

%% Optionally stop a timer and flush
stop_timer(false) -> false;
stop_timer(TimerRef) ->
    case erlang:cancel_timer(TimerRef) of
	false ->
	    receive
		{timeout,TimerRef,_} -> false
	    after 0 ->
		    false
	    end;
	_Remain -> false
    end.


time_of_day() ->
    now_to_time_of_day(now()).

set_time_of_day(Time) ->
    ?dbg("~p: set_time_of_day: ~p\n", [?MODULE, Time]),
    ok.

now_to_time_of_day({Sm,S0,Us}) ->
    S1 = Sm*1000000 + S0,
    D = S1 div ?SECS_PER_DAY,
    S = S1 rem ?SECS_PER_DAY,
    Ms = S*1000 + (Us  div 1000),
    Days = D + (?DAYS_FROM_0_TO_1970 - ?DAYS_FROM_0_TO_1984),
    #time_of_day { ms = Ms, days = Days }.

time_of_day_to_now(T) when is_record(T, time_of_day)  ->
    D = T#time_of_day.days + (?DAYS_FROM_0_TO_1984-?DAYS_FROM_0_TO_1970),
    Sec = D*?SECS_PER_DAY + (T#time_of_day.ms div 1000),
    USec = (T#time_of_day.ms rem 1000)*1000,
    {Sec div 1000000, Sec rem 1000000, USec}.
