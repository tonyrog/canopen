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
%% @author Malotte W Lonne <malotte@malotte.net>
%% @copyright (C) 2013, Tony Rogvall
%% @doc
%%    System command CANopen application.<br/>
%%    Implements index 16#1010 (save), 16#1011(load).<br/>
%%    save - stores the CANOpen node dictionary.<br/>
%%    load - restores the CANOpen node dictionary.<br/>
%%
%% File: co_os_app.erl<br/>
%% Created: December 2011 by Malotte W Lonne
%% @end
%%===================================================================
-module(co_sys_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_app).

%% API
-export([start_link/1, 
	 stop/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% co_app callbacks
-export([index_specification/2,
	 set/3, 
	 get/2]).

%% Test
-export([loop_data/1,
	 debug/2]).

-define(NAME, co_sys).

-record(loop_data,
	{
	  state           ::atom(),
	  co_node         ::node_identity()     %% Identity of co_node
	}).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link(CoNode::node_identity()) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::atom()}.

start_link(CoNode) ->
    gen_server:start_link({local, name(CoNode)}, ?MODULE, CoNode,[]).
	
%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop(CoNode::node_identity()) -> ok | 
		{error, Error::atom()}.

stop(CoNode) ->
    case whereis(name(CoNode)) of
	undefined -> do_nothing;
	Pid -> gen_server:call(Pid, stop)
    end.

%%--------------------------------------------------------------------
%%% CAllbacks for co_app and co_stream_app behavious
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
-spec index_specification(Pid::pid(), {Ix::integer(), Si::integer()}) -> 
		       {spec, Spec::#index_spec{}} |
		       {error, Reason::atom()}.

index_specification(_Pid, {?IX_STORE_PARAMETERS = _Ix, 255} = I) ->
    ?dbg("index_specification: store type ~.16B ",[_Ix]),
    Value = ((?UNSIGNED32 band 16#ff) bsl 8) bor (?OBJECT_ARRAY band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?IX_STORE_PARAMETERS, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 1});
index_specification(_Pid, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL} = I) ->
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RW, atomic, 9000);
index_specification(Pid, Ix) when is_integer(Ix) ->
    index_specification(Pid, {Ix, 0});
index_specification(_Pid, {?IX_STORE_PARAMETERS, _Si})  ->
    ?dbg("index_specification: store unknown subindex ~.8B ",[_Si]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS = _Ix, 255} = I) ->
    ?dbg("index_specification: restore type ~.16B ",[_Ix]),
    Value = ((?UNSIGNED32 band 16#ff) bsl 8) bor (?OBJECT_ARRAY band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 1});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL} = I) ->
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RW, atomic, 9000);
index_specification(Pid, Ix) when is_integer(Ix) ->
    index_specification(Pid, {Ix, 0});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, _Si})  ->
    ?dbg("index_specification: restore unknown subindex ~.8B ",[_Si]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {_Ix, _Si})  ->
    ?dbg("index_specification: unknown index ~.16B:~.8B ",[_Ix, _Si]),
    {error, ?abort_no_such_object}.

reply_specification({_Ix, _Si} = I, Type, Access, Mode) ->
    reply_specification({_Ix, _Si} = I, Type, Access, Mode, undefined).

reply_specification({_Ix, _Si} = I, Type, Access, Mode, TOut) ->
    ?dbg("reply_specification: ~.16B:~.8B, "
	 "type = ~w, access = ~w, mode = ~w, timeout = ~p",
	 [_Ix, _Si, Type, Access, Mode, TOut]),
    Spec = #index_spec{index = I,
		       type = Type,
		       access = Access,
		       transfer = Mode,
		       timeout = TOut},
    {spec, Spec}.

%%--------------------------------------------------------------------
%% Callback functions for transfer_mode == {atomic, Module}
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Sets {Index, SubInd} to NewValue.<br/>
%% Used for transfer_mode = {atomic, Module}.
%% @end
%%--------------------------------------------------------------------
-spec set(Pid::pid(), {Ix::integer(), Si::integer()}, NewValue::term()) ->
		 ok |
		 {error, Reason::atom()}.

set(Pid, {Ix, Si}, NewValue) ->
    ?dbg("set ~.16B:~.8B to ~p",[Ix, Si, NewValue]),
    gen_server:call(Pid, {set, {Ix, Si}, NewValue}).

