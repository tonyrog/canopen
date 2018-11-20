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
%% @author Malotte W Lonne <malotte@malotte.net>
%% @copyright (C) 2011, Tony Rogvall
%% @doc
%%    Example CANopen application.
%% 
%% Required minimum API:
%% <ul>
%% <li>handle_call - get</li>
%% <li>handle_call - set</li>
%% <li>handle_info - notify</li>
%% </ul>
%% @end
%%===================================================================

-module(co_test_app).
-include("../include/canopen.hrl").
-include("../include/co_app.hrl").

-behaviour(gen_server).
-behaviour(co_app).

-compile(export_all).

%% API
-export([start/2, stop/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% CO node callbacks
-export([index_specification/2,
	 set/3, get/2,
	 write_begin/3, write/4,
	 read_begin/3, read/3,
	 abort/2]).


%% Testing
-define(dbg(Format, Args),
	Dbg = get(dbg),
	if Dbg ->
		ct:pal("~p(~p): " ++ Format ++ "\n", [?MODULE, self() | Args]);
	   true ->
		ok
	end).

-record(loop_data,
	{
	  state,
	  co_node,
	  dict,
	  name_table,
	  starter,
	  write_size = 28,
	  store
	}).

-record(store,
	{
	  ref,
	  index,
	  type,
	  data
	}).

%%--------------------------------------------------------------------
%% @spec start(CoNode) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%%
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start(CoNode, Dict) ->
    gen_server:start_link({local, co_test_lib:name(?MODULE, CoNode)}, 
			  ?MODULE, {CoNode, Dict, self()}, []).

   	
%%--------------------------------------------------------------------
%% @spec stop() -> ok | {error, Error}
%% @doc
%%
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop(CoNode) ->
    AppName = co_test_lib:name(?MODULE, CoNode),
    case whereis(AppName) of
	undefined  -> do_nothing;
	Pid ->   gen_server:call(Pid, stop)
    end.

 
%%--------------------------------------------------------------------
%% @spec index_specification(Pid, {Index, SubInd}) -> 
%%   {entry, Entry::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
index_specification(Pid, {Index, 255}) ->
    ?dbg("index_specification type ~.16B ",[Index]),
    case ets:lookup(dict_table(Pid), {Index, 0}) of
	[{I, Type, _Transfer}] ->
	    %% VAR/ARRAY .. fixme
	    Value = (co_test_lib:type(Type) bsl 8) bor ?OBJECT_VAR, 
	    Spec = #index_spec{index = I,
			       type = ?UNSIGNED32,
			       access = ?ACCESS_RO,
			       transfer = {value, Value}},
	    {spec,Spec};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
index_specification(Pid, {Index, SubInd} = I) ->
    ?dbg("index_specification ~.16B:~.8B ",[Index, SubInd]),
    
    [{change_timeout, CI}] = ets:lookup(name_table(Pid), change_timeout),
    NewTimeOut = case Index of
		     CI ->
			 %% To test timeout change
			 ?dbg("handle_call: setting timeout to 4000", []), 
			 4000;
		     _Other ->
			 undefined
		 end,

    case ets:lookup(dict_table(Pid), I) of
	[{I, Type, Transfer, _Value}] ->
	    Spec = #index_spec{index = I,
			       type = co_test_lib:type(Type),
			       access = ?ACCESS_RW,
			       transfer = Transfer,
			       timeout = NewTimeOut},
	    {spec, Spec};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
index_specification(Pid, Index) when is_integer(Index) ->
    index_specification(Pid, {Index, 0}).
    
%% transfer_mode == {atomic, Module}
set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg("set ~.16B:~.8B to ~p",[Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).
get(Pid, {Index, SubInd}) ->
    ?dbg("get ~.16B:~.8B",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).

%% transfer_mode = {streamed, Module}
write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("write_begin ~.16B:~.8B, ref = ~p",[Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).
write(Pid, Ref, Data, EodFlag) ->
    ?dbg("write ref = ~p, data = ~p, Eod = ~p",[Ref, Data, EodFlag]),
    gen_server:call(Pid, {write, Ref, Data, EodFlag}).

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("read_begin ~.16B:~.8B, ref = ~p",[Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
read(Pid, Ref, Bytes) ->
    ?dbg("read ref = ~p, ",[Ref]),
    gen_server:call(Pid, {read, Ref, Bytes}).

abort(Pid, Ref) ->
    ?dbg("abort ref = ~p",[Ref]),
    gen_server:call(Pid, {abort, Ref}).
    

loop_data(CoNode) ->
    gen_server:call(co_test_lib:name(?MODULE, CoNode), loop_data).

dict(CoNode) ->
    gen_server:call(co_test_lib:name(?MODULE, CoNode), dict).

debug(Pid, TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(Pid, {debug, TrueOrFalse}).

write_size(Pid, NewSize) when is_integer(NewSize) ->
    gen_server:call(Pid, {write_size, NewSize}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, LD} |
%%                     {ok, LD, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
init({CoNode, Dict, Starter}) ->
    DictTable = ets:new(dict_table(self()), [public, named_table, ordered_set]),
    NameTable = ets:new(name_table(self()), [public, named_table, ordered_set]),
    {ok, _DictRef} = co_api:attach(CoNode),
    load_dict(CoNode, Dict, DictTable, NameTable),
    {ok, #loop_data {state=init, co_node = CoNode, dict=DictTable, 
		     name_table=NameTable, starter = Starter}}.

dict_table(Pid) ->
    list_to_atom("dict" ++ pid_to_list(Pid)).

name_table(Pid) ->
    list_to_atom("name" ++ pid_to_list(Pid)).

load_dict(CoNode, Dict, DictTable, NameTable) ->
    ?dbg("Dict ~p", [Dict]),
    lists:foreach(fun({Name, 
		       {{Index, _SubInd}, _Type, _Mode, _Value} = Entry}) ->
			  ets:insert(DictTable, Entry),
			  ?dbg("Inserting entry = ~p", [Entry]),
			  ets:insert(NameTable, {Name, Index}),
			  case Name of
			      notify ->			      
				  co_api:subscribe(CoNode, Index);
			      mpdo ->			      
				  co_api:subscribe(CoNode, Index);
			      _Other ->
				  co_api:reserve(CoNode, Index, ?MODULE)
			  end
		  end, Dict).

%%--------------------------------------------------------------------
%% @spec handle_call(Request, From, LD) ->
%%                                   {reply, Reply, LD} |
%%                                   {reply, Reply, LD, Timeout} |
%%                                   {noreply, LD} |
%%                                   {noreply, LD, Timeout} |
%%                                   {stop, Reason, Reply, LD} |
%%                                   {stop, Reason, LD}
%%
%% Request = {get, Index, SubIndex} |
%%           {set, Index, SubInd, Value}
%% LD = term()
%% Index = integer()
%% SubInd = integer()
%% Value = term()
%%
%% @doc
%% Handling call messages.
%% Required to at least handle get and set requests as specified above.
%% Handling all non call/cast messages.
%% Required to at least handle a notify msg as specified above. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_call({get, {Index, SubInd}}, _From, LD) ->
    ?dbg("handle_call: get ~.16B:~.8B ",[Index, SubInd]),

    maybe_add_timeout(Index, LD),

    case ets:lookup(LD#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD};
	[{{Index, SubInd}, _Type, _Transfer, Value}] ->
	    {reply, {ok, Value}, LD}
    end;
handle_call({set, {Index, SubInd}, NewValue}, _From, LD) ->
     ?dbg("handle_call: set ~.16B:~.8B to ~p", [Index, SubInd, NewValue]),

    maybe_add_timeout(Index, LD),
    
    handle_set(LD, {Index, SubInd}, NewValue, undefined);
%% transfer_mode == streamed
handle_call({write_begin, {Index, SubInd} = I, Ref}, _From, LD) ->
    ?dbg("handle_call: write_begin ~.16B:~.8B, ref = ~p", [Index, SubInd, Ref]),
    case ets:lookup(LD#loop_data.dict, I) of
	[] ->
	    ?dbg("handle_call: write_begin error = ~.16B", [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD};
	[{I, Type, _Transfer, _OldValue}] ->
	    Store = #store {ref = Ref, index = I, type = Type},
	    {reply, {ok, Ref, LD#loop_data.write_size}, LD#loop_data {store = Store}}
    end;
handle_call({write, Ref, Data, Eod}, _From, LD) ->
    ?dbg("handle_call: write ref = ~p, data = ~p",[Ref, Data]),
    Store = case LD#loop_data.store#store.data of
		undefined ->
		    LD#loop_data.store#store {data = <<Data/binary>>};
		OldData ->
		    LD#loop_data.store#store {data = <<OldData/binary, Data/binary>>}
	    end,
    if Eod ->
	    NewValue = co_codec:decode(Store#store.data, 
					    co_test_lib:type(Store#store.type)),
	    ?dbg("handle_call: write decoded data = ~p",[NewValue]),
	    handle_set(LD,Store#store.index, NewValue, Ref);
       true ->
	    {reply, {ok, Ref}, LD#loop_data {store = Store}}
    end;
handle_call({read_begin, {16#6037 = Index, SubInd} = I, Ref}, _From, LD) ->
    %% To test 'real' streaming
    ?dbg("handle_call: read_begin ~.16B:~.8B, ref = ~p", [Index, SubInd, Ref]),
    case ets:lookup(LD#loop_data.dict, I) of
	[] ->
	    ?dbg("handle_call: read_begin error = ~.16B", [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD};
	[{I, Type, _Transfer, Value}] ->
	    Data = co_codec:encode(Value, co_test_lib:type(Type)),
	    Store = #store {ref = Ref, index = I, type = Type, data = Data},
	    {reply, {ok, Ref, unknown}, LD#loop_data {store = Store}}
    end;
handle_call({read_begin, {Index, SubInd} = I, Ref}, _From, LD) ->
    ?dbg("handle_call: read_begin ~.16B:~.8B, ref = ~p", [Index, SubInd, Ref]),
    case ets:lookup(LD#loop_data.dict, I) of
	[] ->
	    ?dbg("handle_call: read_begin error = ~.16B", [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD};
	[{I, Type, _Transfer, Value}] ->
	    Data = co_codec:encode(Value, co_test_lib:type(Type)),
	    Size = size(Data),
	    Store = #store {ref = Ref, index = I, type = Type, data = Data},
	    {reply, {ok, Ref, Size}, LD#loop_data {store = Store}}
    end;
handle_call({read, Ref, Bytes}, _From, LD) ->
    ?dbg("handle_call: read ref = ~p",[Ref]),
    Store = LD#loop_data.store,
    Data = Store#store.data,
    Size = size(Data),
    case Size - Bytes of
	RestSize when RestSize > 0 -> 
	    <<DataToSend:Bytes/binary, RestData/binary>> = Data,
	    Store1 = Store#store {data = RestData},
	    {reply, {ok, Ref, DataToSend, false}, LD#loop_data {store = Store1}};
	RestSize when RestSize < 0 ->
	    Store1 = Store#store {data = (<<>>)},
	    {reply, {ok, Ref, Data, true}, LD#loop_data {store = Store1}}
    end;
handle_call({abort, Ref}, _From, LD) ->
    ?dbg("handle_call: abort ref = ~p",[Ref]),
    {reply, ok, LD};
handle_call(loop_data, _From, LD) ->
    io:format("~p: LD = ~p", [?MODULE, LD]),
    {reply, ok, LD};
handle_call(dict, _From, LD) ->
    Dict = ets:tab2list(LD#loop_data.dict),
%%    io:format("~p: Dictionary = ~p", [Dict]),
    {reply, Dict, LD};    
handle_call({debug, TrueOrFalse}, _From, LD) ->
    put(dbg, TrueOrFalse),
    {reply, ok, LD};
handle_call({write_size, NewSize}, _From, LD) ->
    {reply, ok, LD#loop_data {write_size = NewSize}};
handle_call(stop, _From, LD=#loop_data {co_node = CoNode}) ->
    case co_api:alive(CoNode) of
	true ->
	    Name2Index = ets:tab2list(LD#loop_data.name_table),
	    lists:foreach(
	      fun({{Index, _SubInd}, _Type, _Transfer, _Value}) ->
		      case lists:keyfind(Index, 2, Name2Index) of
			  {notify, Ix} ->
			      co_api:unsubscribe(CoNode, Ix);
			  {mpdo, Ix} ->
			      co_api:unsubscribe(CoNode, Ix);
			  {_Any, Ix} ->
			      co_api:unreserve(CoNode, Ix)
		      end
	      end, ets:tab2list(LD#loop_data.dict)),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg("handle_call: stop detached.",[]),
    {stop, normal, ok, LD};
handle_call(Request, _From, LD) ->
    ?dbg("handle_call: bad call ~p.",[Request]),
    {reply, {error,bad_call}, LD}.

handle_set(LD, I, NewValue, Ref) ->
    Reply = case Ref of
		undefined -> ok;
		R -> {ok, R}
	    end,
    case ets:lookup(LD#loop_data.dict, I) of
	[] ->
	    ?dbg("handle_set: set error = ~.16B", [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD};
	[{I, _Type, _Transfer, NewValue}] ->
	    %% No change
	    ?dbg("handle_set: set no change", []),
	    LD#loop_data.starter ! {set, I, NewValue},
	    {reply, Reply, LD};
	[{{Index, SubInd}, Type, Transfer, _OldValue}] ->
	    ets:insert(LD#loop_data.dict, {I, Type, Transfer, NewValue}),
	    ?dbg("handle_set: set ~.16B:~.8B updated to ~p",[Index, SubInd, NewValue]),
	    LD#loop_data.starter ! {set, I, NewValue},
	    {reply, Reply, LD}
    end.

maybe_add_timeout(Index, LD) ->
    [{timeout, TI}] = ets:lookup(LD#loop_data.name_table, timeout),
    [{change_timeout, CI}] = ets:lookup(LD#loop_data.name_table, change_timeout),
    case Index of
	TI ->
	    %% To test timeout
	    ?dbg("handle_call: sleeping for 2 secs", []), 
	    timer:sleep(2000);
	CI ->
	    %% To test change of timeout
	    ?dbg("handle_call: sleeping for 3 secs", []), 
	    timer:sleep(3000);
	_Other ->
	    do_nothing
    end.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, LD) -> {noreply, LD} |
%%                                  {noreply, LD, Timeout} |
%%                                  {stop, Reason, LD}
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast({object_event, Ix}, LD) ->
    ?dbg("handle_cast: My object ~.16# has changed.", [Ix]),
    [{notify, I}] = ets:lookup(LD#loop_data.name_table, notify),
    case Ix of
	I ->
	    {ok, Val} = co_api:value(LD#loop_data.co_node, Ix),
	    ?dbg("New value is ~p", [Val]),
	    LD#loop_data.starter ! {object_event, Ix},
	    ?dbg("Sent object event to ~p", [LD#loop_data.starter]);
	_Other ->
	    ?dbg(" Received object_event for unknown index ~.16#", [Ix])
    end,
    {noreply, LD};
handle_cast(_Msg, LD) ->
    ?dbg("handle_cast: Unknown message ~p. ", [_Msg]),
    {noreply, LD}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, LD) -> {noreply, LD} |
%%                                   {noreply, LD, Timeout} |
%%                                   {stop, Reason, LD}
%%
%% Info = {notify, RemoteCobId, Index, SubInd, Value}
%% LD = term()
%% RemoteCobId = integer()
%% Index = integer()
%% SubInd = integer()
%% Value = term()
%%
%% @doc
%% Handling all non call/cast messages.
%% Required to at least handle a notify msg as specified above. <br/>
%% RemoteCobId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_info({notify, _RemoteCobId, Index, SubInd, Value}, LD) ->
    ?dbg("handle_info: notify ~.16B: ID = ~.16#:~w, Value=~w ", 
	      [_RemoteCobId, Index, SubInd, Value]),
    [{mpdo, I}] = ets:lookup(LD#loop_data.name_table, mpdo),
    case Index of
	I ->
	    LD#loop_data.starter ! {notify, Index},
	    ?dbg("Sent notify to ~p", [LD#loop_data.starter]);
	_Other ->
	    ?dbg(" Received notify for unknown index ~.16#:~w", 
		 [Index, SubInd])
    end,
   {noreply, LD};
handle_info(Info, LD) ->
    ?dbg("handle_info: Unknown Info ~p", [Info]),
    {noreply, LD}.

%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, LD) -> void()
%%
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _LD) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @spec code_change(OldVsn, LD, Extra) -> {ok, NewLD}
%%
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, LD, _Extra) ->
    %% Note!
    %% If the code change includes a change in which indexes that should be
    %% reserved it is vital to unreserve the indexes no longer used.
    {ok, LD}.

