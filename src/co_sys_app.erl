%%-------------------------------------------------------------------
%% @author Malotte W Lönne <malotte@malotte.net>
%% @copyright (C) 2012, Tony Rogvall
%% @doc
%%    System command CANopen application.<br/>
%%    Implements index 16#1010 (save), 16#1011(load).<br/>
%%    save - stores the CANOpen node dictionary.<br/>
%%    load - restores the CANOpen node dictionary.<br/>
%%
%% File: co_os_app.erl<br/>
%% Created: December 2011 by Malotte W Lönne
%% @end
%%===================================================================
-module(co_sys_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_app).

%% API
-export([start_link/1, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% co_app callbacks
-export([index_specification/2,
	 set/3, get/2]).

%% Test
-export([loop_data/1,
	 debug/2]).

-define(NAME, co_sys).

%% Flags to indicate if store/restore command is valid
-define(EVAS, 1935767141). %% $e + ($v bsl 8) + ($a bsl 16) + ($s bsl 24)
-define(DOAL, 1819238756). %% $d + ($a bsl 8) + ($o bsl 16) + ($l bsl 24)

-record(loop_data,
	{
	  state           ::atom(),
	  co_node         ::atom()     %% Name of co_node
	}).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link(CoSerial::integer()) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::atom()}.

start_link(CoSerial) ->
    gen_server:start_link({local, name(CoSerial)}, ?MODULE, CoSerial,[]).
	
%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop(CoSerial::integer()) -> ok | 
		{error, Error::atom()}.

stop(CoSerial) ->
    case whereis(name(CoSerial)) of
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
-spec index_specification(Pid::pid(), {Index::integer(), SubInd::integer()}) -> 
		       {spec, Spec::record()} |
		       {error, Reason::atom()}.

index_specification(_Pid, {?IX_STORE_PARAMETERS = _Index, 255} = I) ->
    ?dbg(?NAME,"index_specification: store type ~.16B ",[_Index]),
    Value = ((?UNSIGNED32 band 16#ff) bsl 8) bor (?OBJECT_ARRAY band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?IX_STORE_PARAMETERS, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 1});
index_specification(_Pid, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL} = I) ->
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RW, atomic, 9000);
index_specification(Pid, Index) when is_integer(Index) ->
    index_specification(Pid, {Index, 0});
index_specification(_Pid, {?IX_STORE_PARAMETERS, _SubInd})  ->
    ?dbg(?NAME,"index_specification: store unknown subindex ~.8B ",[_SubInd]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS = _Index, 255} = I) ->
    ?dbg(?NAME,"index_specification: restore type ~.16B ",[_Index]),
    Value = ((?UNSIGNED32 band 16#ff) bsl 8) bor (?OBJECT_ARRAY band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 1});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL} = I) ->
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RW, atomic, 9000);
index_specification(Pid, Index) when is_integer(Index) ->
    index_specification(Pid, {Index, 0});
index_specification(_Pid, {?IX_RESTORE_DEFAULT_PARAMETERS, _SubInd})  ->
    ?dbg(?NAME,"index_specification: restore unknown subindex ~.8B ",[_SubInd]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {_Index, _SubInd})  ->
    ?dbg(?NAME,"index_specification: unknown index ~.16B:~.8B ",[_Index, _SubInd]),
    {error, ?abort_no_such_object}.

reply_specification({_Index, _SubInd} = I, Type, Access, Mode) ->
    reply_specification({_Index, _SubInd} = I, Type, Access, Mode, undefined).

reply_specification({_Index, _SubInd} = I, Type, Access, Mode, TOut) ->
    ?dbg(?NAME,"reply_specification: ~.16B:~.8B, "
	 "type = ~w, access = ~w, mode = ~w, timeout = ~p",
	 [_Index, _SubInd, Type, Access, Mode, TOut]),
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
-spec set(Pid::pid(), {Index::integer(), SubInd::integer()}, NewValue::term()) ->
		 ok |
		 {error, Reason::atom()}.

set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg(?NAME," set ~.16B:~.8B to ~p",[Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).

%%--------------------------------------------------------------------
%% @doc
%% Gets Value for {Index, SubInd}.<br/>
%% Used for transfer_mode = {atomic, Module}.
%% @end
%%--------------------------------------------------------------------
-spec get(Pid::pid(), {Index::integer(), SubInd::integer()}) ->
		 {ok, Value::term()} |
		 {error, Reason::atom()}.

get(Pid, {Index, SubInd}) ->
    ?dbg(?NAME," get ~.16B:~.8B",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).


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
%% @spec init(Args) -> {ok, LoopData} |
%%                     {ok, LoopData, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
init(CoSerial) ->
    {ok, _Dict} = co_api:attach(CoSerial),
    co_api:reserve(CoSerial, ?IX_STORE_PARAMETERS, ?MODULE),
    co_api:reserve(CoSerial, ?IX_RESTORE_DEFAULT_PARAMETERS, ?MODULE),
    {ok, #loop_data {state=running, co_node = CoSerial}}.


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
	{get, {Index::integer(), SubIndex::integer()}} |
	{set, {Index::integer(), SubInd::integer()}, Value::term()} |
	stop.

-spec handle_call(Request::call_request(), From::pid(), LoopData::#loop_data{}) ->
			 {reply, Reply::term(), LoopData::#loop_data{}} |
			 {reply, Reply::term(), LoopData::#loop_data{}, Timeout::timeout()} |
			 {noreply, LoopData::#loop_data{}} |
			 {noreply, LoopData::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), Reply::term(), LoopData::#loop_data{}} |
			 {stop, Reason::atom(), LoopData::#loop_data{}}.

handle_call({set, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}, Flag}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: store all",[]),
    handle_store(LoopData, Flag);
handle_call({set, {?IX_STORE_PARAMETERS, _SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: set store unknown subindex ~.8B ",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({set, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_RESTORE_ALL}, Flag}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: restore all",[]),
    handle_restore(LoopData, Flag);
handle_call({set, {?IX_RESTORE_DEFAULT_PARAMETERS, _SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: set restore unknown subindex ~.8B ",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({set, {_Index, _SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: set ~.16B:~.8B ",[_Index, _SubInd]),    
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({get, {?IX_STORE_PARAMETERS, 0}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get object size = 1",[]),    
    {reply, {ok, 1}, LoopData};
handle_call({get, {?IX_STORE_PARAMETERS, ?SI_STORE_ALL}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get store all",[]),
    %% Device supports save on command
    {reply, {ok, 0}, LoopData};
handle_call({get, {?IX_STORE_PARAMETERS, _SubInd}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get store unknown subindex ~.8B ",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, 0}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get object size = 3",[]),    
    {reply, {ok, 3}, LoopData};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, ?SI_STORE_ALL}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get store_all",[]),
    %% Device supports save on command
    {reply, {ok, 0}, LoopData};
handle_call({get, {?IX_RESTORE_DEFAULT_PARAMETERS, _SubInd}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get unknown subindex ~.8B ",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({get, {_Index, _SubInd}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get ~.16B:~.8B ",[_Index, _SubInd]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p", [?MODULE,LoopData]),
    {reply, ok, LoopData};
handle_call({debug, TrueOrFalse}, _From, LoopData) ->
    put(dbg, TrueOrFalse),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ?dbg(?NAME," handle_call: stop",[]),    
    handle_stop(LoopData);
handle_call(_Request, _From, LoopData) ->
    ?dbg(?NAME," handle_call: bad call ~p.",[_Request]),
    {reply, {error, ?abort_internal_error}, LoopData}.

    
handle_store(LoopData=#loop_data {co_node = CoNode}, ?EVAS) ->
    case co_api:save_dict(CoNode) of
	ok ->
	    {reply, ok, LoopData};
	{error, _Reason} ->
	    ?dbg(?NAME, "handle_store: save_dict failed, reason = ~p ",[_Reason]),
	    {reply, {error, ?abort_hardware_failure}, LoopData}
    end;
handle_store(LoopData, _NotOk) ->
    ?dbg(?NAME, "handle_store: incorrect flag = ~p ",[_NotOk]),
    {reply, {error, ?abort_local_control_error}, LoopData}.

handle_restore(LoopData=#loop_data {co_node = CoNode}, ?DOAL) ->
    case co_api:load_dict(CoNode) of
	ok ->
	    {reply, ok, LoopData};
	{error, _Reason} ->
	    ?dbg(?NAME, "handle_restore: save_dict failed, reason = ~p ",[_Reason]),
	    {reply, {error, ?abort_hardware_failure}, LoopData}
    end;
handle_restore(LoopData, _NotOk) ->
    ?dbg(?NAME, "handle_restore: incorrect flag = ~p ",[_NotOk]),
    {reply, {error, ?abort_local_control_error}, LoopData}.


handle_stop(LoopData=#loop_data {co_node = CoNode}) ->
    case co_api:alive(LoopData#loop_data.co_node) of
	true ->
	    co_api:unreserve(CoNode, ?IX_STORE_PARAMETERS),
	    co_api:unreserve(CoNode, ?IX_RESTORE_DEFAULT_PARAMETERS),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg(?NAME," handle_stop: detached.",[]),
    {stop, normal, ok, LoopData}.


%%--------------------------------------------------------------------
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
-type cast_msg()::go.

-spec handle_cast(Msg::cast_msg(), LoopData::#loop_data{}) ->
			 {noreply, LoopData::#loop_data{}} |
			 {noreply, LoopData::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), LoopData::#loop_data{}}.
			 
handle_cast(_Msg, LoopData) ->
    ?dbg(?NAME," handle_cast: Message = ~p. ", [_Msg]),
    {noreply, LoopData}.


%%--------------------------------------------------------------------
%% @doc
%% Handling all non call/cast messages.
%%
%% Info types:
%% {notify, RemoteCobId, Index, SubInd, Value} - 
%%   When Index subscribed to by this process has been updated. <br/>
%% RemoteCobId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{notify, RemoteCobId::term(), Index::integer(), SubInd::integer(), Value::term()} |
	%% Unknown info
	term().

-spec handle_info(Info::info(), LoopData::#loop_data{}) ->
			 {noreply, LoopData::#loop_data{}} |
			 {noreply, LoopData::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), LoopData::#loop_data{}}.
			 
handle_info({notify, _RemoteCobId, _Index, _SubInd, _Value}, LoopData) ->
    ?dbg(?NAME," handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w ", 
	      [_RemoteCobId, _Index, _SubInd, _Value]),
    {noreply, LoopData};
handle_info(_Info, LoopData) ->
    ?dbg(?NAME," handle_info: Unknown Info ~p", [_Info]),
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, LoopData) -> void()
%%
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _LoopData) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @spec code_change(OldVsn, LoopData, Extra) -> {ok, NewLoopData}
%%
%% @doc
%% Convert process loop data when code is changed
%%
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, LoopData, _Extra) ->
    %% Note!
    %% If the code change includes a change in which indexes that should be
    %% reserved it is vital to unreserve the indexes no longer used.
    {ok, LoopData}.

     
name(CoSerial) ->
    list_to_atom(atom_to_list(?MODULE) ++ integer_to_list(CoSerial,16)).
