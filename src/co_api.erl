%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%%   CANopen node interface.
%%%
%%% File    : co_api.erl <br/>
%%% Created: 10 Jan 2008 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_api).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/co_app.hrl").

-define(DICT_T(), term()). %% dict:dict()

%% API
-export([start_link/2, stop/1]).
-export([attach/1, detach/1]).

%% Admin interface
-export([load_dict/1, load_dict/2]).
-export([save_dict/1, save_dict/2]).
-export([get_option/2, set_option/3]).
-export([alive/1]).

%% Application interface
-export([subscribe/2, unsubscribe/2]).
-export([reserve/3, unreserve/2]).
-export([extended_notify_subscribe/2, extended_notify_unsubscribe/2]).
-export([inactive_event_subscribe/1, inactive_event_unsubscribe/1]).
-export([my_subscriptions/1, my_subscriptions/2]).
-export([my_reservations/1, my_reservations/2]).
-export([all_subscribers/1, all_subscribers/2]).
-export([all_reservers/1, reserver/2]).
-export([object_event/2, session_over/2]). %% Sdo session signals
-export([pdo_event/2, dam_mpdo_event/3]).
-export([notify/3, notify/4, notify/5]). %% To send MPOs
-export([notify_from/5]). %% To send MPOs
-export([add_object/4, add_entry/3]).
-export([delete_object/3, delete_entry/3]).
-export([set_data/4, set_value/4]).
-export([data/3, value/3]).
-export([set_error/3]).

%% CANopen application internal
-export([add_entry/2, get_entry/2]).
-export([add_object/3, get_object/2]).
%%-export([delete_object/2, delete_entry/2]).
-export([set_data/3, set_value/3]).
-export([data/2, value/2]).
-export([store/7, fetch/7]).
-export([subscribers/2]).
-export([reserver_with_module/2]).
-export([tpdo_mapping/2, rpdo_mapping/2, tpdo_set/4, tpdo_data/2]).

%% Test interface
-export([dump/1, dump/2, loop_data/1]).
-export([state/1, state/2]).
-export([dict/1]).

-define(CO_NODE, co_node).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Description: Starts the CANOpen node.
%%
%% Options (default values given if applicale): 
%%          {use_serial_as_xnodeid, boolean()} - create extended node id from
%%                                      serial number.<br/>
%%          {nodeid, integer()}       - node id, range: 1 - 16#7e.<br/>
%%          {xnodeid, integer()}      - extended node id, range: 1 - 16#ffffff.<br/>
%%          {time_stamp,  timeout()}  - ( 60000 ) in msec. <br/>
%%          {nmt_role, nmt_role()}    - ( autonomous ) slave/master/autonomous
%%          {nmt_conf, nmt_conf()}    - ( default ) default/undefined/string()
%%          {supervision, node_guard | heartbeat | none}   - ( none )
%%          {inact_timeout, timeout()} - (infinity) in sec. <br/>
%%                                      timeout for sending inactive event 
%%                                      when can bus has been inactive. <br/>
%%
%%            Dictionary option
%%          {dict, none | default | saved | string()} - ( saved )
%%                                      Controls wich dict that will be loaded
%%                                      at start. 
%%                                      default means the dictionary included 
%%                                      in the delivery.
%%                                      saved means the dictonary last saved by the
%%                                      save/0 function. If none exist default will
%%                                      be used.
%%
%%            SDO transfer options
%%          {sdo_timeout, timeout()}  - ( 1000 ) in msec. <br/>
%%          {blk_timeout, timeout()}  - ( 500 ) in msec. <br/>
%%          {pst, integer()}          - ( 16 ) protocol switch limit.<br/>
%%          {max_blksize, integer()}  - ( 74 = 518 bytes) <br/>
%%          {use_crc, boolean()}      - (true) use crc for block. <br/>
%%          {readbufsize, integer()}  - (1024) size of buf when reading from app. <br/>
%%          {load_ratio, float()}     - (0.5) ratio when time to fill read_buf. <br/> 
%%          {atomic_limit, integer()} - (1024) limit to size of atomic variable. <br/>
%%
%%            TPDO options
%%          {tpdo_cache_limit, integer()} - (512) limits number of cached tpdo values
%%                                      for an index.<br/>
%%          {tpdo_restart_limit, integer()} - (10) limits number of restart  
%%                                      attempts for tpdo processes.<br/>
%%
%%            Testing
%%          {debug, boolean()}        - Enable/Disable trace output.<br/>
%%          {linked, boolean()}       - Start process linked (default) or not. <br/>
%%         
%% @end
%%--------------------------------------------------------------------
-type supervision():: node_guard | heartbeat | none.
-type obj_dict():: none | default | saved | string().
-type option()::
	{use_serial_as_xnodeid, boolean()} |
	{nodeid, integer()} | 
	{xnodeid, integer()} | 
	{vendor, integer()} | 
	{product, integer()} | 
	{revision, integer()} | 
	{nmt_role, nmt_role()} | 
	{nmt_conf, nmt_conf()} | 
	{supervision, supervision()} | 
	{inact_timeout, timeout() } |
	{dict, obj_dict()} | 
	{time_stamp,  timeout()} | 
	{sdo_timeout, timeout()} | 
	{blk_timeout, timeout()} |
	{pst, integer()} | 
	{max_blksize, integer()} | 
	{use_crc, boolean()} | 
	{readbufsize, integer()} | 
	{load_ratio, float()} | 
	{atomic_limit, integer()} | 
	{tpdo_cache_limit, integer()} |
	{os_commands_enabled, boolean()} |
	{debug, boolean()} | 
	{linked, boolean()}.
	