%%--------------------------------------------------------------------
%% @doc
%% Gets Value for {Index, SubInd}.<br/>
%% Used for transfer_mode = {atomic, Module}.
%% @end
%%--------------------------------------------------------------------
-spec get(Pid::pid(), {Ix::integer(), Si::integer()}) ->
		 {ok, Value::term()} |
		 {error, Reason::atom()}.

get(Pid, {Ix, Si}) ->
    ?dbg("get ~.16B:~.8B",[Ix, Si]),
    gen_server:call(Pid, {get, {Ix, Si}}).


%% Test functions
%% @private
debug(Pid, TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(Pid, {debug, TrueOrFalse}).

%% @private
loop_data(Pid) ->
    gen_server:call(Pid, loop_data).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(CoNode::node_identity()) -> {ok, LD::#loop_data{}}.

init(CoNode) ->
    CoName = {name, _Name} = co_api:get_option(CoNode, name),
    {ok, _Dict} = co_api:attach(CoNode),
    co_api:reserve(CoNode, ?IX_STORE_PARAMETERS, ?MODULE),
    co_api:reserve(CoNode, ?IX_RESTORE_DEFAULT_PARAMETERS, ?MODULE),
    {ok, #loop_data {state=running, co_node = CoName}}.


%%--------------------------------------------------------------------
%% @doc
%% Handling call messages.
%% Used for transfer mode atomic (set, get) and streamed 
%% (write_begin, write, read_begin, read).
%%
%% Index = Index in Object Dictionary <br/>
%% SubInd =  SubIndex in Object Dictionary  <br/>
%% Value =  Any value the node chooses to send.
%%
%% For description of requests compare with the correspondig functions:
%% @see set/3  
%% @see get/2 
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{get, {Ix::integer(), Si::integer()}} |
	{set, {Ix::integer(), Si::integer()}, Value::term()} |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), term()}, LD::#loop_data{}) ->
			 {reply, Reply::term(), LD::#loop_data{}} |
			 {reply, Reply::term(), LD::#loop_data{}, Timeout::timeout()} |
			 {noreply, LD::#loop_data{}} |
			 {noreply, LD::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), Reply::term(), LD::#loop_data{}} |
			 {stop, Reason::atom(), LD::#loop_data{}}.

handle_call({set, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}, Flag}, _From, LD) ->
    ?dbg("handle_call: store all",[]),
    handle_store(LD, Flag);
handle_call({set, {?IX_STORE_PARAMETERS, _Si}, _NewValue}, _From, LD) ->
    ?dbg("handle_call: set store unknown subindex ~.8B ",[_Si]),    
    {reply, {error, ?abort_no_such_subindex}, LD};
handle_call({set, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL}, Flag}, _From, LD) ->
    ?dbg("handle_call: restore all",[]),
    handle_restore(LD, Flag);
handle_call({set, {?IX_RESTORE_DEFAULT_PARAMETERS, _Si}, _NewValue}, _From, LD) ->
    ?dbg("handle_call: set restore unknown subindex ~.8B ",[_Si]),    
    {reply, {error, ?abort_no_such_subindex}, LD};
handle_call({set, {_Ix, _Si}, _NewValue}, _From, LD) ->
    ?dbg("handle_call: set ~.16B:~.8B ",[_Ix, _Si]),    
    {reply, {error, ?abort_no_such_object}, LD};
handle_call({get, {?IX_STORE_PARAMETERS, 0}}, _From, LD) ->
    ?dbg("handle_call: get object size = 1",[]),    
    {reply, {ok, 1}, LD};
handle_call({get, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}}, _From, LD) ->
    ?dbg("handle_call: get store all",[]),
    %% Device supports save on command
    {reply, {ok, 0}, LD};
handle_call({get, {?IX_STORE_PARAMETERS, _Si}}, _From, LD) ->
    ?dbg("handle_call: get store unknown subindex ~.8B ",[_Si]),    
    {reply, {error, ?abort_no_such_subindex}, LD};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, 0}}, _From, LD) ->
    ?dbg("handle_call: get object size = 3",[]),    
    {reply, {ok, 3}, LD};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_STORE_ALL}}, _From, LD) ->
    ?dbg("handle_call: get store_all",[]),
    %% Device supports save on command
    {reply, {ok, 0}, LD};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, _Si}}, _From, LD) ->
    ?dbg("handle_call: get unknown subindex ~.8B ",[_Si]),    
    {reply, {error, ?abort_no_such_subindex}, LD};
