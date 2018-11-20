%% coding: latin-1
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
%%-------------------------------------------------------------------
%% @author Malotte W Lönne <malotte@malotte.net>
%% @copyright (C) 2012, Tony Rogvall
%% @doc
%%    Example CANOpen application.
%%
%%    Responsible for index MY_INDEX. <br/>
%%      MY_INDEX:0 - size = unsigned8, access ro, value 2 <br/>
%%      MY_INDEX:1 - entry1 = unsigned32, access rw <br/>
%%      MY_INDEX:2 - entry2 = visible_string, access rw <br/>
%%
%% File: co_ex_app.erl<br/>
%% Created: April 2012 by Malotte W Lönne<br/>
%% @end
%%===================================================================
-module(co_ex_app).
-include("../include/canopen.hrl").
-include("../include/co_app.hrl").
-include("../include/co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_app).

%% API
-export([start/1, stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% co_app callbacks
-export([index_specification/2,
	 set/3, get/2]).

%% Test
-export([loop_data/0,
	 debug/1]).

-define(NAME, co_example).
-define(MY_INDEX, 16#9898).
-define(SUBSCRIBED_INDEX, 16#9899).

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
-spec start(CoSerial::integer()) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::atom()}.

start(CoSerial) ->
    gen_server:start({local, ?NAME}, ?MODULE, CoSerial,[]).
	
%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | 
		{error, Error::atom()}.

stop() ->
    case whereis(?NAME) of
	undefined -> do_nothing;
	Pid -> gen_server:call(Pid, stop)
    end.

%%--------------------------------------------------------------------
%%% Callbacks for co_app behaviour.
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
-spec index_specification(Pid::pid(), {Index::integer(), SubInd::integer()}) -> 
		       {spec, Spec::#index_spec{}} |
		       {error, Reason::atom()}.

index_specification(_Pid, {?MY_INDEX = _Index, 255} = I) ->
    ?dbg("index_specification: store type ~.16B ",[_Index]),
    Value = ((?UNSIGNED32 band 16#ff) bsl 8) bor (?VISIBLE_STRING band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?MY_INDEX, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 2});
index_specification(_Pid, {?MY_INDEX, 1} = I) ->
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RW, atomic);
index_specification(_Pid, {?MY_INDEX, 2} = I) ->
    reply_specification(I, ?VISIBLE_STRING, ?ACCESS_RW, atomic);
index_specification(_Pid, {?MY_INDEX, _SubInd})  ->
    ?dbg("index_specification: unknown subindex ~.8B ",[_SubInd]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {_Index, _SubInd})  ->
    ?dbg("index_specification: unknown index ~.16B:~.8B ",[_Index, _SubInd]),
    {error, ?abort_no_such_object}.

reply_specification({_Index, _SubInd} = I, Type, Access, Mode) ->
    ?dbg("reply_specification: ~.16B:~.8B, "
	 "type = ~w, access = ~w, mode = ~w", 
	 [_Index, _SubInd, Type, Access, Mode]),
    Spec = #index_spec{index = I,
		       type = Type,
		       access = Access,
		       transfer = Mode},
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

set(_Pid, Index = {_Ix, _Si}, NewValue) ->
    ?dbg(" set ~.16#:~.8# to ~p",[_Ix, _Si, NewValue]),
    handle_set(Index, NewValue).

%%--------------------------------------------------------------------
%% @doc
%% Gets Value for {Index, SubInd}.<br/>
%% Used for transfer_mode = {atomic, Module}.
%% @end
%%--------------------------------------------------------------------
-spec get(Pid::pid(), {Index::integer(), SubInd::integer()}) ->
		 {ok, Value::term()} |
		 {error, Reason::atom()}.

get(_Pid, Index = {_Ix, _Si}) ->
    ?dbg(" get ~.16#:~.8#",[_Ix, _Si]),
    handle_get(Index).


%% Test functions
%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?NAME, {debug, TrueOrFalse}).

%% @private
loop_data() ->
    gen_server:call(?NAME, loop_data).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec init(CoSerial::term()) -> {ok, LoopData::#loop_data{}} |
				{stop, Reason::term()}.

init(CoSerial) ->
    {ok, _Dict} = co_api:attach(CoSerial),
    co_api:reserve(CoSerial, ?MY_INDEX, ?MODULE),
    co_api:subscribe(CoSerial, ?SUBSCRIBED_INDEX),
    ets:new(co_ex_table, [public, named_table, ordered_set]),

    %% Insert default values
    ets:insert(co_ex_table, {{?MY_INDEX, 1}, 0}),
    ets:insert(co_ex_table, {{?MY_INDEX, 2}, "undefined"}),

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
%% For description of requests compare with the corresponding functions:
%% @see set/3  
%% @see get/2 
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{get, {Index::integer(), SubIndex::integer()}} |
	{set, {Index::integer(), SubInd::integer()}, Value::term()} |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), term()}, LoopData::#loop_data{}) ->
			 {reply, Reply::term(), LoopData::#loop_data{}} |
			 {reply, Reply::term(), LoopData::#loop_data{}, Timeout::timeout()} |
			 {noreply, LoopData::#loop_data{}} |
			 {noreply, LoopData::#loop_data{}, Timeout::timeout()} |
			 {stop, Reason::atom(), Reply::term(), LoopData::#loop_data{}} |
			 {stop, Reason::atom(), LoopData::#loop_data{}}.

handle_call({set, Index, Value}, _From, LoopData) ->
    {reply, handle_set(Index, Value), LoopData};

handle_call({get, Index}, _From, LoopData) ->
    {reply, handle_get(Index), LoopData};

handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p", [?MODULE,LoopData]),
    {reply, ok, LoopData};

handle_call({debug, TrueOrFalse}, _From, LoopData) ->
    put(dbg, TrueOrFalse),
    {reply, ok, LoopData};

handle_call(stop, _From, LoopData=#loop_data {co_node = CoNode}) ->
    ?dbg(" handle_call: stop",[]),    
    case co_api:alive(CoNode) of
	true ->
	    co_api:unreserve(CoNode, ?IX_STORE_PARAMETERS),
	    co_api:unreserve(CoNode, ?IX_RESTORE_DEFAULT_PARAMETERS),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg(" handle_stop: detached.",[]),
    {stop, normal, ok, LoopData};

handle_call(_Request, _From, LoopData) ->
    ?dbg(" handle_call: bad call ~p.",[_Request]),
    {reply, {error, ?abort_internal_error}, LoopData}.

    
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
    ?dbg(" handle_cast: Message = ~p. ", [_Msg]),
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
			 
handle_info({object_event, ?SUBSCRIBED_INDEX = I}, LoopData) ->
    ?dbg(" handle_info: object_event for ~.16#",  [I]),
    do_something,
    {noreply, LoopData};
handle_info({object_event, _I}, LoopData) ->
    ?dbg(" handle_info: object_event unknwon index ~.16#",  [_I]),
    {noreply, LoopData};
handle_info(_Info, LoopData) ->
    ?dbg(" handle_info: Unknown Info ~p", [_Info]),
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), LoopData::#loop_data{}) -> 
		       no_return().

terminate(_Reason, _LoopData) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process loop data when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), LoopData::#loop_data{}, Extra::term()) -> 
			 {ok, NewLoopData::#loop_data{}}.

code_change(_OldVsn, LoopData, _Extra) ->
    %% Note!
    %% If the code change includes a change in which indexes that should be
    %% reserved it is vital to unreserve the indexes no longer used.
    {ok, LoopData}.

     
%%%===================================================================
%%% Support functions
%%%===================================================================
handle_set({?MY_INDEX, 0}, _Value) ->
    ?dbg(" handle_set: 0 not allowed",[]),
    {error, ?abort_unsupported_access};
handle_set({?MY_INDEX, 1} = Index, Value) 
  when is_integer(Value)->
    ?dbg(" handle_set: 1 to ~p",[Value]),
    handle_set1(Index, Value);
handle_set({?MY_INDEX, 1}, Value) ->
    ?dbg(" handle_set: 1 to ~p",[Value]),
    {error, ?abort_parameter_error};
handle_set({?MY_INDEX, 2} = Index, Value) 
  when is_list(Value) ->
    ?dbg(" handle_set: 2 to ~p",[Value]),
    handle_set1(Index, Value);
handle_set({?MY_INDEX, 2}, Value) ->
    ?dbg(" handle_set: 2 to ~p",[Value]),
    {error, ?abort_parameter_error};
handle_set({?MY_INDEX, _SubInd}, _Value) ->
    ?dbg( "handle_set: unknown subindex ~.8B ",[_SubInd]),    
    {error, ?abort_no_such_subindex};
handle_set({_Index, _SubInd}, _NewValue) ->
    ?dbg( "handle_set, unknown index ~.16B:~.8B ",[_Index, _SubInd]),    
    {error, ?abort_no_such_object};
handle_set(Index, NewValue) 
  when is_integer(Index) ->
    handle_set({Index,0}, NewValue).

handle_set1(Index, Value) ->
    try ets:insert(co_ex_table, {Index, Value}) of
	true ->
	    ok
    catch error:_Reason ->
	    ?dbg( "handle_set: set failed, reason = ~p ",[_Reason]),
	    {error, ?abort_hardware_failure}
    end.

handle_get({?MY_INDEX, 0}) ->
    ?dbg( "handle_call: get object size = 1",[]),    
    {ok, 2};
handle_get({?MY_INDEX, 1} = Index) ->
    ?dbg( "handle_call: get 1",[]),
    handle_get1(Index);
handle_get({?MY_INDEX, 2} = Index) ->
    ?dbg( "handle_call: get 2",[]),
    handle_get1(Index);
handle_get({?MY_INDEX, _SubInd}) ->
    ?dbg( "handle_get: unknown subindex ~.8B ",[_SubInd]),    
    {error, ?abort_no_such_subindex};
handle_get({_Index, _SubInd}) ->
    ?dbg( "handle_get: unknown index ~.16B:~.8B ",[_Index, _SubInd]),
   {error, ?abort_no_such_object};
handle_get(Index) 
  when is_integer(Index)->
    handle_get({Index, 0}).

handle_get1(Index) ->
    case ets:lookup(co_ex_table, Index) of
	[{Index, Value}] ->
	    {ok, Value};
	_Other ->
	    ?dbg( "handle_get: get failed, got = ~p ",[_Other]),
	    {error, ?abort_hardware_failure}
    end.