-spec start_link(Serial::integer(), Opts::list(option())) ->
			{ok, Pid::pid()} |
			{error, Reason::term()}.
start_link(S, Opts) when is_integer(S) ->
    %% Trace output enable/disable
    co_lib:debug(proplists:get_value(debug,Opts,false)), 
    lager:debug("start_link: Serial = ~.16#, Opts = ~p", [S, Opts]),

    F =	case proplists:get_value(linked,Opts,true) of
	    true -> start_link;
	    false -> start
	end,

    Serial = serial(S),
    case verify_options(Opts) of
	ok ->
	    Name = name(Opts, Serial),
	    lager:debug("start_link: Starting co_node with function ~p, "
		 "Name = ~p, Serial = ~.16#", [F, Name, Serial]),
	    gen_server:F({local, Name}, ?CO_NODE, {Serial,Name,Opts}, []);
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

verify_option(name, NewValue) 
  when is_list(NewValue) orelse is_atom(NewValue) ->
    ok;
verify_option(name, _NewValue) ->
    {error, "Option name can only be set to a string or an atom."};
verify_option(nodeid, NewValue) 
  when is_integer(NewValue) andalso NewValue >= 0 andalso NewValue < 127 ->
    ok;
verify_option(nodeid, NewValue) 
  when NewValue == undefined ->
    ok;
verify_option(nodeid, _NewValue) ->
    {error, "Option nodeid can only be set to an integer between 0 and "
     "126 (0 - 16#7e) or undefined."};
verify_option(xnodeid, NewValue) 
  when is_integer(NewValue) andalso NewValue > 0
       andalso NewValue < 2#1000000000000000000000000 -> %% Max 24 bits
    ok;
verify_option(xnodeid, NewValue) 
  when NewValue =:= undefined ->
    ok;
verify_option(xnodeid, _NewValue) ->
    {error, "Option xnodeid can only be set to an integer value between "
     "0 and 16777215 (0 - 16#ffffff) or undefined."};
verify_option(dict, NewValue) 
  when NewValue == none orelse
       NewValue == saved orelse
       NewValue == default ->
    ok;
verify_option(dict, NewValue) 
  when is_list(NewValue) ->
    ok;
verify_option(dict, _NewValue) ->
    {error, "Option dict can only be set to a string or an atom."};
verify_option(nmt_role, NewValue) 
  when NewValue == slave;
       NewValue == master;
       NewValue == autonomous ->
    ok;
verify_option(nmt_role, _NewValue) ->
    {error, "Option nmt_role can only be set to slave/master/autonomous."};
verify_option(nmt_conf, NewValue) 
  when NewValue =:= default;
       NewValue =:= undefined;
       NewValue =:= "";
       is_list(NewValue) ->
    ok;
verify_option(nmt_conf, _NewValue) ->
    {error, "Option nmt_conf can only be set to default/file-name."};

verify_option(supervision, NewValue) 
  when NewValue == node_guard;
       NewValue == heartbeat;
       NewValue == none ->
    ok;
verify_option(supervision, _NewValue) ->
    {error, "Option supervision can only be set to "
     "node_guard/heartbeat/none."};
verify_option(pst, NewValue) 
  when is_integer(NewValue) andalso NewValue >= 0 ->
    ok;
verify_option(pst, _NewValue) ->
    {error, "Option pst can only be set to a positive integer value or zero."};
verify_option(inact_timeout, NewValue) 
  when is_integer(NewValue) andalso NewValue > 0 ->
    ok;
verify_option(inact_timeout, infinity) ->
    ok;
verify_option(inact_timeout, _NewValue) ->
    {error, "Option inact_timeout can only be set to a positive "
     "integer value or infinity."};
verify_option(Option, NewValue) 
  when Option == vendor;
       Option == product;
       Option == revision;
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
  when Option == use_serial_as_xnodeid;
       Option == use_crc;
       Option == load_last_saved;
       Option == os_commands_enabled;
       Option == debug;
       Option == linked ->
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
verify_option(Option, _NewValue) ->
    {error, "Option " ++ atom_to_list(Option) ++ " unknown."}.

%%--------------------------------------------------------------------
%% @doc
%% Stops the CANOpen node.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(Identity::node_identity()) -> ok | {error, Reason::atom()}.
				  
stop(Identity) ->
    gen_server:call(identity_to_pid(Identity), stop).

%%--------------------------------------------------------------------
%% @doc
%% Checks if the co_node is alive.
%%
%% @end
%%--------------------------------------------------------------------
-spec alive(Identity::node_identity()) -> Reply::boolean().
				  
alive(Identity) ->
    is_process_alive(identity_to_pid(Identity)).

%%--------------------------------------------------------------------
%% @doc
%% Gets value of option variable. (For testing)
%%
%% @end
%%--------------------------------------------------------------------
-spec get_option(Identity::node_identity(), Option::atom()) -> 
			{Option::atom(), Value::term()} | 
			{error, Reason::string()}.