handle_call({get, {_Ix, _Si}}, _From, LD) ->
    ?dbg("handle_call: get ~.16B:~.8B ",[_Ix, _Si]),
    {reply, {error, ?abort_no_such_object}, LD};
handle_call(loop_data, _From, LD) ->
    io:format("~p: LD = ~p", [?MODULE,LD]),
    {reply, ok, LD};
handle_call({debug, TrueOrFalse}, _From, LD) ->
    co_lib:debug(TrueOrFalse),
    {reply, ok, LD};
handle_call(stop, _From, LD) ->
    ?dbg("handle_call: stop",[]),    
    handle_stop(LD);
handle_call(_Request, _From, LD) ->
    ?dbg("handle_call: bad call ~p.",[_Request]),
    {reply, {error, ?abort_internal_error}, LD}.

handle_store(LD=#loop_data {co_node = CoNode}, ?EVAS) ->
    case co_api:save_dict(CoNode) of
	ok ->
	    {reply, ok, LD};
	{error, _Reason} ->
	    ?dbg("handle_store: save_dict failed, reason = ~p ",[_Reason]),
	    {reply, {error, ?abort_hardware_failure}, LD}
    end;
handle_store(LD, _NotOk) ->
    ?dbg("handle_store: incorrect flag = ~p ",[_NotOk]),
    {reply, {error, ?abort_local_control_error}, LD}.

handle_restore(LD=#loop_data {co_node = CoNode}, ?DOAL) ->
    case co_api:load_dict(CoNode) of
	ok ->
	    {reply, ok, LD};
	{error, _Reason} ->
	    ?dbg("handle_restore: save_dict failed, reason = ~p ",[_Reason]),
	    {reply, {error, ?abort_hardware_failure}, LD}
    end;
handle_restore(LD, _NotOk) ->
    ?dbg("handle_restore: incorrect flag = ~p ",[_NotOk]),
    {reply, {error, ?abort_local_control_error}, LD}.


handle_stop(LD=#loop_data {co_node = CoNode}) ->
    case co_api:alive(CoNode) of
	true ->
	    co_api:unreserve(CoNode, ?IX_STORE_PARAMETERS),
	    co_api:unreserve(CoNode, ?IX_RESTORE_DEFAULT_PARAMETERS),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg("handle_stop: detached.",[]),
    {stop, normal, ok, LD}.

%%--------------------------------------------------------------------
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), LD::#loop_data{}) ->
			 {noreply, LD::#loop_data{}} |
			 {noreply, LD::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), LD::#loop_data{}}.
			 
handle_cast({name_change, OldName, NewName}, 
	    LD=#loop_data {co_node = {name, OldName}}) ->
   ?dbg("handle_cast: co_node name change from ~p to ~p.", 
	 [OldName, NewName]),
    {noreply, LD#loop_data {co_node = {name, NewName}}};

handle_cast({name_change, _OldName, _NewName}, LD) ->
   ?dbg("handle_cast: co_node name change from ~p to ~p, ignored.", 
	 [_OldName, _NewName]),
    {noreply, LD};

handle_cast(_Msg, LD) ->
    ?dbg("handle_cast: Message = ~p. ", [_Msg]),
    {noreply, LD}.


%%--------------------------------------------------------------------
%% @doc
%% Handling all non call/cast messages.
%%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info::term(), LD::#loop_data{}) ->
			 {noreply, LD::#loop_data{}} |
			 {noreply, LD::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), LD::#loop_data{}}.
			 
handle_info(_Info, LD) ->
    ?dbg("handle_info: Unknown Info ~p", [_Info]),
    {noreply, LD}.

%%--------------------------------------------------------------------
%% @private
%%
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), LD::#loop_data{}) -> 
		       no_return().

terminate(_Reason, _LD) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%%
%% @doc
%% Convert process loop data when code is changed.
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), LD::#loop_data{}, Extra::term()) -> 
			 {ok, NewLD::#loop_data{}}.

code_change(_OldVsn, LD, _Extra) ->
    %% Note!
    %% If the code change includes a change in which indexes that should be
    %% reserved it is vital to unreserve the indexes no longer used.
    {ok, LD}.

     
%%%===================================================================
%%% Support functions
%%%===================================================================
name(CoNode) when is_integer(CoNode) ->
    list_to_atom(atom_to_list(?MODULE) ++ erlang:integer_to_list(CoNode,16));
name({name, CoNode}) when is_atom(CoNode)->
    list_to_atom(atom_to_list(?MODULE) ++ atom_to_list(CoNode)).

