%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen node.
%%%
%%% File    : co_node.erl <br/>
%%% Created: 10 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_node).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include("canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

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

%% Admin interface
-export([load_dict/1, load_dict/2]).
-export([save_dict/1, save_dict/2]).
-export([get_option/2, set_option/3]).

%% Application interface
-export([subscribe/2, unsubscribe/2]).
-export([reserve/3, unreserve/2]).
-export([my_subscriptions/1, my_subscriptions/2]).
-export([my_reservations/1, my_reservations/2]).
-export([all_subscribers/1, all_subscribers/2]).
-export([all_reservers/1, reserver/2]).
-export([object_event/2, pdo_event/2]).
-export([notify/3, notify/4]). %% To send MPOs

%% CANopen application internal
-export([add_entry/2, get_entry/2]).
-export([set/3, value/2]).
-export([store/6, fetch/6]).
-export([subscribers/2]).
-export([reserver_with_module/2]).
-export([tpdo_mapping/2, rpdo_mapping/2, tpdo_set/3, tpdo_value/2]).

%% Debug interface
-export([dump/1, dump/2, loop_data/1]).
-export([nodeid/1]).
-export([state/2]).
-export([direct_set/3]).

-import(lists, [foreach/2, reverse/1, seq/2, map/2, foldl/3]).

-define(BACKUP_FILE, filename:join(code:priv_dir(canopen), "backup.dict")).

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
%% @doc
%% Description: Starts the CANOpen node.
%%
%% Options: 
%%          {use_serial_as_nodeid, boolean()} 
%%          {short_nodeid, integer()} - 1-126
%%          {time_stamp,  timeout()}  - ( 60000 )  1m <br/>
%%          {sdo_timeout, timeout()}  - ( 1000 ) <br/>
%%          {blk_timeout, timeout()}  - ( 500 ) <br/>
%%          {pst, integer()}          - ( 16 ) <br/>
%%          {max_blksize, integer()}  - ( 74 = 518 bytes) <br/>
%%          {use_crc, boolean()}      - use crc for block (true) <br/>
%%          {readbufsize, integer()}  - size of buf when reading from app <br/>
%%          {load_ratio, float()}     - ratio when time to fill read_buf <br/> 
%%          {atomic_limit, integer()} - limit to size of atomic variable <br/>
%%          {debug, boolean()}        - Enable/Disable trace output<br/>
%%         
%% @end
%%--------------------------------------------------------------------
-spec start_link(list({serial, Serial::integer()} | 
		      {options, list({use_serial_as_nodeid, boolean()} |
				     {name, string()} |
				     {vendor, integer()} | 
				     {short_nodeid, integer()} |
				     {time_stamp,  timeout()} |  
				     {sdo_timeout, timeout()} |  
				     {blk_timeout, timeout()} |  
				     {pst, integer()} |          
				     {max_blksize, integer()} |  
				     {use_crc, boolean()} |
				     {readbufsize, integer()} |
				     {load_ratio, float()} |
				     {atomic_maxsize, integer()} |
				     {debug, boolean()})})) -> 
			{ok, Pid::pid()} | ignore | {error, Error::atom()}.

start_link(Args) ->
    ?dbg(node, "start_link: Args = ~p", [Args]),
        
    Serial = serial(proplists:get_value(serial, Args, 0)),
    Opts = proplists:get_value(options, Args, []),	    

    case verify_options(Opts) of
	ok ->
	    Name = name(Opts, Serial),
	    ?dbg(node, "Starting co_node with Name = ~p, Serial = ~.16#", 
		 [Name, Serial]),
	    gen_server:start({local, Name}, ?MODULE, {Serial,Name,Opts}, []);
	E ->
	    E
    end.

verify_options([]) ->
    ok;
verify_options([{Opt, Value} | Rest]) ->
    case verify_option(Opt, Value) of
	ok ->
	    verify_options(Rest);
	E ->
	    E
    end.
%%
%% Get serial number
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
%% @doc
%% Stops the CANOpen node.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(Identity::term()) -> ok | {error, Reason::atom()}.
				  
stop(Identity) ->
    gen_server:call(identity_to_pid(Identity), stop).

%%--------------------------------------------------------------------
%% @doc
%% Loads the default backup dict.
%%
%% @end
%%-------------------------------------------------------------------
-spec load_dict(Identity::term()) -> 
		       ok | {error, Error::atom()}.

load_dict(Identity) ->
    gen_server:call(identity_to_pid(Identity), {load_dict, ?BACKUP_FILE}).
    

%%--------------------------------------------------------------------
%% @doc
%% Loads a new Object Dictionary from File.
%%
%% @end
%%-------------------------------------------------------------------
-spec load_dict(Identity::term(), File::string()) -> 
		       ok | {error, Error::atom()}.

load_dict(Identity, File) ->
    gen_server:call(identity_to_pid(Identity), {load_dict, File}).
    

%%--------------------------------------------------------------------
%% @doc
%% Saves the Object Dictionary to a default backup file.
%%
%% @end
%%-------------------------------------------------------------------
-spec save_dict(Identity::term()) -> 
		       ok | {error, Error::atom()}.

save_dict(Identity) ->
    gen_server:call(identity_to_pid(Identity), {save_dict, ?BACKUP_FILE}).
    

%%--------------------------------------------------------------------
%% @doc
%% Saves the Object Dictionary to a file.
%%
%% @end
%%-------------------------------------------------------------------
-spec save_dict(Identity::term(), File::string()) -> 
		       ok | {error, Error::atom()}.

save_dict(Identity, File) ->
    gen_server:call(identity_to_pid(Identity), {save_dict, File}).
    

%%--------------------------------------------------------------------
%% @doc
%% Gets value of option variable. (For testing)
%%
%% @end
%%--------------------------------------------------------------------
-spec get_option(Identity::term(), Option::atom()) -> 
			{ok, {option, Value::term()}} | 
			{error, unkown_option}.

get_option(Identity, Option) ->
    gen_server:call(identity_to_pid(Identity), {option, Option}).

%%--------------------------------------------------------------------
%% @doc
%% Sets value of option variable. (For testing)
%%
%% @end
%%--------------------------------------------------------------------
-spec set_option(Identity::term(), Option::atom(), NewValue::term()) -> 
			ok | {error, Reason::string()}.

set_option(Identity, Option, NewValue) ->
    ?dbg(node, "set_option: Option = ~p, NewValue = ~p",[Option, NewValue]),
    case verify_option(Option, NewValue) of
	ok ->
	    gen_server:call(identity_to_pid(Identity), {option, Option, NewValue});	    
	{error, _Reason} = Error ->
	    ?dbg(node, "set_option: option rejected, reason = ~p",[_Reason]),
	    Error
    end.

verify_option(Option, NewValue) 
  when Option == vendor;
       Option == max_blksize;
       Option == readbufsize;
       Option == time_stamp; 
       Option == sdo_timeout;
       Option == blk_timeout;
       Option == atomic_limit ->
    if is_integer(NewValue) andalso NewValue > 0 ->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to a positive integer value."}
    end;
verify_option(Option, NewValue) 
  when Option == pst ->
    if is_integer(NewValue) andalso NewValue >= 0 ->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to a positive integer value or zero."}
    end;
verify_option(Option, NewValue) 
  when Option == short_nodeid ->
    if is_integer(NewValue) andalso NewValue >= 0 andalso NewValue < 127->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to an integer between 0 and 126."}
    end;
verify_option(Option, NewValue) 
  when Option == use_serial_as_nodeid;
       Option == use_crc;
       Option == debug ->
    if is_boolean(NewValue) ->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to true or false."}
    end;
verify_option(Option, NewValue) 
  when Option == load_ratio ->
    if is_float (NewValue) andalso NewValue > 0 andalso NewValue =< 1 ->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to a float value between 0 and 1."}
    end;
verify_option(Option, NewValue) 
  when Option == name ->
    if is_list(NewValue) orelse is_atom(NewValue)->
	    ok;
       true ->
	    {error, "Option " ++ atom_to_list(Option) ++ 
		 " can only be set to a string or an atom."}
    end;
verify_option(Option, _NewValue) ->
    {error, "Option " ++ atom_to_list(Option) ++ " unknown."}.

%%--------------------------------------------------------------------
%% @doc
%% Attches the calling process to the CANnode idenified by Identity.
%%
%% @end
%%--------------------------------------------------------------------
-spec attach(Identity::term()) -> {ok, Id::integer()} | {error, Error::atom()}.

attach(Identity) ->
    gen_server:call(identity_to_pid(Identity), {attach, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Detaches the calling process from the CANnode idenified by Identity.
%%
%% @end
%%--------------------------------------------------------------------
-spec detach(Identity::term()) -> ok | {error, Error::atom()}.

detach(Identity) ->
    gen_server:call(identity_to_pid(Identity), {detach, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Adds a subscription to changes of the Dictionary Object in position Index.<br/>
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribe(Identity::term(), Index::integer() | 
					  list(Index::integer())) -> 
		       ok | {error, Error::atom()}.

subscribe(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {subscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Removes a subscription to changes of the Dictionary Object in position Index.<br/>
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
-spec unsubscribe(Identity::term(), Index::integer() | 
					    list(Index::integer())) -> 
		       ok | {error, Error::atom()}.
unsubscribe(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {unsubscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Indexes for which the application idenified by Pid 
%% has subscriptions.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_subscriptions(Identity::term(), Pid::pid()) -> 
			      list(Index::integer()) | 
			      {error, Error::atom()}.
my_subscriptions(Identity, Pid) ->
    gen_server:call(identity_to_pid(Identity), {subscriptions, Pid}).

%%--------------------------------------------------------------------
%% @spec my_subscriptions(Identity) -> [Index] | {error, Error}
%%
%% @doc
%% Returns the Indexes for which the calling process has subscriptions.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_subscriptions(Identity::term()) -> 
			      list(Index::integer()) | 
			      {error, Error::atom()}.
my_subscriptions(Identity) ->
    gen_server:call(identity_to_pid(Identity), {subscriptions, self()}).

%%--------------------------------------------------------------------
%% @spec all_subscribers(Identity) -> [Pid] | {error, Error}
%%
%% @doc
%% Returns the Pids of all applications that subscribes to any Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_subscribers(Identity::term()) -> 
			     list(Pid::pid()) | 
			     {error, Error::atom()}.
all_subscribers(Identity) ->
    gen_server:call(identity_to_pid(Identity), {subscribers}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Pids of all applications that subscribes to Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_subscribers(Identity::term(), Ix::integer()) ->
			     list(Pid::pid()) | 
			     {error, Error::atom()}.

all_subscribers(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {subscribers, Ix}).

%%--------------------------------------------------------------------
%% @doc
%% Adds a reservation to an index.
%% Module:index_specification will be called if needed.
%% Index can also be a range {Index1, Index2}.
%%
%% @end
%%--------------------------------------------------------------------
-spec reserve(Identity::term(), Index::integer(), Module::atom()) -> 
		     ok | {error, Error::atom()}.

reserve(Identity, Ix, Module) ->
    gen_server:call(identity_to_pid(Identity), {reserve, Ix, Module, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Removes a reservation to changes of the Dictionary Object in position Index.
%% Index can also be a range {Index1, Index2}.
%%
%% @end
%%--------------------------------------------------------------------
-spec unreserve(Identity::term(), Index::integer()) -> 
		       ok | {error, Error::atom()}.
unreserve(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {unreserve, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Indexes for which Pid has reservations.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_reservations(Identity::term(), Pid::pid()) -> 
			     list(Index::integer()) | 
			     {error, Error::atom()}.

my_reservations(Identity, Pid) ->
    gen_server:call(identity_to_pid(Identity), {reservations, Pid}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Indexes for which the calling process has reservations.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_reservations(Identity::term()) ->
			     list(Index::integer()) | 
			     {error, Error::atom()}.

my_reservations(Identity) ->
    gen_server:call(identity_to_pid(Identity), {reservations, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Pids that has reserved any index.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_reservers(Identity::term()) ->
			   list(Pid::pid()) | {error, Error::atom()}.

all_reservers(Identity) ->
    gen_server:call(identity_to_pid(Identity), {reservers}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Pid that has reserved index if any.
%%
%% @end
%%--------------------------------------------------------------------
-spec reserver(Identity::term(), Ix::integer()) ->
		      list(Pid::pid()) | {error, Error::atom()}.

reserver(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {reserver, Ix}).

%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that an object has been updated so that any
%% subscribers can be informed.
%% @end
%%--------------------------------------------------------------------
-spec object_event(CoNodePid::pid(), Index::{Ix::integer(), Si::integer()}) ->
			  ok | {error, Error::atom()}.

object_event(CoNodePid, Index) ->
    gen_server:cast(CoNodePid, {object_event, Index}).

%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that a PDO should be transmitted.
%% @end
%%--------------------------------------------------------------------
-spec pdo_event(CoNode::pid() | integer(), CobId::integer()) ->
		       ok | {error, Error::atom()}.

pdo_event(CoNodePid, CobId) when is_pid(CoNodePid) ->
    gen_server:cast(CoNodePid, {pdo_event, CobId});
pdo_event(Identity, CobId) ->
    gen_server:cast(identity_to_pid(Identity), {pdo_event, CobId}).


%%--------------------------------------------------------------------
%% @doc
%% Adds Entry to the Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_entry(Identity::term(), Entry::record()) -> 
		       ok | {error, Error::atom()}.

add_entry(Identity, Ent) ->
    gen_server:call(identity_to_pid(Identity), {add_entry, Ent}).

%%--------------------------------------------------------------------
%% @doc
%% Gets the Entry at Index in Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec get_entry(Identity::term(), Index::integer()) -> 
		       ok | {error, Error::atom()}.

get_entry(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {get_entry,Ix}).

%%--------------------------------------------------------------------
%% @doc
%% Sets {Ix, Si} to Value.
%% @end
%%--------------------------------------------------------------------
-spec set(Identity::term(), 
	  Index::{Ix::integer(), Si::integer()} |integer(), 
	  Value::term()) -> 
		 ok | {error, Error::atom()}.

set(Identity, {Ix, Si} = I, Value) when ?is_index(Ix), ?is_subind(Si) ->
    gen_server:call(identity_to_pid(Identity), {set,I,Value});   
set(Identity, Ix, Value) when is_integer(Ix) ->
    set(Identity, {Ix, 0}, Value).

%%--------------------------------------------------------------------
%% @doc
%% Cache {Ix, Si} Value truncated to 64 bits.
%% @end
%%--------------------------------------------------------------------
-spec tpdo_set(Identity::term(), 
	       Index::{Ix::integer(), Si::integer()} | integer(), 
	       Value::term()) -> 
		      ok | {error, Error::atom()}.

tpdo_set(Identity, {Ix, Si} = I, Value) when ?is_index(Ix), ?is_subind(Si) ->
    ?dbg(node, "tpdo_set: Identity = ~.16#,  Ix = ~.16#:~w, Value = ~p",
	 [Identity, Ix, Si, Value]), 
    gen_server:call(identity_to_pid(Identity), {tpdo_set,I,Value});   
tpdo_set(Identity, Ix, Value) when is_integer(Ix) ->
    tpdo_set(Identity, {Ix, 0}, Value).

%%--------------------------------------------------------------------
%% @doc
%% Set raw value (used to update internal read only tables etc)
%% @end
%%--------------------------------------------------------------------
-spec direct_set(Identity::term(), 
		 Index::{Ix::integer(), Si::integer()} | integer(), 
		 Value::term()) -> 
		 ok | {error, Error::atom()}.

direct_set(Identity, {Ix, Si} = I, Value) when ?is_index(Ix), ?is_subind(Si) ->
    gen_server:call(identity_to_pid(Identity), {direct_set,I,Value});
direct_set(Identity, Ix, Value) when is_integer(Ix) ->
    direct_set(Identity, {Ix, 0}, Value).


%%--------------------------------------------------------------------
%% @doc
%% Gets Value for Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec value(Identity::term(), 
	    Index::{Ix::integer(), Si::integer()} | integer()) -> 
		   Value::term() | {error, Error::atom()}.

value(Identity, {Ix, Si} = I) when ?is_index(Ix), ?is_subind(Si)  ->
    gen_server:call(identity_to_pid(Identity), {value,I});
value(Identity, Ix) when is_integer(Ix) ->
    value(Identity, {Ix, 0}).

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
%% @doc
%% Starts a store session to store Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
-spec store(Identity::term() | atom(), Cobid::integer(), 
	    Index::integer(), SubInd::integer(), 
	    TransferMode:: block | segment,
	    Term::{data, binary()} | {app, Pid::pid(), Module::atom()}) ->
		   ok | {error, Error::atom()}.

store(Identity, COBID, IX, SI, TransferMode, Term) 
  when ?is_index(IX), ?is_subind(SI) ->
    ?dbg(node, "store: Identity = ~p, CobId = ~.16#, Ix = ~4.16.0B, Si = ~p, " ++
	     "Mode = ~p, Term = ~p", 
	 [Identity, COBID, IX, SI, TransferMode, Term]),
    Pid = identity_to_pid(Identity),
    gen_server:call(Pid, {store,TransferMode,COBID,IX,SI,Term}).


%%--------------------------------------------------------------------
%% @doc
%% Starts a fetch session to fetch Value at Index:Subind on remote node.
%%
%% @end
%%--------------------------------------------------------------------
-spec fetch(Identity::term() | atom(), Cobid::integer(), 
	    Index::integer(), SubInd::integer(),
 	    TransferMode:: block | segment,
	    Term::data | {app, Pid::pid(), Module::atom()}) ->
		   ok | {ok, Data::binary()} | {error, Error::atom()}.


fetch(Identity, COBID, IX, SI, TransferMode, Term)
  when ?is_index(IX), ?is_subind(SI) ->
    gen_server:call(identity_to_pid(Identity), {fetch,TransferMode,COBID,IX,SI,Term}).


%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump(Identity::term()) -> ok | {error, Error::atom()}.

dump(Identity) ->
    dump(Identity, all).

%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump(Identity::term(), Qualifier::all | no_dict) -> 
		  ok | {error, Error::atom()}.

dump(Identity, Qualifier) 
  when Qualifier == all;
       Qualifier == no_dict ->
    gen_server:call(identity_to_pid(Identity), {dump, Qualifier}).

%%--------------------------------------------------------------------
%% @doc
%% Dumps loop data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec loop_data(Identity::term()) -> ok | {error, Error::atom()}.

loop_data(Identity) ->
    gen_server:call(identity_to_pid(Identity), loop_data).

%%--------------------------------------------------------------------
%% @doc
%% Returns the co_nodes nodeid.
%%
%% @end
%%--------------------------------------------------------------------
-spec nodeid(Identity::term()) -> 
		    NodeId::integer() | {error, Error::atom()}.

nodeid(Identity) ->
    gen_server:call(identity_to_pid(Identity), nodeid).

%%--------------------------------------------------------------------
%% @doc
%% Sets the co_nodes state.
%%
%% @end
%%--------------------------------------------------------------------
-spec state(Identity::term(), State::operational | preoperational | stopped) -> 
		    NodeId::integer() | {error, Error::atom()}.

state(Identity, operational) ->
    gen_server:call(identity_to_pid(Identity), {state, ?Operational});
state(Identity, preoperational) ->
    gen_server:call(identity_to_pid(Identity), {state, ?PreOperational});
state(Identity, stopped) ->
    gen_server:call(identity_to_pid(Identity), {state, ?Stopped}).

%%--------------------------------------------------------------------
%% @doc
%% Send notification (from Nid). <br/>
%% SubInd is set to 0.<br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify(Nid::integer(), Ix::integer(), Value::term()) -> 
		    ok | {error, Error::atom()}.

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
-spec notify(Nid::integer(), Ix::integer(), Si::integer(), Value::term()) -> 
		    ok | {error, Error::atom()}.

notify(Nid,Index,Subind,Value) ->
    io:format("~p: notify: Nid = ~.16#, Index = ~7.16.0#:~w, Value = ~8.16.0B\n",
	      [self(), Nid, Index, Subind, Value]),

    if ?is_nodeid_extended(Nid) ->
	    ?dbg(node, "notify: Nid ~.16# is extended",[Nid]),
	    CobId = ?XCOB_ID(?PDO1_TX, Nid);
	true ->
	    ?dbg(node, "notify: Nid ~.16# is not extended",[Nid]),
	    CobId = ?COB_ID(?PDO1_TX, Nid)
    end,
    FrameID = ?COBID_TO_CANID(CobId),
    Frame = #can_frame { id=FrameID, len=0, 
			 data=(<<16#80,Index:16/little,Subind:8,Value:32/little>>) },
    ?dbg(node, "notify: Sending frame ~p from Nid = ~.16# (CobId = ~.16#, CanId = ~.16#)",
	 [Frame, Nid, CobId, FrameID]),
    can:send(Frame).

%%--------------------------------------------------------------------
%% @doc
%% Get the RPDO mapping. <br/>
%% Executing in calling process context.<br/>
%% @end
%%--------------------------------------------------------------------
-spec rpdo_mapping(Offset::integer(), Ctx::record()) -> 
			  Map::term() | {error, Error::atom()}.

rpdo_mapping(Offset, Ctx) ->
    pdo_mapping(Offset+?IX_RPDO_MAPPING_FIRST, Ctx).

%%--------------------------------------------------------------------
%% @doc
%% Get the TPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec tpdo_mapping(Offset::integer(), Ctx::record()) -> 
			  Map::term() | {error, Error::atom()}.

tpdo_mapping(Offset, Ctx) ->
    pdo_mapping(Offset+?IX_TPDO_MAPPING_FIRST, Ctx).

%%--------------------------------------------------------------------
%% @doc
%% Get all subscribers in Tab for Index. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribers(Tab::reference(), Index::integer()) -> 
			 list(Pid::pid()) | {error, Error::atom()}.

subscribers(Tab, Ix) when ?is_index(Ix) ->
    ets:foldl(
      fun({ID,ISet}, Acc) ->
	      case co_iset:member(Ix, ISet) of
		  true -> [ID|Acc];
		  false -> Acc
	      end
      end, [], Tab).

%%--------------------------------------------------------------------
%% @doc
%% Get the reserver in Tab for Index if any. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec reserver_with_module(Tab::reference(), Index::integer()) -> 
				  {Pid::pid(), Mod::atom()} | [].

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
%% @doc
%% Description: Initiates the server
%% @end
%%--------------------------------------------------------------------
-spec init({Identity::term(), NodeName::atom(), Opts::list(term())}) -> 
		  {ok, State::record()} |
		  {ok, State::record(), Timeout::integer()} |
		  ignore               |
		  {stop, Reason::atom()}.


init({Serial, NodeName, Opts}) ->
    can_router:start(),
    can_udp:start(0),

    %% Trace output enable/disable
    put(dbg, proplists:get_value(debug,Opts,false)), 

    co_proc:reg(Serial),

    {ShortNodeId, ExtNodeId} = nodeids(Serial,Opts),
    reg({short_nodeid, ShortNodeId}),
    reg({ext_nodeid, ExtNodeId}),
    reg({name, NodeName}),

    Dict = create_dict(),
    SubTable = create_sub_table(),
    ResTable =  ets:new(co_res_table, [public,ordered_set]),
    TpdoCache = ets:new(co_tpdo_cache, [public,ordered_set]),
    SdoCtx = #sdo_ctx {
      timeout         = proplists:get_value(sdo_timeout,Opts,1000),
      blk_timeout     = proplists:get_value(blk_timeout,Opts,500),
      pst             = proplists:get_value(pst,Opts,16),
      max_blksize     = proplists:get_value(max_blksize,Opts,7),
      use_crc         = proplists:get_value(use_crc,Opts,true),
      readbufsize     = proplists:get_value(readbufsize,Opts,1024),
      load_ratio      = proplists:get_value(load_ratio,Opts,0.5),
      atomic_limit    = proplists:get_value(atomic_limit,Opts,1024),
      debug           = proplists:get_value(debug,Opts,false),
      dict            = Dict,
      sub_table       = SubTable,
      res_table       = ResTable
     },
    TpdoCtx = #tpdo_ctx {
      dict            = Dict,
      tpdo_cache      = TpdoCache,
      res_table       = ResTable
     },
    CobTable = create_cob_table(ExtNodeId, ShortNodeId),
    Ctx = #co_ctx {
      ext_nodeid = ExtNodeId,
      short_nodeid = ShortNodeId,
      name   = NodeName,
      vendor = proplists:get_value(vendor,Opts,0),
      serial = Serial,
      state  = ?Initialisation,
      node_map = ets:new(co_node_map, [{keypos,1}]),
      nmt_table = ets:new(co_nmt_table, [{keypos,#nmt_entry.id}]),
      sub_table = SubTable,
      res_table = ResTable,
      dict = Dict,
      tpdo_cache = TpdoCache,
      tpdo = TpdoCtx,
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

    case load_dict_init(proplists:get_value(dict_file, Opts), Ctx) of
	{ok, Ctx1} ->
	    process_flag(trap_exit, true),
	    if ShortNodeId =:= 0 ->
		    {ok, Ctx1#co_ctx { state = ?Operational }};
	       true ->
		    {ok, reset_application(Ctx1)}
	    end;
	{error, Reason} ->
	    io:format("WARNING! ~p: Loading of dict failed, exiting\n", 
		      [Ctx#co_ctx.name]),
	    {stop, Reason}
    end.

nodeids(Serial, Opts) ->
    {proplists:get_value(short_nodeid,Opts),
     case proplists:get_value(use_serial_as_nodeid,Opts,false) of
	 false -> undefined;
	 true  -> (Serial bsr 8) bor ?COBID_ENTRY_EXTENDED
     end}.

reg({_, undefined}) ->	    
    do_nothing;
reg(Term) ->	
    co_proc:reg(Term).
%%
%%
%%
reset_application(Ctx) ->
    io:format("Node '~s' id=~w,~w reset_application\n", 
	      [Ctx#co_ctx.name, Ctx#co_ctx.ext_nodeid, Ctx#co_ctx.short_nodeid]),
    reset_communication(Ctx).

reset_communication(Ctx) ->
    io:format("Node '~s' id=~w,~w reset_communication\n",
	      [Ctx#co_ctx.name, Ctx#co_ctx.ext_nodeid, Ctx#co_ctx.short_nodeid]),
    initialization(Ctx).

initialization(Ctx=#co_ctx {name=Name, short_nodeid=SNodeId, ext_nodeid=XNodeId}) ->
    io:format("Node '~s' id=~w,~w initialization\n",
	      [Name, XNodeId, SNodeId]),

    %% ??
    if XNodeId =/= undefined ->
	    can:send(#can_frame { id = ?NODE_GUARD_ID(XNodeId),
				  len = 1, data = <<0>> });
       true ->
	    do_nothing
    end,
    if SNodeId =/= undefined ->
	    can:send(#can_frame { id = ?NODE_GUARD_ID(SNodeId),
				  len = 1, data = <<0>> });
       true ->
	    do_nothing
    end,
	   
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

handle_call({set,{IX,SI},Value}, _From, Ctx) ->
    {Reply,Ctx1} = set_dict_value(IX,SI,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({tpdo_set,I,Value}, _From, Ctx) ->
    {Reply,Ctx1} = set_tpdo_value(I,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({direct_set,{IX,SI},Value}, _From, Ctx) ->
    {Reply,Ctx1} = direct_set_dict_value(IX,SI,Value,Ctx),
    {reply, Reply, Ctx1};
handle_call({value,{Ix, Si}}, _From, Ctx) ->
    Result = co_dict:value(Ctx#co_ctx.dict, Ix, Si),
    {reply, Result, Ctx};

handle_call({store,Mode,COBID,IX,SI,Term}, From, Ctx) ->
    case lookup_sdo_server(COBID,Ctx) of
	ID={Tx,Rx} ->
	    ?dbg(node, "~s: store: ID = ~p", [Ctx#co_ctx.name,ID]),
	    case co_sdo_cli_fsm:store(Ctx#co_ctx.sdo,Mode,From,Tx,Rx,IX,SI,Term) of
		{error, Reason} ->
		    ?dbg(node,"~s: unable to start co_sdo_cli_fsm: ~p", 
			 [Ctx#co_ctx.name, Reason]),
		    {reply, Reason, Ctx};
		{ok, Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    ?dbg(node, "~s: store: added session id=~p", 
			 [Ctx#co_ctx.name, ID]),
		    Sessions = Ctx#co_ctx.sdo_list,
		    {noreply, Ctx#co_ctx { sdo_list = [S|Sessions]}}
	    end;
	undefined ->
	    {reply, {error, badarg}, Ctx}
    end;

handle_call({fetch,Mode,COBID,IX,SI, Term}, From, Ctx) ->
    case lookup_sdo_server(COBID,Ctx) of
	ID={Tx,Rx} ->
	    ?dbg(node, "~s: fetch: ID = ~p", [Ctx#co_ctx.name,ID]),
	    case co_sdo_cli_fsm:fetch(Ctx#co_ctx.sdo,Mode,From,Tx,Rx,IX,SI,Term) of
		{error, Reason} ->
		    io:format("WARNING!" 
			      "~s: unable to start co_sdo_cli_fsm: ~p\n", 
			      [Ctx#co_ctx.name,Reason]),
		    {reply, Reason, Ctx};
		{ok, Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    S = #sdo { id=ID, pid=Pid, mon=Mon },
		    ?dbg(node, "~s: fetch: added session id=~p", 
			 [Ctx#co_ctx.name, ID]),
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

handle_call({save_dict, File}, _From, Ctx=#co_ctx {dict = Dict}) ->
    case co_dict:to_file(Dict, File) of
	ok ->
	    {reply, ok, Ctx};
	{error, Error} ->
	    {reply, Error, Ctx}
    end;

handle_call({attach,Pid}, _From, Ctx) when is_pid(Pid) ->
    case lists:keysearch(Pid, #app.pid, Ctx#co_ctx.app_list) of
	false ->
	    Mon = erlang:monitor(process, Pid),
	    App = #app { pid=Pid, mon=Mon },
	    Ctx1 = Ctx#co_ctx { app_list = [App |Ctx#co_ctx.app_list] },
	    {reply, {ok, Ctx1#co_ctx.ext_nodeid}, Ctx1};
	{value,_} ->
	    {reply, {error, already_attached, Ctx#co_ctx.ext_nodeid}, Ctx}
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

handle_call({dump, Qualifier}, _From, Ctx) ->
    io:format("   NAME: ~p\n", [Ctx#co_ctx.name]),
    if Ctx#co_ctx.short_nodeid =/= undefined ->
	    io:format(" NODEID: ~8.16.0B\n", [Ctx#co_ctx.short_nodeid]);
       true ->
	    io:format(" NODEID: ~p\n", [Ctx#co_ctx.short_nodeid])
    end,

    if Ctx#co_ctx.short_nodeid =/= undefined ->
	    io:format("XNODEID: ~8.16.0B\n", [Ctx#co_ctx.ext_nodeid]);
       true ->
	    io:format("XNODEID: ~p\n", [Ctx#co_ctx.ext_nodeid])
    end,
    io:format(" VENDOR: ~8.16.0B\n", [Ctx#co_ctx.vendor]),
    io:format(" SERIAL: ~8.16.0B\n", [Ctx#co_ctx.serial]),
    io:format("  STATE: ~s\n", [co_format:state(Ctx#co_ctx.state)]),

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
    io:format("---- TPDO CACHE ----\n"),
    ets:foldl(
      fun({{Ix,Si}, Value},_) ->
	      io:format("~7.16.0#:~w = ~p\n",[Ix, Si, Value])
      end, ok, Ctx#co_ctx.tpdo_cache),
    io:format("---------PROCESSES----------\n"),
    lists:foreach(
      fun(Process) ->
	      case Process of
		  T when is_record(T, tpdo) ->
		      io:format("tpdo process ~p\n",[T]);
		  A when is_record(A, app) ->
		      io:format("app process ~p\n",[A]);
		  S when is_record(S, sdo) ->
		      io:format("sdo process ~p\n",[S])
	      end
      end,
      Ctx#co_ctx.tpdo_list ++ Ctx#co_ctx.app_list ++ Ctx#co_ctx.sdo_list),
    if Qualifier == all ->
	    io:format("---------DICT----------\n"),
	    co_dict:to_fd(Ctx#co_ctx.dict, user),
	    io:format("------------------------\n");
       true ->
	    do_nothing
    end,
    {reply, ok, Ctx};

handle_call(loop_data, _From, Ctx) ->
    io:format("  LoopData: ~p\n", [Ctx]),
    {reply, ok, Ctx};

handle_call({option, Option}, _From, Ctx) ->
    Reply = case Option of
		name -> {Option, Ctx#co_ctx.name};
		short_nodeid -> {Option, Ctx#co_ctx.short_nodeid};
		ext_nodeid -> {Option, Ctx#co_ctx.ext_nodeid};
		use_serial_as_nodeid -> {Option, true};
		sdo_timeout ->  {Option, Ctx#co_ctx.sdo#sdo_ctx.timeout};
		blk_timeout -> {Option, Ctx#co_ctx.sdo#sdo_ctx.blk_timeout};
		pst ->  {Option, Ctx#co_ctx.sdo#sdo_ctx.pst};
		max_blksize -> {Option, Ctx#co_ctx.sdo#sdo_ctx.max_blksize};
		use_crc -> {Option, Ctx#co_ctx.sdo#sdo_ctx.use_crc};
		readbufsize -> {Option, Ctx#co_ctx.sdo#sdo_ctx.readbufsize};
		load_ratio -> {Option, Ctx#co_ctx.sdo#sdo_ctx.load_ratio};
		atomic_limit -> {Option, Ctx#co_ctx.sdo#sdo_ctx.atomic_limit};
		time_stamp -> {Option, Ctx#co_ctx.time_stamp_time};
		debug -> {Option, Ctx#co_ctx.sdo#sdo_ctx.debug};
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    ?dbg(node, "~s: handle_call: option = ~p, reply = ~w", 
	 [Ctx#co_ctx.name, Option, Reply]),    
    {reply, Reply, Ctx};
handle_call({option, Option, NewValue}, _From, Ctx) ->
    ?dbg(node, "~s: handle_call: option = ~p, new value = ~p", 
	 [Ctx#co_ctx.name, Option, NewValue]),    
    Reply = case Option of
		name -> Ctx#co_ctx {name = NewValue}; %% Reg new name ??
		short_nodeid -> Ctx#co_ctx {short_nodeid = NewValue}; %% Reg new nodeid ??
		sdo_timeout -> Ctx#co_ctx.sdo#sdo_ctx {timeout = NewValue};
		blk_timeout -> Ctx#co_ctx.sdo#sdo_ctx {blk_timeout = NewValue};
		pst ->  Ctx#co_ctx.sdo#sdo_ctx {pst = NewValue};
		max_blksize -> Ctx#co_ctx.sdo#sdo_ctx {max_blksize = NewValue};
		use_crc -> Ctx#co_ctx.sdo#sdo_ctx {use_crc = NewValue};
		readbufsize -> Ctx#co_ctx.sdo#sdo_ctx {readbufsize = NewValue};
		load_ratio -> Ctx#co_ctx.sdo#sdo_ctx {load_ratio = NewValue};
		atomic_limit -> Ctx#co_ctx.sdo#sdo_ctx {atomic_limit = NewValue};
		time_stamp -> Ctx#co_ctx {time_stamp_time = NewValue};
		use_serial_as_nodeid -> 
		    if NewValue == true ->
			    Ctx;
		       true ->
			    {error, "Option " ++ atom_to_list(Option) ++
				 " can only be true."}
		    end;
		debug -> put(dbg, NewValue),
			 Ctx#co_ctx.sdo#sdo_ctx {debug = NewValue};
		_Other -> {error, "Unknown option " ++ atom_to_list(Option)}
	    end,
    case Reply of
	SdoCtx when is_record(SdoCtx, sdo_ctx) ->
	    {reply, ok, Ctx#co_ctx {sdo = SdoCtx}};
	NewCtx when is_record(NewCtx, co_ctx) ->
	    {reply, ok, NewCtx};
	{error, _Reason} ->
	    {reply, Reply, Ctx}
    end;
handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};

handle_call(nodeid, _From, Ctx) ->
    {reply, Ctx#co_ctx.ext_nodeid, Ctx};

handle_call({state, State}, _From, Ctx) ->
    broadcast_state(State, Ctx),
    {reply, ok, Ctx#co_ctx {state = State}};

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
handle_cast({object_event, {Ix, _Si}}, Ctx) ->
    ?dbg(node, "~s: handle_cast: object_event, index = ~.16B:~p", 
	 [Ctx#co_ctx.name, Ix, _Si]),
    inform_subscribers(Ix, Ctx),
    {noreply, Ctx};
handle_cast({pdo_event, CobId}, Ctx) ->
    ?dbg(node, "~s: handle_cast: pdo_event, CobId = ~.16B", 
	 [Ctx#co_ctx.name, CobId]),
    case lists:keysearch(CobId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	{value, T} ->
	    co_tpdo:transmit(T#tpdo.pid),
	    {noreply,Ctx};
	_ ->
	    ?dbg(node, "~s: handle_cast: pdo_event, no tpdo process found", 
		 [Ctx#co_ctx.name]),
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
    ?dbg(node, "~s: handle_info: CAN frame received", [Ctx#co_ctx.name]),
    Ctx1 = handle_can(Frame, Ctx),
    {noreply, Ctx1};

handle_info({timeout,Ref,sync}, Ctx) when Ref =:= Ctx#co_ctx.sync_tmr ->
    %% Send a SYNC frame
    %% FIXME: check that we still are sync producer?
    ?dbg(node, "~s: handle_info: sync timeout received", [Ctx#co_ctx.name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.sync_id),
    Frame = #can_frame { id=FrameID, len=0, data=(<<>>) },
    can:send(Frame),
    ?dbg(node, "~s: handle_info: Sent sync", [Ctx#co_ctx.name]),
    Ctx1 = Ctx#co_ctx { sync_tmr = start_timer(Ctx#co_ctx.sync_time, sync) },
    {noreply, Ctx1};

handle_info({timeout,Ref,time_stamp}, Ctx) when Ref =:= Ctx#co_ctx.time_stamp_tmr ->
    %% FIXME: Check that we still are time stamp producer
    ?dbg(node, "~s: handle_info: time_stamp timeout received", [Ctx#co_ctx.name]),
    FrameID = ?COBID_TO_CANID(Ctx#co_ctx.time_stamp_id),
    Time = time_of_day(),
    Data = co_codec:encode(Time, ?TIME_OF_DAY),
    Size = byte_size(Data),
    Frame = #can_frame { id=FrameID, len=Size, data=Data },
    can:send(Frame),
    ?dbg(node, "~s: handle_info: Sent time stamp ~p", [Ctx#co_ctx.name, Time]),
    Ctx1 = Ctx#co_ctx { time_stamp_tmr = start_timer(Ctx#co_ctx.time_stamp_time, time_stamp) },
    {noreply, Ctx1};

handle_info({'DOWN',Ref,process,_Pid,Reason}, Ctx) ->
    ?dbg(node, "~s: handle_info: DOWN for process ~p received", 
	 [Ctx#co_ctx.name, _Pid]),
    Ctx1 = handle_sdo_processes(Ref, Reason, Ctx),
    Ctx2 = handle_app_processes(Ref, Ctx1),
    Ctx3 = handle_tpdo_processes(Ref, Ctx2),
    {noreply, Ctx3};

handle_info(_Info, Ctx) ->
    ?dbg(node, "~s: handle_info: unknown info received", [Ctx#co_ctx.name]),
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
    %% Stop all apps ??
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      ?dbg(node, "~s: terminate: Killing app with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.app_list),

    %% Stop all tpdo-servers ??
    lists:foreach(
      fun(T) ->
	      case T#tpdo.pid of
		  Pid -> 
		      ?dbg(node, "~s: terminate: Killing TPDO with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
			  %% Or gen_server:cast(Pid, co_node_terminated) ?? 
		      exit(Pid, co_node_terminated)
	      end
      end,
      Ctx#co_ctx.tpdo_list),

    case co_proc:alive() of
	true -> co_proc:clear();
	false -> do_nothing
    end,
   ?dbg(node, "~s: terminate: cleaned up, exiting", [Ctx#co_ctx.name]),
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
%%% Support functions
%%--------------------------------------------------------------------

%%
%% Convert an identity to a pid
%%
identity_to_pid(Serial) when is_integer(Serial) ->
    list_to_atom(co_lib:serial_to_string(Serial));
identity_to_pid(Pid) when is_pid(Pid) ->
    Pid;
identity_to_pid(Term) ->
    co_proc:lookup(Term).

%% Needed ???
call_node(Identity, Msg) ->
    case identity_to_pid(Identity) of
	Pid when is_pid(Pid) -> gen_server:call(Pid, Msg);
	{error, _R} = E -> E 
    end.
	    

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
create_cob_table(ExtNid, ShortNid) ->
    T = ets:new(co_cob_table, [public]),

    if ExtNid =/= undefined ->
	    XSDORx = ?XCOB_ID(?SDO_RX,ExtNid),
	    XSDOTx = ?XCOB_ID(?SDO_TX,ExtNid),
	    ets:insert(T, {XSDORx, {sdo_rx, XSDOTx}}),
	    ets:insert(T, {XSDOTx, {sdo_tx, XSDORx}}),
	    ets:insert(T, {?XCOB_ID(?NMT, 0), nmt}),
	    ?dbg(node, "create_cob_table: XNid=~w, XSDORx=~w, XSDOTx=~w", 
		 [ExtNid,XSDORx,XSDOTx]);
	true ->
	    do_nothing
    end,
    if ShortNid =/= undefined ->	
	    SDORx = ?COB_ID(?SDO_RX,ShortNid),
	    SDOTx = ?COB_ID(?SDO_TX,ShortNid),
	    ets:insert(T, {SDORx, {sdo_rx, SDOTx}}),
	    ets:insert(T, {SDOTx, {sdo_tx, SDORx}}),
	    ets:insert(T, {?COB_ID(?NMT, 0), nmt}),
	    ?dbg(node, "create_cob_table: ShortNid=~w, SDORx=~w, SDOTx=~w", 
		 [ShortNid,SDORx,SDOTx]);
	true ->
	    do_nothing
    end,
    T.

%%
%% Create subscription table
%%
create_sub_table() ->
    T = ets:new(co_sub_table, [public,ordered_set]),
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
    
%%
%% Load a dictionary
%% 
%%
%% Load dictionary from file
%% FIXME: map
%%    IX_COB_ID_SYNC_MESSAGE  => cob_table
%%    IX_COB_ID_TIME_STAMP    => cob_table
%%    IX_COB_ID_EMERGENCY     => cob_table
%%    IX_SDO_SERVER_FIRST - IX_SDO_SERVER_LAST =>  cob_table
%%    IX_SDO_CLIENT_FIRST - IX_SDO_CLIENT_LAST =>  cob_table
%%    IX_RPDO_PARAM_FIRST - IX_RPDO_PARAM_LAST =>  cob_table
%% 
load_dict_init(undefined, Ctx) ->
    case filelib:is_regular(?BACKUP_FILE) of
	true -> load_dict_init(?BACKUP_FILE, Ctx);
	false -> {ok, Ctx}
    end;
load_dict_init(File, Ctx) ->
    case load_dict_internal(filename:join(code:priv_dir(canopen), File), Ctx) of
	{ok, NewCtx} -> {ok, NewCtx};
	{error, Error, _OldCtx} -> {error, Error}
    end.

load_dict_internal(File, Ctx) ->
    ?dbg(node, "~s: load_dict_internal: Loading file = ~p", 
	 [Ctx#co_ctx.name, File]),
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
	    ?dbg(node, "~s: load_dict_internal: Failed loading file, error = ~p", 
		 [Ctx#co_ctx.name, Error]),
	    {error, Error, Ctx}
    catch
	error:Reason ->
	    ?dbg(node, "~s: load_dict_internal: Failed loading file, reason = ~p", 
		 [Ctx#co_ctx.name, Reason]),

	    {error, Reason, Ctx}
    end.

%%
%% Update dictionary
%% Only valid for 'local' objects
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
    ?dbg(node, "~s: direct_set_dict_value: Ix = ~.16#:~w, Value = ~p",
	 [Ctx#co_ctx.name, IX, SI, Value]), 
    try co_dict:direct_set(Ctx#co_ctx.dict, IX,SI,Value) of
	ok -> {ok, handle_notify(IX, Ctx)};
	Error -> {Error, Ctx}
    catch
	error:Reason -> {{error,Reason}, Ctx}
    end.


%%
%% Handle can messages
%%
handle_can(Frame, Ctx) when ?is_can_frame_rtr(Frame) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg(node, "~s: handle_can: COBID=~8.16.0B", [Ctx#co_ctx.name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt  ->
	    %% Handle Node guard
	    Ctx;

	_Other ->
	    case lists:keysearch(COBID, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:rtr(T#tpdo.pid),
		    Ctx;
		_ -> 
		    Ctx
	    end
    end;
handle_can(Frame, Ctx) ->
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    ?dbg(node, "~s: handle_can: COBID=~8.16.0B", [Ctx#co_ctx.name, COBID]),
    case lookup_cobid(COBID, Ctx) of
	nmt        -> handle_nmt(Frame, Ctx);
	sync       -> handle_sync(Frame, Ctx);
	emcy       -> handle_emcy(Frame, Ctx);
	time_stamp -> handle_time_stamp(Frame, Ctx);
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
	    case Frame#can_frame.data of
		%% Test if MPDO
		<<F:1, Addr:7, Ix:16/little, Si:8, Data:32/little>> ->
		    case {F, Addr} of
			{1, 0} ->
			    %% DAM-MPDO, destination is a group
			    handle_dam_mpdo(Ctx, ?XNODE_ID(COBID), Ix, Si, Data);
			_Other ->
			    ?dbg(node, "~s: handle_can: frame not handled: "
				 "Frame = ~w", [Ctx#co_ctx.name, Frame]),
			    Ctx
		    end;
		_Other ->
		    ?dbg(node, "~s: handle_can: frame not handled: Frame = ~w", 
			 [Ctx#co_ctx.name, Frame]),
		    Ctx
	    end
    end.

%%
%% NMT 
%%
handle_nmt(M, Ctx) when M#can_frame.len >= 2 ->
    ?dbg(node, "~s: handle_nmt: ~p", [Ctx#co_ctx.name, M]),
    <<NodeId,Cs,_/binary>> = M#can_frame.data,
    if NodeId == 0; NodeId == Ctx#co_ctx.ext_nodeid ->
	    case Cs of
		?NMT_RESET_NODE ->
		    reset_application(Ctx);
		?NMT_RESET_COMMUNICATION ->
		    reset_communication(Ctx);
		?NMT_ENTER_PRE_OPERATIONAL ->
		    broadcast_state(?PreOperational, Ctx),
		    Ctx#co_ctx { state = ?PreOperational };
		?NMT_START_REMOTE_NODE ->
		    broadcast_state(?Operational, Ctx),
		    Ctx#co_ctx { state = ?Operational };
		?NMT_STOP_REMOTE_NODE ->
		    broadcast_state(?Stopped, Ctx),
		    Ctx#co_ctx { state = ?Stopped };
		_ ->
		    ?dbg(node, "~s: handle_nmt: unknown cs=~w", 
			 [Ctx#co_ctx.name, Cs]),
		    Ctx
	    end;
       true ->
	    %% not for me
	    Ctx
    end.


handle_node_guard(Frame, Ctx) when ?is_can_frame_rtr(Frame) ->
    ?dbg(node, "~s: handle_node_guard: request ~w", [Ctx#co_ctx.name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    if NodeId == 0; NodeId == Ctx#co_ctx.ext_nodeid ->
	    Data = Ctx#co_ctx.state bor Ctx#co_ctx.toggle,
	    can:send(#can_frame { id = ?NODE_GUARD_ID(Ctx#co_ctx.ext_nodeid),
				  len = 1,
				  data = <<Data>> }),
	    Toggle = Ctx#co_ctx.toggle bxor 16#80,
	    Ctx#co_ctx { toggle = Toggle };
       true ->
	    %% ignore, not for me
	    Ctx
    end;
handle_node_guard(Frame, Ctx) when Frame#can_frame.len >= 1 ->
    ?dbg(node, "~s: handle_node_guard: ~w", [Ctx#co_ctx.name,Frame]),
    NodeId = ?NODE_ID(Frame#can_frame.id),
    case Frame#can_frame.data of
	<<_Toggle:1, State:7, _/binary>> when NodeId =/= Ctx#co_ctx.ext_nodeid ->
	    %% Verify toggle if NodeId=slave and we are Ctx#co_ctx.ext_nodeid=master
	    update_nmt_entry(NodeId, [{state,State}], Ctx);
	_ ->
	    Ctx
    end.

%%
%% LSS
%% 
handle_lss(_M, Ctx) ->
    ?dbg(node, "~s: handle_lss: ~w", [Ctx#co_ctx.name,_M]),
    Ctx.

%%
%% SYNC
%%
handle_sync(_Frame, Ctx) ->
    ?dbg(node, "~s: handle_sync: ~w", [Ctx#co_ctx.name,_Frame]),
    lists:foreach(
      fun(T) -> co_tpdo:sync(T#tpdo.pid) end, Ctx#co_ctx.tpdo_list),
    Ctx.

%%
%% TIME STAMP - update local time offset
%%
handle_time_stamp(Frame, Ctx) ->
    ?dbg(node, "~s: handle_timestamp: ~w", [Ctx#co_ctx.name,Frame]),
    try co_codec:decode(Frame#can_frame.data, ?TIME_OF_DAY) of
	{T, _Bits} when is_record(T, time_of_day) ->
	    ?dbg(node, "~s: Got timestamp: ~p", [Ctx#co_ctx.name, T]),
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
    ?dbg(node, "~s: handle_emcy: ~w", [Ctx#co_ctx.name,_Frame]),
    Ctx.

%%
%% Recive PDO - unpack into the dictionary
%%
handle_rpdo(Frame, Offset, _COBID, Ctx) ->
    ?dbg(node, "~s: handle_rpdo: offset = ~p, frame = ~w", 
	 [Ctx#co_ctx.name, Offset, Frame]),
    rpdo_unpack(?IX_RPDO_MAPPING_FIRST + Offset, Frame#can_frame.data, Ctx).

%% CLIENT side:
%% SDO tx - here we receive can_node response
%% FIXME: conditional compile this
%%
handle_sdo_tx(Frame, Tx, Rx, Ctx) ->
    ?dbg(node, "~s: handle_sdo_tx: src=~p, ~s",
	      [Ctx#co_ctx.name, Tx,
	       co_format:format_sdo(co_sdo:decode_tx(Frame#can_frame.data))]),
    ID = {Tx,Rx},
    ?dbg(node, "~s: handle_sdo_tx: session id=~p", [Ctx#co_ctx.name, ID]),
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    ?dbg(node, "~s: handle_sdo_tx: session not found", [Ctx#co_ctx.name]),
	    %% no such session active
	    Ctx
    end.

%% SERVER side
%% SDO rx - here we receive client requests
%% FIXME: conditional compile this
%%
handle_sdo_rx(Frame, Rx, Tx, Ctx) ->
    ?dbg(node, "~s: handle_sdo_rx: ~s", 
	      [Ctx#co_ctx.name,
	       co_format:format_sdo(co_sdo:decode_rx(Frame#can_frame.data))]),
    ID = {Rx,Tx},
    Sessions = Ctx#co_ctx.sdo_list,
    case lists:keysearch(ID,#sdo.id,Sessions) of
	{value, S} ->
	    ?dbg(node, "~s: handle_sdo_rx: Frame sent to old process ~p", 
		 [Ctx#co_ctx.name,S#sdo.pid]),
	    gen_fsm:send_event(S#sdo.pid, Frame),
	    Ctx;
	false ->
	    %% FIXME: handle expedited and spurios frames here
	    %% like late aborts etc here !!!
	    case co_sdo_srv_fsm:start(Ctx#co_ctx.sdo,Rx,Tx) of
		{error, Reason} ->
		    io:format("WARNING!" 
			      "~p: unable to start co_sdo_srv_fsm: ~p\n",
			      [Ctx#co_ctx.name, Reason]),
		    Ctx;
		{ok,Pid} ->
		    Mon = erlang:monitor(process, Pid),
		    sys:trace(Pid, true),
		    ?dbg(node, "~s: handle_sdo_rx: Frame sent to new process ~p", 
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
    ?dbg(node, "~s: handle_dam_mpdo: Index = ~7.16.0#", [Ctx#co_ctx.name,Ix]),
    case lists:usort(subscribers(Ctx#co_ctx.sub_table, Ix) ++
		     reserver_pid(Ctx#co_ctx.res_table, Ix)) of
	[] ->
	    ?dbg(node, "~s: No subscribers for index ~7.16.0#", [Ctx#co_ctx.name, Ix]);
	PidList ->
	    lists:foreach(
	      fun(Pid) ->
		      case Pid of
			  dead ->
			      %% Warning ??
			      ?dbg(node, "~s: Process subscribing to index "
				   "~7.16.0# is dead", [Ctx#co_ctx.name, Ix]);
			  P when is_pid(P)->
			      ?dbg(node, "~s: Process ~p subscribes to index "
				   "~7.16.0#", [Ctx#co_ctx.name, Pid, Ix]),
			      Pid ! {notify, RId, Ix, Si, Data}
		      end
	      end, PidList)
    end,
    Ctx.

%%
%% Handle terminated processes
%%
handle_sdo_processes(Ref, Reason, Ctx) ->
    case lists:keysearch(Ref, #sdo.mon, Ctx#co_ctx.sdo_list) of
	{value,_S} ->
	    if Reason =/= normal ->
		    io:format("WARNING!" 
			      "~s: sdo session died: ~p\n", 
			      [Ctx#co_ctx.name, Reason]);
	       true ->
		    ok
	    end,
	    Sessions = lists:keydelete(Ref, #sdo.mon, Ctx#co_ctx.sdo_list),
	    Ctx#co_ctx { sdo_list = Sessions };
	false ->
	    Ctx
    end.

handle_app_processes(Ref, Ctx) ->
    case lists:keysearch(Ref, #app.mon, Ctx#co_ctx.app_list) of
	{value,A} ->
	    io:format("WARNING!" 
		      "~s: id=~w application died\n", 
		      [Ctx#co_ctx.name,A#app.pid]),
	    remove_subscriptions(Ctx#co_ctx.sub_table, A#app.pid), %% Or reset ??
	    reset_reservations(Ctx#co_ctx.res_table, A#app.pid),
	    %% FIXME: restart application? application_mod ?
	    Ctx#co_ctx { app_list = Ctx#co_ctx.app_list--[A]};
	false ->
	    Ctx
    end.

handle_tpdo_processes(Ref, Ctx) ->
    case lists:keysearch(Ref, #tpdo.mon, Ctx#co_ctx.tpdo_list) of
	{value,T} ->
	    io:format("WARNING!" 
		      "~s: id=~w tpdo process died\n", 
		      [Ctx#co_ctx.name,T#tpdo.pid]),
	    
	    case restart_tpdo(T, Ctx) of
		{error, not_found} ->
		    io:format("WARNING! ~s: not possible to restart " ++
				  "tpdo process for offset ~p\n", 
			      [Ctx#co_ctx.name,T#tpdo.offset]),
		    Ctx;
		NewT ->
		    ?dbg(node, "~s: handle_info: new tpdo process ~p started", 
			 [Ctx#co_ctx.name, NewT#tpdo.pid]),
		    Ctx#co_ctx { tpdo_list = [NewT | Ctx#co_ctx.tpdo_list]--[T]}
	    end;
	false ->
	    Ctx
    end.

%%
%% NMT requests (call from within node process)
%%
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

broadcast_state(State, #co_ctx {state = State}) ->
    %% No change
    ok;
broadcast_state(State, Ctx) ->
    ?dbg(node, "~s: broadcast_state: new state = ~p", [Ctx#co_ctx.name, State]),

    %% To all tpdo processes
    lists:foreach(
      fun(T) ->
	      case T#tpdo.pid of
		  Pid -> 
		      ?dbg(node, "~s: broadcast_state: to TPDO with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
		      gen_server:cast(Pid, {state, State}) 
	      end
      end,
      Ctx#co_ctx.tpdo_list),
    
    %% To all applications ??
    lists:foreach(
      fun(A) ->
	      case A#app.pid of
		  Pid -> 
		      ?dbg(node, "~s: broadcast_state: to app with pid = ~p", 
			   [Ctx#co_ctx.name, Pid]),
		      gen_server:cast(Pid, {state, State}) 
	      end
      end,
      Ctx#co_ctx.app_list).

    
%%
%% Dictionary entry has been updated
%% Emulate co_node as subscriber to dictionary updates
%%
handle_notify(I, Ctx) ->
    NewCtx = handle_notify1(I, Ctx),
    inform_subscribers(I, NewCtx),
    NewCtx.

handle_notify1(I, Ctx) ->
    ?dbg(node, "~s: handle_notify: Index=~7.16.0#",[Ctx#co_ctx.name, I]),
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
	    ?dbg(node, "~s: handle_notify: update RPDO offset=~7.16.0#", 
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
	    ?dbg(node, "~s: handle_notify: update TPDO: offset=~7.16.0#",
		 [Ctx#co_ctx.name, I - ?IX_TPDO_PARAM_FIRST]),
	    case load_pdo_parameter(I, (I-?IX_TPDO_PARAM_FIRST), Ctx) of
		undefined -> Ctx;
		Param ->
		    case update_tpdo(Param, Ctx) of
			{new, {_T,Ctx1}} ->
			    ?dbg(node, "~s: handle_notify: TPDO:new",
				 [Ctx#co_ctx.name]),
			    Ctx1;
			{existing,T} ->
			    ?dbg(node, "~s: handle_notify: TPDO:existing",
				 [Ctx#co_ctx.name]),
			    co_tpdo:update_param(T#tpdo.pid, Param),
			    Ctx;
			{deleted,Ctx1} ->
			    ?dbg(node, "~s: handle_notify: TPDO:deleted",
				 [Ctx#co_ctx.name]),
			    Ctx1;
			none ->
			    ?dbg(node, "~s: handle_notify: TPDO:none",
				 [Ctx#co_ctx.name]),
			    Ctx
		    end
	    end;
	_ when I >= ?IX_TPDO_MAPPING_FIRST, I =< ?IX_TPDO_MAPPING_LAST ->
	    Offset = I - ?IX_TPDO_MAPPING_FIRST,
	    ?dbg(node, "~s: handle_notify: update TPDO-MAP: offset=~w", 
		 [Ctx#co_ctx.name, Offset]),
	    J = ?IX_TPDO_PARAM_FIRST + Offset,
	    COBID = co_dict:direct_value(Ctx#co_ctx.dict,J,?SI_PDO_COB_ID),
	    case lists:keysearch(COBID, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
		{value, T} ->
		    co_tpdo:update_map(T#tpdo.pid),
		    Ctx;
		_ ->
		    Ctx
	    end;
	_ ->
	    ?dbg(node, "~s: handle_notify: index not in cob table ix=~7.16.0#", 
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
		    ?dbg(node, "~s: update_time_stamp: Timestamp server time=~p", 
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
		    ?dbg(node, "~s: update_time_stamp: Timestamp consumer", 
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
    

update_tpdo(P=#pdo_parameter {offset = Offset, cob_id = CId, valid = Valid}, Ctx) ->
    ?dbg(node, "~s: update_tpdo: pdo param for ~p", [Ctx#co_ctx.name, Offset]),
    case lists:keytake(CId, #tpdo.cob_id, Ctx#co_ctx.tpdo_list) of
	false ->
	    if Valid ->
		    {ok,Pid} = co_tpdo:start(Ctx#co_ctx.tpdo, P),
		    co_tpdo:debug(Pid, get(dbg)),
		    gen_server:cast(Pid, {state, Ctx#co_ctx.state}),
		    Mon = erlang:monitor(process, Pid),
		    T = #tpdo { offset = Offset,
				cob_id = CId,
				pid = Pid,
				mon = Mon },
		    TList = [T | Ctx#co_ctx.tpdo_list],
		    {new, {T, Ctx#co_ctx { tpdo_list = TList }}};
	       true ->
		    none
	    end;
	{value, T, TList} ->
	    if Valid ->
		    {existing, T};
	       true ->
		    erlang:demonitor(T#tpdo.mon),
		    co_tpdo:stop(T#tpdo.pid),
		    {deleted,Ctx#co_ctx { tpdo_list = TList }}
	    end
    end.

restart_tpdo(T=#tpdo {offset = Offset}, Ctx) ->
    case load_pdo_parameter(?IX_TPDO_PARAM_FIRST + Offset, Offset, Ctx) of
	undefined -> 
	    ?dbg(node, "~s: restart_tpdo: pdo param for ~p not found", 
		 [Ctx#co_ctx.name, Offset]),
	    {error, not_found};
	Param ->
	    {ok,Pid} = co_tpdo:start(Ctx#co_ctx.tpdo, Param),
	    co_tpdo:debug(Pid, get(dbg)),
	    gen_server:cast(Pid, {state, Ctx#co_ctx.state}),
	    Mon = erlang:monitor(process, Pid),
	    T#tpdo {pid = Pid, mon = Mon}
    end.



load_pdo_parameter(I, Offset, Ctx) ->
    ?dbg(node, "~s: load_pdo_parameter ~p + ~p", [Ctx#co_ctx.name, I, Offset]),
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



add_subscription(Tab, Ix, Pid) ->
    add_subscription(Tab, Ix, Ix, Pid).

add_subscription(Tab, Ix1, Ix2, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					  Ix1 =< Ix2, 
					  (is_pid(Pid) orelse is_atom(Pid)) ->
    ?dbg(node, "add_subscription: ~7.16.0#:~7.16.0# for ~w", 
	 [Ix1, Ix2, Pid]),
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
    ?dbg(node, "remove_subscription: ~7.16.0#:~7.16.0# for ~w", 
	 [Ix1, Ix2, Pid]),
    case ets:lookup(Tab, Pid) of
	[] -> ok;
	[{Pid,ISet}] -> 
	    case co_iset:difference(ISet, co_iset:new(Ix1, Ix2)) of
		[] ->
		    ?dbg(node, "remove_subscription: last index for ~w", 
			 [Pid]),
		    ets:delete(Tab, Pid);
		ISet1 -> 
		    ?dbg(node, "remove_subscription: new index set ~p for ~w", 
			 [ISet1,Pid]),
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
		      ?dbg(node, "~s: inform_subscribers: "
			   "Sending object event to ~p", 
			   [Ctx#co_ctx.name, Pid]),
		      gen_server:cast(Pid, {object_event, I}) 
	      end
      end,
      lists:usort(subscribers(Ctx#co_ctx.sub_table, I))).


reservations(Tab, Pid) when is_pid(Pid) ->
    lists:usort([Ix || {Ix, _M, P} <- ets:tab2list(Tab), P == Pid]).

	
add_reservation(_Tab, [], _Mod, _Pid) ->
    ok;
add_reservation(Tab, [Ix | Tail], Mod, Pid) ->
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ?dbg(node, "add_reservation: ~7.16.0# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, Mod, dead}] ->  %% M or Mod ???
	    ok, 
	    ?dbg(node, "add_reservation: renewing ~7.16.0# for ~w",[Ix, Pid]), 
	    ets:insert(Tab, {Ix, Mod, Pid}), 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, Pid}] -> 
	    ok, 
	    add_reservation(Tab, Tail, Mod, Pid);
	[{Ix, _M, _OtherPid}] ->        
	    ?dbg(node, "add_reservation: index already reserved  by ~p", 
		 [_OtherPid]),
	    {error, index_already_reserved}
    end.


add_reservation(_Tab, Ix1, Ix2, _Mod, _Pid) when Ix1 < ?MAN_SPEC_MIN;
						Ix2 < ?MAN_SPEC_MIN->
    ?dbg(node, "add_reservation: not possible for ~7.16.0#:~7.16.0# for ~w", 
	 [Ix1, Ix2, _Pid]),
    {error, not_possible_to_reserve};
add_reservation(Tab, Ix1, Ix2, Mod, Pid) when ?is_index(Ix1), ?is_index(Ix2), 
					      Ix1 =< Ix2, 
					      is_pid(Pid) ->
    ?dbg(node, "add_reservation: ~7.16.0#:~7.16.0# for ~w", 
	 [Ix1, Ix2, Pid]),
    add_reservation(Tab, lists:seq(Ix1, Ix2), Mod, Pid).
	    

   
remove_reservations(Tab, Pid) ->
    remove_reservation(Tab, reservations(Tab, Pid), Pid).

remove_reservation(_Tab, [], _Pid) ->
    ok;
remove_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg(node, "remove_reservation: ~7.16.0# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    remove_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    ?dbg(node, "remove_reservation: index reserved by other pid ~p", 
		 [_OtherPid]),
	    {error, index_reservered_by_other}
    end.

remove_reservation(Tab, Ix1, Ix2, Pid) when Ix1 =< Ix2 ->
    ?dbg(node, "remove_reservation: ~7.16.0#:~7.16.0# for ~w", 
	 [Ix1, Ix2, Pid]),
    remove_reservation(Tab, lists:seq(Ix1, Ix2), Pid).

reset_reservations(Tab, Pid) ->
    reset_reservation(Tab, reservations(Tab, Pid), Pid).

reset_reservation(_Tab, [], _Pid) ->
    ok;
reset_reservation(Tab, [Ix | Tail], Pid) ->
    ?dbg(node, "reset_reservation: ~7.16.0# for ~w", [Ix, Pid]),
    case ets:lookup(Tab, Ix) of
	[] -> 
	    ok, 
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, M, Pid}] -> 
	    ets:delete(Tab, Ix), 
	    ets:insert(Tab, {Ix, M, dead}),
	    reset_reservation(Tab, Tail, Pid);
	[{Ix, _M, _OtherPid}] -> 	    
	    ?dbg(node, "reset_reservation: index reserved by other pid ~p", 
		 [_OtherPid]),
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
    Ctx#co_ctx.ext_nodeid;
dyn_nodeid({cob,_I,Serial},Ctx) ->
    case ets:lookup(Ctx#co_ctx.node_map, Serial) of
	[]       -> ?COBID_ENTRY_INVALID;
	[{_,NodeId}] -> NodeId
    end.

%%
%% Callback functions for changes in tpdo elements
%% Truncate data to 64 bits
%%
set_tpdo_value(I,Value,Ctx) when is_binary(Value) andalso byte_size(Value) > 8 ->
    <<TruncValue:8/binary, _Rest/binary>> = Value,
    set_tpdo_value(I,TruncValue,Ctx);
set_tpdo_value(I,Value,Ctx)  when is_list(Value) andalso length(Value) > 16 ->
    %% ??
    set_tpdo_value(I,lists:sublist(Value,16),Ctx);
%% Other conversions ???
set_tpdo_value({_Ix, _Si} = I, Value, 
	       Ctx=#co_ctx {tpdo_cache = Cache, name = Name}) ->
    ?dbg(node, "~s: set_tpdo_value: Ix = ~.16#:~w, Value = ~p",
	 [Name, _Ix, _Si, Value]), 
    case ets:lookup(Cache, I) of
	[] ->
	    io:format("WARNING!" 
		      "~s: set_tpdo_value: unknown tpdo element\n", [Name]),
	    {{error,unknown_tpdo_element}, Ctx};
	[{I, OldValues}] ->
	    NewValues = case OldValues of
			    [0] -> [Value]; %% remove default
			    _List -> OldValues ++ [Value]
			end,
	    ?dbg(node, "~s: set_tpdo_value: old = ~p, new = ~p",
		 [Name, OldValues, NewValues]), 
	    try ets:insert(Cache,{I,NewValues}) of
		true -> {ok, Ctx}
	    catch
		error:Reason -> 
		    io:format("WARNING!" 
			      "~s: set_tpdo_value: insert of ~p failed, reason = ~w\n", 
			      [Name, NewValues, Reason]),
		    {{error,Reason}, Ctx}
	    end
    end.

%%
%% Unpack PDO Data from external TPDO/internal RPDO 
%%
rpdo_unpack(I, Data, Ctx) ->
    case pdo_mapping(I, Ctx#co_ctx.res_table, Ctx#co_ctx.dict, 
		     Ctx#co_ctx.tpdo_cache) of
	{rpdo,{Ts,Is}} ->
	    ?dbg(node, "~s: rpdo_unpack: data = ~w, ts = ~w, is = ~w", 
		 [Ctx#co_ctx.name, Data, Ts, Is]),
	    try co_codec:decode_pdo(Data, Ts) of
		{Ds, _} -> 
		    ?dbg(node, "rpdo_unpack: decoded data ~p", [Ds]),
		    rpdo_set(Is, Ds, Ts, Ctx)
	    catch error:_Reason ->
		    io:format("WARNING!" 
			      "~s: rpdo_unpack: decode failed = ~p\n", 
			      [Ctx#co_ctx.name, _Reason]),
		    Ctx
	    end;
	Error ->
	    io:format("WARNING!" 
		      "~s: rpdo_unpack: error = ~p\n", [Ctx#co_ctx.name, Error]),
	    Ctx
    end.

rpdo_set([{IX,SI}|Is], [Value|Vs], [Type|Ts], Ctx) ->
    if IX >= ?BOOLEAN, IX =< ?UNSIGNED32 -> %% skip entry
	    rpdo_set(Is, Vs, Ts, Ctx);
       true ->
	    {_Reply,Ctx1} = rpdo_value({IX,SI},Value,Type,Ctx),
	    rpdo_set(Is, Vs, Ts, Ctx1)
    end;
rpdo_set([], [], [], Ctx) ->
    Ctx.

%%
%% read PDO mapping  => {MapType,[{Type,Len}],[Index]}
%%
pdo_mapping(IX, _TpdoCtx=#tpdo_ctx {dict = Dict, res_table = ResTable, 
				   tpdo_cache = TpdoCache}) ->
    pdo_mapping(IX, ResTable, Dict, TpdoCache).
pdo_mapping(IX, ResTable, Dict, TpdoCache) ->
    ?dbg(node, "pdo_mapping: ~7.16.0#", [IX]),
    case co_dict:value(Dict, IX, 0) of
	{ok,N} when N >= 0, N =< 64 ->
	    MType = case IX of
			_TPDO when IX >= ?IX_TPDO_MAPPING_FIRST, 
				   IX =< ?IX_TPDO_MAPPING_LAST ->
			    tpdo;
			_RPDO when IX >= ?IX_RPDO_MAPPING_FIRST, 
				   IX =< ?IX_RPDO_MAPPING_LAST ->
			    rpdo
		    end,
	    pdo_mapping(MType,IX,1,N,ResTable,Dict, TpdoCache);
	{ok,254} -> %% SAM-MPDO
	    {mpdo,[]};
	{ok,255} -> %% DAM-MPDO
	    pdo_mapping(mpdo,IX,1,1,ResTable,Dict, TpdoCache);
	Error ->
	    Error
    end.

    
pdo_mapping(MType,IX,SI,Sn,ResTable,Dict,TpdoCache) ->
    pdo_mapping(MType,IX,SI,Sn,[],[],ResTable,Dict,TpdoCache).

pdo_mapping(MType,_IX,SI,Sn,Ts,Is,_ResTable,_Dict,_TpdoCache) when SI > Sn ->
    {MType, {reverse(Ts),reverse(Is)}};
pdo_mapping(MType,IX,SI,Sn,Ts,Is,ResTable,Dict,TpdoCache) ->
    case co_dict:value(Dict, IX, SI) of
	{ok,Map} ->
	    ?dbg(node, "pdo_mapping: index = ~7.16.0#:~w, map = ~11.16.0#", 
		 [IX,SI,Map]),
	    Index = {_I,_S} = {?PDO_MAP_INDEX(Map),?PDO_MAP_SUBIND(Map)},
	    ?dbg(node, "pdo_mapping: entry[~w] = {~7.16.0#:~w}", 
		 [SI,_I,_S]),
	    case entry(MType, Index, ResTable, Dict, TpdoCache) of
		{ok, E} when is_record(E,dict_entry) ->
		    pdo_mapping(MType,IX,SI+1,Sn,
				[{E#dict_entry.type,?PDO_MAP_BITS(Map)}|Ts],
				[Index|Is], ResTable, Dict, TpdoCache);
		{ok, Type} ->
		    pdo_mapping(MType,IX,SI+1,Sn,
				[{Type,?PDO_MAP_BITS(Map)}|Ts],
				[Index|Is], ResTable, Dict, TpdoCache);
		    
		Error ->
		    Error
	    end;
	Error ->
	    ?dbg(node, "pdo_mapping: ~7.16.0#:~w = Error ~w", 
		 [IX,SI,Error]),
	    Error
    end.

entry(MType, {Ix, Si}, ResTable, Dict, TpdoCache) ->
    case co_node:reserver_with_module(ResTable, Ix) of
	[] ->
	    ?dbg(node, "entry: No reserver for index ~7.16.0#", [Ix]),
	    co_dict:lookup_entry(Dict, Ix);
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg(node, "entry: Process ~p has reserved index ~7.16.0#", 
		 [Pid, Ix]),

	    %% Handle differently when TPDO and RPDO
	    case MType of
		tpdo ->
		    %% Store default value in cache ??
		    ets:insert(TpdoCache, {{Ix, Si}, [0]}),
		    try Mod:tpdo_callback(Pid, {Ix, Si}, {co_node, tpdo_set}) of
			Res -> Res %% Handle error??
		    catch error:Reason ->
			    io:format("WARNING!" 
				      "~p: ~p: entry: tpdo_callback call failed " 
				      "for process ~p module ~p, index ~7.16.0#"
				      ":~w, reason ~p\n", 
				      [self(), ?MODULE, Pid, Mod, Ix, Si, Reason]),
			    {error,  ?abort_internal_error}
		    end;
		rpdo ->
		    try Mod:index_specification(Pid, {Ix, Si}) of
			{spec, Spec} ->
			    {ok, Spec#index_spec.type}
		    catch error:Reason -> 
			    io:format("WARNING!" 
				      "~p: ~p: entry: index_specification call "
				      "failed for process ~p module ~p, index "
				      "~7.16.0#:~w, reason ~p\n", 
				      [self(), ?MODULE, Pid, Mod, Ix, Si, Reason]),
			    {error,  ?abort_internal_error}
			    
		    end
	    end;
	{dead, _Mod} ->
	    ?dbg(node, "entry: Reserver process for index ~7.16.0# dead.", [Ix]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg(node, "entry: Other case = ~p", [_Other]),
	    {error, ?abort_internal_error}
    end.

tpdo_value({Ix, Si}, #tpdo_ctx {res_table = ResTable, dict = Dict, 
				   tpdo_cache = TpdoCache}) ->
	     tpdo_value({Ix, Si}, ResTable, Dict, TpdoCache).
tpdo_value({Ix, Si} = I, ResTable, Dict, TpdoCache) ->
    case co_node:reserver_with_module(ResTable, Ix) of
	[] ->
	    ?dbg(node, "tpdo_value: No reserver for index ~7.16.0#", [Ix]),
	    co_dict:value(Dict, Ix, Si);
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg(node, "tpdo_value: Process ~p has reserved index ~7.16.0#", 
		 [Pid, Ix]),
	    %% Value cached ??
	    cache_value(TpdoCache, I);
	{dead, _Mod} ->
	    ?dbg(node, "tpdo_value: Reserver process for index ~7.16.0# dead.", 
		 [Ix]),
	    %% Value cached??
	    cache_value(TpdoCache, I);
	_Other ->
	    ?dbg(node, "tpdo_value: Other case = ~p", [_Other]),
	    {error, ?abort_internal_error}
    end.

cache_value(Cache, I) ->
    case ets:lookup(Cache, I) of
	[] ->
	    io:format("WARNING!" 
		      "~p: tpdo_value: unknown tpdo element\n", [self()]),
	    {error,?abort_internal_error};
	[{I,[LastValue | []]}]  ->
	    %% Leave last value in cache
	    ?dbg(node, "cache_value: Last value = ~p.", [LastValue]),
	    {ok, LastValue};
	[{I, [FirstValue | Rest]}] ->
	    %% Remove first value from list
	    ?dbg(node, "cache_value: First value = ~p, rest = ~p.", 
		 [FirstValue, Rest]),
	    ets:insert(Cache, {I, Rest}),
	    {ok, FirstValue}
    end.
	    
    
rpdo_value({Ix,Si},Value,Type,Ctx) ->
    case co_node:reserver_with_module(Ctx#co_ctx.res_table, Ix) of
	[] ->
	    ?dbg(node, "rpdo_value: No reserver for index ~7.16.0#", [Ix]),
	    try co_dict:set(Ctx#co_ctx.dict, Ix, Si, Value) of
		ok -> {ok, handle_notify(Ix, Ctx)};
		Error -> {Error, Ctx}
	    catch
		error:Reason -> {{error,Reason}, Ctx}
	    end;
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg(node, "rpdo_value: Process ~p has reserved index ~7.16.0#", 
		 [Pid, Ix]),
	    Bin = 
		try co_codec:encode(Value, Type) of
		    B -> B
		catch error: _Reason1 ->
			?dbg(node, "rpdo_value: Encode failed for ~p of type ~w "
			     "reason ~p",[Value, Type, _Reason1]),
			Value %% ??
		end,
	    case co_set_fsm:start({Pid, Mod}, {Ix, Si}, Bin) of
		{ok, _FsmPid} -> 
		    ?dbg(node,"Started set session ~p", [_FsmPid]),
		    {ok, handle_notify(Ix, Ctx)};
		ignore ->
		    ?dbg(node,"Complete set session executed", []),
		    {ok, handle_notify(Ix, Ctx)};
		{error, _Reason} = E-> 	
		    %% io:format ??
		    ?dbg(node,"Failed starting set session ~p", [_Reason]),
		    {E, Ctx}
	    end;
	{dead, _Mod} ->
	    ?dbg(node, "rpdo_value: Reserver process for index ~7.16.0# dead.", 
		 [Ix]),
	    {error, ?abort_internal_error}; %% ???
	_Other ->
	    ?dbg(node, "rpdo_value: Other case = ~p", [_Other]),
	    {error, ?abort_internal_error}
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
    ?dbg(node, "set_time_of_day: ~p", [Time]),
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