get_option(Identity, Option) ->
    gen_server:call(identity_to_pid(Identity), {option, Option}).

%%--------------------------------------------------------------------
%% @doc
%% Sets value of option variable. (For testing)
%%
%% @end
%%--------------------------------------------------------------------
-spec set_option(Identity::node_identity(), Option::atom(), NewValue::term()) -> 
			ok | {error, Reason::string()}.

set_option(Identity, Option, NewValue) ->
    lager:debug("set_option: Option = ~p, NewValue = ~p",[Option, NewValue]),
    case verify_option(Option, NewValue) of
	ok ->
	    gen_server:call(identity_to_pid(Identity), {option, Option, NewValue});	    
	{error, _Reason} = Error ->
	    lager:debug("set_option: option rejected, reason = ~p",[_Reason]),
	    Error
    end.


%%--------------------------------------------------------------------
%% @doc
%% Loads the last saved dict.
%%
%% @end
%%-------------------------------------------------------------------
-spec load_dict(Identity::node_identity()) -> 
		       ok | {error, Error::atom()}.

load_dict(Identity) ->
    gen_server:call(identity_to_pid(Identity), load_dict, 10000).
    

%%--------------------------------------------------------------------
%% @doc
%% Loads a new Object Dictionary from File.
%%
%% @end
%%-------------------------------------------------------------------
-spec load_dict(Identity::node_identity(), File::string()) -> 
		       ok | {error, Error::atom()}.

load_dict(Identity, File) ->
    gen_server:call(identity_to_pid(Identity), {load_dict, File}, 10000).
    

%%--------------------------------------------------------------------
%% @doc
%% Saves the Object Dictionary to a default file.
%%
%% @end
%%-------------------------------------------------------------------
-spec save_dict(Identity::node_identity()) -> 
		       ok | {error, Error::atom()}.

save_dict(Identity) ->
    gen_server:call(identity_to_pid(Identity), save_dict, 10000).
    

%%--------------------------------------------------------------------
%% @doc
%% Saves the Object Dictionary to a file.
%%
%% @end
%%-------------------------------------------------------------------
-spec save_dict(Identity::node_identity(), File::string()) -> 
		       ok | {error, Error::atom()}.

save_dict(Identity, File) ->
    gen_server:call(identity_to_pid(Identity), {save_dict, File}, 10000).
    

%%--------------------------------------------------------------------
%% @doc
%% Attches the calling process to the CANnode idenified by Identity.
%% In return a dictionary reference is given so that the application
%% can store its object in it if it wants, using the co_dict API.
%% @end
%%--------------------------------------------------------------------
-spec attach(Identity::node_identity()) -> 
		    {ok, DictRef::term()} | 
		    {error, Error::atom()}.

attach(Identity) ->
    gen_server:call(identity_to_pid(Identity), {attach, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Detaches the calling process from the CANnode idenified by Identity.
%%
%% @end
%%--------------------------------------------------------------------
-spec detach(Identity::node_identity()) -> ok | {error, Error::atom()}.

detach(Identity) ->
    gen_server:call(identity_to_pid(Identity), {detach, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Adds a subscription to changes of the Dictionary Object in position Index.<br/>
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribe(Identity::node_identity(), 
		Index::integer() |  list(Index::integer())) -> 
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
-spec unsubscribe(Identity::node_identity(), 
		  Index::integer() | list(Index::integer())) -> 
		       ok | {error, Error::atom()}.
unsubscribe(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {unsubscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Adds a subscription to changes of the Dictionary Object in position Index.<br/>
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
-spec extended_notify_subscribe(Identity::node_identity(), 
				Index::integer() | 
				       list(Index::integer())) -> 
		       ok | {error, Error::atom()}.

extended_notify_subscribe(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {xnot_subscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Removes a subscription to changes of the Dictionary Object in position Index.<br/>
%% Index can also be a range [Index1 - Index2].
%%
%% @end
%%--------------------------------------------------------------------
-spec extended_notify_unsubscribe(Identity::node_identity(), 
				  Index::integer() | list(Index::integer())) -> 
		       ok | {error, Error::atom()}.
extended_notify_unsubscribe(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {xnot_unsubscribe, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Adds a subscription to event when can bus has been inactive.
%% @end
%%--------------------------------------------------------------------
-spec inactive_event_subscribe(Identity::node_identity()) -> 
		       ok | {error, Error::atom()}.

inactive_event_subscribe(Identity) ->
    gen_server:call(identity_to_pid(Identity), 
		    {inactive_subscribe, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Removes a subscription to event when can bus has been inactive.
%%
%% @end
%%--------------------------------------------------------------------
-spec inactive_event_unsubscribe(Identity::node_identity()) -> 
		       ok | {error, Error::atom()}.
inactive_event_unsubscribe(Identity) ->
    gen_server:call(identity_to_pid(Identity), 
		    {inactive_unsubscribe, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Indexes for which the application idenified by Pid 
%% has subscriptions.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_subscriptions(Identity::node_identity(), Pid::pid()) -> 
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
-spec my_subscriptions(Identity::node_identity()) -> 
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
-spec all_subscribers(Identity::node_identity()) -> 
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
-spec all_subscribers(Identity::node_identity(), Ix::integer()) ->
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
-spec reserve(Identity::node_identity(), Index::integer(), Module::atom()) -> 
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
-spec unreserve(Identity::node_identity(), Index::integer()) -> 
		       ok | {error, Error::atom()}.
unreserve(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {unreserve, Ix, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Indexes for which Pid has reservations.
%%
%% @end
%%--------------------------------------------------------------------
-spec my_reservations(Identity::node_identity(), Pid::pid()) -> 
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
-spec my_reservations(Identity::node_identity()) ->
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
-spec all_reservers(Identity::node_identity()) ->
			   list(Pid::pid()) | {error, Error::atom()}.

all_reservers(Identity) ->
    gen_server:call(identity_to_pid(Identity), {reservers}).

%%--------------------------------------------------------------------
%% @doc
%% Returns the Pid that has reserved index if any.
%%
%% @end
%%--------------------------------------------------------------------
-spec reserver(Identity::node_identity(), Ix::integer()) ->
		      list(Pid::pid()) | {error, Error::atom()}.

reserver(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {reserver, Ix}).

%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that an object has been updated so that any
%% subscribers can be informed. Called by co_sdo_srv_fsm.erl and
%% co_sdo_cli_fsm.erl.
%% @end
%%--------------------------------------------------------------------
-spec object_event(Identity::node_identity(), Index::{Ix::integer(), Si::integer()}) ->
			  ok | {error, Error::atom()}.

object_event(CoNodePid, Index) 
  when is_pid(CoNodePid) ->
    gen_server:cast(CoNodePid, {object_event, Index});
object_event(Identity, Index) ->
    gen_server:cast(identity_to_pid(Identity), {object_event, Index}).

%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that a session has finished and should be removed
%% from the sdo_list. Called by co_sdo_srv_fsm.erl and
%% co_sdo_cli_fsm.erl.
%% @end
%%--------------------------------------------------------------------
-spec session_over(Identity::node_identity(), Reason::normal | atom()) ->
			  ok | {error, Error::atom()}.

session_over(CoNodePid, Reason) 
  when is_pid(CoNodePid) ->
    gen_server:cast(CoNodePid, {session_over, self(), Reason});
session_over(Identity, Reason) ->
    gen_server:cast(identity_to_pid(Identity), {session_over, self(), Reason}).

%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that a PDO should be transmitted.
%% @end
%%--------------------------------------------------------------------
-spec pdo_event(CoNode::pid() | integer(), CobId::integer()) ->
		       ok | {error, Error::atom()}.

pdo_event(Identity, CobId) ->
    gen_server:cast(identity_to_pid(Identity), {pdo_event, CobId}).


%%--------------------------------------------------------------------
%% @doc
%% Tells the co_node that an DAM-MPDO should be transmitted.
%% @end
%%--------------------------------------------------------------------
-spec dam_mpdo_event(CoNode::pid() | integer(), CobId::integer(), 
		    DestinationNode::integer() | broadcast) ->
		       ok | {error, Error::atom()}.

dam_mpdo_event(Identity, CobId, DestinationNode) 
  when DestinationNode == broadcast orelse
       (is_integer(DestinationNode) andalso DestinationNode) =< 127 ->
    gen_server:cast(identity_to_pid(Identity), {dam_mpdo_event, CobId, DestinationNode});
dam_mpdo_event(_Identity, _CobId, _DestinationNode) ->
    lager:debug("dam_mpdo_event: Invalid destination = ~p", [_DestinationNode]),
    {error, invalid_destination}.



%%--------------------------------------------------------------------
%%
%% Functions accessing the dictionary in calling party context
%%
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Add a new object to a dictionary. 
%% Addition is done in calling partys context but an object_event is also sent
%% to the node.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_object(Identity::node_identity(), 
		 Dict::term(), 
		 Object::#dict_object{}, 
		 list(Entry::#dict_entry{})) ->
			ok | {error, badarg}.

add_object(Identity, Dict, Object, Es) when is_record(Object, dict_object) ->
     update_dict(Identity, Object#dict_object.index, add_object, [Dict, Object, Es]).

%%--------------------------------------------------------------------
%% @doc
%% Add a new entry to a dictionary. 
%% Addition is done in calling partys context but an object_event is also sent
%% to the node.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_entry(Identity::node_identity(), 
		Dict::term(), 
		Entry::#dict_entry{}) ->
		       ok | {error, badarg}.

add_entry(Identity, Dict, Entry) when is_record(Entry, dict_entry) ->
    update_dict(Identity, Entry#dict_entry.index, add_entry, [Dict, Entry]).

%%--------------------------------------------------------------------
%% @doc
%% Delete existing object in dictionary.
%% Deletion is done in calling partys context but an object_event is also sent
%% to the node.
%%
%% @end
%%--------------------------------------------------------------------
-spec delete_object(Identity::node_identity(), Dict::term(), Ix::integer()) ->
			ok | {error, badarg}.

delete_object(Identity, Dict, Ix) when ?is_index(Ix) ->
    update_dict(Identity, Ix, delete_object, [Dict, Ix]).
    
%%--------------------------------------------------------------------
%% @doc
%% Delete existing entry in dictionary.
%% Deletion is done in calling partys context but an object_event is also sent
%% to the node.
%%
%% @end
%%--------------------------------------------------------------------
-spec delete_entry(Identity::node_identity(), Dict::term(), 
		   Index::integer() | {integer(), integer()}) ->
		       ok | {error, badarg}.

delete_entry(Identity, Dict, Index={Ix,Sx}) when ?is_index(Ix), ?is_subind(Sx) ->
    update_dict(Identity, Ix, delete_entry, [Dict, Index]);
delete_entry(Identity, Dict, Ix) when ?is_index(Ix) ->
    delete_entry(Identity, Dict, {Ix,0}).

%%--------------------------------------------------------------------
%% @doc
%% Sets {Ix, Si} to Value.
%% @end
%%--------------------------------------------------------------------
-spec set_value(Identity::node_identity(), Dict::term(), 
		Index::{Ix::integer(), Si::integer()} |integer(), 
		Value::term()) -> 
		       ok | {error, Error::atom()}.

set_value(Identity, Dict, {Ix, Si} = I, Value) when ?is_index(Ix), ?is_subind(Si) ->
    update_dict(Identity, Ix, set_value, [Dict, I, Value]);
set_value(Identity, Dict, Ix, Value) when is_integer(Ix) ->
    set_value(Identity, Dict, {Ix, 0}, Value).



%%--------------------------------------------------------------------
%% @doc
%% Sets {Ix, Si} to Data.
%% @end
%%--------------------------------------------------------------------
-spec set_data(Identity::node_identity(), Dict::term(), 
	       Index::{Ix::integer(), Si::integer()} |integer(), 
	       Data::binary()) -> 
		      ok | {error, Error::atom()}.

set_data(Identity, Dict, {Ix, Si} = I, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    update_dict(Identity, Ix, set_data, [Dict, I, Data]);
set_data(Identity, Dict, Ix, Data) when is_integer(Ix), is_binary(Data) ->
    set_data(Identity, Dict, {Ix, 0}, Data).


%%--------------------------------------------------------------------
%% @doc
%% Gets Value for Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec value(Identity::node_identity(), Dict::term(), 
	    Index::{Ix::integer(), Si::integer()} | integer()) -> 
		   {ok, Value::term()} | {error, Error::atom()}.

value(_Identity, Dict, {Ix, Si} = I) when ?is_index(Ix), ?is_subind(Si)  ->
    co_dict:value(Dict, I);
value(Identity, Dict, Ix) when is_integer(Ix) ->
    value(Identity, Dict, {Ix, 0}).


%%--------------------------------------------------------------------
%% @doc
%% Gets Data for Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec data(Identity::node_identity(), Dict::term(), 
	    Index::{Ix::integer(), Si::integer()} | integer()) -> 
		   {ok, Data::term()} | {error, Error::atom()}.

data(_Identity, Dict, {Ix, Si} = I) when ?is_index(Ix), ?is_subind(Si)  ->
    co_dict:data(Dict, I);
data(Identity, Dict, Ix) when is_integer(Ix) ->
    data(Identity, Dict, {Ix, 0}).

%%--------------------------------------------------------------------
%% @doc
%% Set error condition and send emergency frame.
%% @end
%%--------------------------------------------------------------------
-spec set_error(Identity::node_identity(),
		Error::integer(),
		Code::integer()) -> ok | {error, term()}.

set_error(Identity, Error, Code) ->
    gen_server:call(identity_to_pid(Identity), {set_error,Error,Code}).

%%--------------------------------------------------------------------
%%
%% Functions accessing the dictionary in co_node process context
%%
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Adds Object to the CoNode internal Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_object(Identity::node_identity(), 
		 Object::#dict_object{}, 
		 list(Entry::#dict_entry{})) -> 
		       ok | {error, Error::atom()}.

add_object(Identity, Object, Es) when is_record(Object, dict_object) ->
     gen_server:call(identity_to_pid(Identity), {add_object, Object, Es}).

%%--------------------------------------------------------------------
%% @doc
%% Adds Entry to the CoNode internal Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_entry(Identity::node_identity(), Entry::#dict_entry{}) -> 
		       ok | {error, Error::atom()}.

add_entry(Identity, Ent) ->
    gen_server:call(identity_to_pid(Identity), {add_entry, Ent}).

%%--------------------------------------------------------------------
%% @doc
%% Gets the Entry at Index in Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec get_entry(Identity::node_identity(), 
		{Ix::integer(), Si::integer()}) -> 
		       ok | {error, Error::atom()}.

get_entry(Identity, Index) ->
    gen_server:call(identity_to_pid(Identity), {get_entry,Index}).

%%--------------------------------------------------------------------
%% @doc
%% Gets the Object at Index in Object dictionary.
%%
%% @end
%%--------------------------------------------------------------------
-spec get_object(Identity::node_identity(), Ix::integer()) -> 
		       ok | {error, Error::atom()}.

get_object(Identity, Ix) ->
    gen_server:call(identity_to_pid(Identity), {get_object,Ix}).

%%--------------------------------------------------------------------
%% @doc
%% Sets {Ix, Si} to Value.
%% @end
%%--------------------------------------------------------------------
-spec set_value(Identity::node_identity(), 
		Index::{Ix::integer(), Si::integer()} |integer(), 
		Value::term()) -> 
		       ok | {error, Error::atom()}.

set_value(Identity, {Ix, Si} = I, Value) when ?is_index(Ix), ?is_subind(Si) ->
    gen_server:call(identity_to_pid(Identity), {set_value,I,Value});   
set_value(Identity, Ix, Value) when is_integer(Ix) ->
    set_value(Identity, {Ix, 0}, Value).



%%--------------------------------------------------------------------
%% @doc
%% Sets {Ix, Si} to Data.
%% @end
%%--------------------------------------------------------------------
-spec set_data(Identity::node_identity(), 
	       Index::{Ix::integer(), Si::integer()} | integer(), 
	       Data::binary()) -> 
		      ok | {error, Error::atom()}.

set_data(Identity, {Ix, Si} = I, Data) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) ->
    gen_server:call(identity_to_pid(Identity), {set_data,I,Data});   
set_data(Identity, Ix, Data) when is_integer(Ix), is_binary(Data) ->
    set_data(Identity, {Ix, 0}, Data).



%%--------------------------------------------------------------------
%% @doc
%% Gets Value for Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec value(Identity::node_identity(), 
	    Index::{Ix::integer(), Si::integer()} | integer()) -> 
		   Value::term() | {error, Error::atom()}.

value(Identity, {Ix, Si} = I) when ?is_index(Ix), ?is_subind(Si)  ->
    gen_server:call(identity_to_pid(Identity), {value,I});
value(Identity, Ix) when is_integer(Ix) ->
    value(Identity, {Ix, 0}).


%%--------------------------------------------------------------------
%% @doc
%% Gets Data for Index.
%%
%% @end
%%--------------------------------------------------------------------
-spec data(Identity::node_identity(), 
	    Index::{Ix::integer(), Si::integer()} | integer()) -> 
		   Data::term() | {error, Error::atom()}.

data(Identity, {Ix, Si} = I) when ?is_index(Ix), ?is_subind(Si)  ->
    gen_server:call(identity_to_pid(Identity), {data,I});
data(Identity, Ix) when is_integer(Ix) ->
    data(Identity, {Ix, 0}).

%%--------------------------------------------------------------------
%% @doc
%% Starts a store session to store Value at Index:Si on remote node.
%%
%% @end
%%--------------------------------------------------------------------
-spec store(Identity::node_identity(),
	    {TypeOfNid::nodeid | xnodeid, Nid::integer()},
	    Ix::integer(), Si::integer(), 
	    TransferMode:: block | segment,
	    Term::{data, binary()} | 
		  {value, Value::term(), Type::integer() | atom()} |
		  {app, Pid::pid(), Module::atom()},
	    TimeOut::timeout() | default) ->
		   ok | {error, Error::term()}.

store(Identity, NodeId = {_TypeOfNid, _Nid}, Ix, Si, 
      TransferMode, Term, default) 
  when ?is_index(Ix), ?is_subind(Si) ->
    lager:debug([{index, {Ix, Si}}],
	 "store: Identity = ~p, NodeId = {~p, ~.16#}, "
	 "Ix = ~4.16.0B, Si = ~p, Mode = ~p, Term = ~p", 
	 [Identity, _TypeOfNid, _Nid, Ix, Si, TransferMode, Term]),
    gen_server:call(identity_to_pid(Identity), 
		    {store,TransferMode,NodeId,Ix,Si,Term});
store(Identity, NodeId = {_TypeOfNid, _Nid}, Ix, Si, 
      TransferMode, Term, TimeOut) 
  when ?is_index(Ix), ?is_subind(Si),
       (is_integer(TimeOut) andalso TimeOut > 0) ->
    lager:debug([{index, {Ix, Si}}],
	 "store: Identity = ~p, NodeId = {~p, ~.16#}, "
	 "Ix = ~4.16.0B, Si = ~p, Mode = ~p, Term = ~p, TimeOut = ~p", 
	 [Identity, _TypeOfNid, _Nid, Ix, Si, TransferMode, Term, TimeOut]),
    gen_server:call(identity_to_pid(Identity), 
		    {store,TransferMode,NodeId,Ix,Si,Term,TimeOut},
		    TimeOut + 1000).


    
%%--------------------------------------------------------------------
%% @doc
%% Starts a fetch session to fetch Value at Ix:Si on remote node.
%%
%% @end
%%--------------------------------------------------------------------
-spec fetch(Identity::node_identity(), 
	    {TypeOfNid::nodeid | xnodeid, Nid::integer()},
	    Ix::integer(), Si::integer(),
 	    TransferMode:: block | segment,
	    Term::data | 
		  {app, Pid::pid(), Module::atom()} |
		  {value, Type::integer() | atom()},
	    TimeOut::timeout() | default) ->
		   {ok, Data::binary()} | {error, Error::term()}.


fetch(Identity, NodeId = {_TypeOfNid, Nid}, Ix, Si, 
      TransferMode, Term, default)
  when is_integer(Nid), ?is_index(Ix), ?is_subind(Si) ->
    lager:debug([{index, {Ix, Si}}],
	 "fetch: Identity = ~p, NodeId = {~p, ~.16#}, "
	 "Ix = ~4.16.0B, Si = ~p, Mode = ~p, Term = ~p", 
	 [Identity, _TypeOfNid, Nid, Ix, Si, TransferMode, Term]),
    gen_server:call(identity_to_pid(Identity), 
		    {fetch,TransferMode,NodeId,Ix,Si,Term});
fetch(Identity, NodeId = {_TypeOfNid, Nid}, Ix, Si, 
      TransferMode, Term, TimeOut)
  when is_integer(Nid), ?is_index(Ix), ?is_subind(Si),
       (is_integer(TimeOut) andalso TimeOut > 0) ->
    lager:debug([{index, {Ix, Si}}],
	 "fetch: Identity = ~p, NodeId = {~p, ~.16#}, "
	 "Ix = ~4.16.0B, Si = ~p, Mode = ~p, Term = ~p, TimeOut = ~p", 
	 [Identity, _TypeOfNid, Nid, Ix, Si, TransferMode, Term, TimeOut]),
    gen_server:call(identity_to_pid(Identity), 
		    {fetch,TransferMode,NodeId,Ix,Si,Term,TimeOut},
		    TimeOut + 1000).


%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump(Identity::node_identity()) -> ok | {error, Error::atom()}.

dump(Identity) ->
    dump(Identity, all).

%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump(Identity::node_identity(), Qualifier::all | no_dict) -> 
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
-spec loop_data(Identity::node_identity()) -> ok | {error, Error::atom()}.

loop_data(Identity) ->
    gen_server:call(identity_to_pid(Identity), loop_data).

%%--------------------------------------------------------------------
%% @doc
%% Gets the co_nodes state.
%%
%% @end
%%--------------------------------------------------------------------
-spec state(Identity::node_identity()) -> 
		   State::atom() | {error, Error::atom()}.

state(Identity) ->
    gen_server:call(identity_to_pid(Identity), state).

%%--------------------------------------------------------------------
%% @doc
%% Sets the co_node's state.
%%
%% @end
%%--------------------------------------------------------------------
-spec state(Identity::node_identity(), 
	    State::operational | preoperational | stopped) -> 
		   ok | {error, Error::atom()}.

state(Identity, operational) ->
    gen_server:call(identity_to_pid(Identity), {state, ?Operational});
state(Identity, preoperational) ->
    gen_server:call(identity_to_pid(Identity), {state, ?PreOperational});
state(Identity, stopped) ->
    gen_server:call(identity_to_pid(Identity), {state, ?Stopped}).

%%--------------------------------------------------------------------
%% @doc
%% Gets the co_node's dict
%%
%% @end
%%--------------------------------------------------------------------
-spec dict(Identity::node_identity()) -> 
		  Dict::?DICT_T() | {error, Error::atom()}.

dict(Identity) ->
    gen_server:call(identity_to_pid(Identity), dict).

%%--------------------------------------------------------------------
%% @doc
%% Cache {Ix, Si} Data or encoded Value truncated to 64 bits.
%% @end
%%--------------------------------------------------------------------
-spec tpdo_set(Identity::node_identity(), 
	       Index::{Ix::integer(), Si::integer()} | integer(), 
	       Data::binary() | {Value::term(), Type::term()},
	       Mode:: append | overwrite) -> 
		      ok | {error, Error::atom()}.

tpdo_set(Identity, {Ix, Si} = I, Data, Mode) 
  when ?is_index(Ix), ?is_subind(Si), is_binary(Data) andalso
       (Mode == append orelse Mode == overwrite) ->
    lager:debug([{index, {Ix, Si}}],
	 "tpdo_set: Identity = ~.16#,  Ix = ~.16#:~w, Data = ~p, Mode ~p",
	 [Identity, Ix, Si, Data, Mode]), 
    Data64 = co_codec:set_binary_size(Data, 64),
    gen_server:call(identity_to_pid(Identity), {tpdo_set,I,Data64,Mode});   
tpdo_set(Identity, {Ix, Si} = I, {Value, Type}, Mode) 
  when ?is_index(Ix), ?is_subind(Si) ->
    lager:debug([{index, {Ix, Si}}],
	 "tpdo_set: Identity = ~.16#,  Ix = ~.16#:~w, Value = ~p, "
	 "Type = ~p, Mode ~p", [Identity, Ix, Si, Value, Type, Mode]), 
    try co_codec:encode(Value, Type) of
	Data ->
	    tpdo_set(Identity, I, Data, Mode) 
    catch
	error:_Reason ->
	    lager:debug([{index, {Ix, Si}}],
		 "tpdo_set: encode failed, reason = ~p", [_Reason]), 
	    {error, badarg}
    end;
tpdo_set(Identity, Ix, Term, Mode) 
  when is_integer(Ix) ->
    tpdo_set(Identity, {Ix, 0}, Term, Mode).

%%--------------------------------------------------------------------
%% @doc
%% Send notification. <br/>
%% SubIndex is set to 0.<br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify(CobId::integer(), Ix::integer(), Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify(CobId,Ix,Data) ->
    notify(CobId,Ix,0,Data).

%%--------------------------------------------------------------------
%% @doc
%% Send notification. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify(CobId::integer(), Ix::integer(), Si::integer(), Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify(CobId,Ix,Si,Data) 
  when is_integer(CobId), ?is_index(Ix), ?is_subind(Si), is_binary(Data)->
    co_node:notify(CobId,Ix,Si,Data).

%%--------------------------------------------------------------------
%% @doc
%% Send notification. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify({TypeOfNid::nodeid | xnodeid, Nid::integer()}, 
	    Func::atom(), Ix::integer(), Si::integer(), Data::binary()) -> 
		    ok | {error, Error::atom()}.

notify({xnodeid, XNid}, Func, Ix, Si, Data) ->
    try notify(?XCOB_ID(co_lib:encode_func(Func), co_lib:add_xflag(XNid)),
	       Ix,Si,Data) 
    catch _T:E -> 
	    {error, E}
    end;
notify({nodeid, Nid}, Func, Ix, Si, Data) ->
    try notify(?COB_ID(co_lib:encode_func(Func), Nid),Ix,Si,Data)
    catch _T:E -> 
	    {error, E}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Send notification but not to (own) Node. <br/>
%% Note that there are two possible ways of using this function:
%% Either with NodeIdentity and CobId OR with NodeIdentity of a type
%% holding the NodeId (short or extended) and the FunctionCode.<br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec notify_from(NodeIdentity::node_identity(),
		  CobId::integer(),
		  Ix::integer(), Si::integer(), 
		  Data::binary()) -> 
			 ok | {error, Error::atom()};
		 (NodeIdentity::{xnodeid, XNid::integer()} | {nodeid, Nid::integer()},
		  Func::atom(), 
		  Ix::integer(), Si::integer(), 
		  Data::binary()) -> 
			 ok | {error, Error::atom()}.
		  

notify_from(Identity={xnodeid, XNid}, Func, Ix, Si, Data)
  when is_atom(Func) ->
    lager:debug([{index, {Ix, Si}}],
	 "notify_from: NodeId = {xnodeid, ~.16#}, Func = ~p, " ++
	     "Ix = ~4.16.0B, Si = ~p, Data = ~w", 
	 [XNid, Func, Ix, Si, Data]),
    try notify_from(Identity,?XCOB_ID(co_lib:encode_func(Func),
				      co_lib:add_xflag(XNid)),
		    Ix,Si,Data)
    catch _T:E ->
	    {error, E}
    end;
notify_from(Identity={nodeid, Nid}, Func, Ix, Si, Data)
  when is_atom(Func)->
    lager:debug([{index, {Ix, Si}}],
	"notify_from: NodeId = {nodeid, ~.16#}, Func = ~p, "
	 "Ix = ~4.16.0B, Si = ~p, Data = ~p", 
	 [Nid, Func, Ix, Si, Data]),
    try notify_from(Identity,?COB_ID(co_lib:encode_func(Func), Nid),Ix,Si,Data)
    catch _T:E ->
	    {error, E}
    end; 
notify_from(Identity,CobId,Ix,Si,Data)
  when is_integer(CobId), ?is_index(Ix), ?is_subind(Si),  is_binary(Data) ->
    try co_node:notify_from(identity_to_pid(Identity),CobId,Ix,Si,Data)
    catch _T:E ->
	    {error, E}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Get the RPDO mapping. <br/>
%% Executing in calling process context.<br/>
%% @end
%%--------------------------------------------------------------------
-spec rpdo_mapping(Offset::integer(), TpdoCtx::#tpdo_ctx{}) -> 
			  Map::term() | 
			       {error, Error::atom()}.

rpdo_mapping(Offset, TpdoCtx) ->
    co_node:rpdo_mapping(Offset, TpdoCtx).

%%--------------------------------------------------------------------
%% @doc
%% Get the TPDO mapping. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec tpdo_mapping(Offset::integer(), TpdoCtx::#tpdo_ctx{}) -> 
			  Map::term() | {error, Error::atom()}.

tpdo_mapping(Offset, TpdoCtx) ->
    co_node:tpdo_mapping(Offset, TpdoCtx).

%%--------------------------------------------------------------------
%% @doc
%% Get the value for Index from either tpdo_cache, dict or app. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec tpdo_data(Index::{integer(), integer()}, TpdoCtx::#tpdo_ctx{}) ->
			{ok, Data::binary()} |
			{error, Error::atom()}.

tpdo_data(Index = {Ix, Si}, TpdoCtx) 
  when is_integer(Ix) andalso is_integer(Si) ->
    co_node:tpdo_data(Index, TpdoCtx).


%%--------------------------------------------------------------------
%% @doc
%% Get all subscribers in Tab for Index. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribers(Tab::atom() | integer(), Ix::integer()) -> 
			 list(Pid::pid()) | {error, Error::atom()}.

subscribers(Tab, Ix) when ?is_index(Ix) ->
    co_node:subscribers(Tab, Ix).

%%--------------------------------------------------------------------
%% @doc
%% Get the reserver in Tab for Ix if any. <br/>
%% Executing in calling process context.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec reserver_with_module(Tab::atom() | integer(), Ix::integer()) -> 
				  {Pid::pid() | dead, Mod::atom()} | [].

reserver_with_module(Tab, Ix) when ?is_index(Ix) ->
    co_node:reserver_with_module(Tab, Ix).


%%--------------------------------------------------------------------
%%% Support functions
%%--------------------------------------------------------------------
%% @private

%%
%% Convert an identity to a pid
%%
identity_to_pid(Pid) when is_pid(Pid) ->
    Pid;
identity_to_pid(Term) ->
    co_proc:lookup(Term).


update_dict(Identity, Index, Func, Args) ->
    case apply(co_dict,Func,Args) of
	ok ->
	    object_event(identity_to_pid(Identity), Index);
	_Other ->
	    _Other
    end.


