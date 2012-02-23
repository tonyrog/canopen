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

-module(co_ex_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").

-behaviour(gen_server).

-compile(export_all).

%% API
-export([start/1, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% CO node callbacks
-export([index_specification/2,
	 set/3, get/2,
	 write_begin/3, write/3, write_end/3,
	 read_begin/3, read/3,
	 abort/2]).

%% Testing
-ifdef(debug).
-define(dbg(Fmt,As), ct:pal((Fmt), (As))).
-else.
-define(dbg(Fmt,As), ok).
-endif.

-define(SERVER, ?MODULE). 
-define(TEST_IX, 16#2003).
-define(DICT,[{{16#2003, 0}, undef, atomic, undef}, %% To test notify after central set
	      {{16#6033, 0}, ?VISIBLE_STRING, atomic, "Mine"},
	      {{16#6034, 0}, ?VISIBLE_STRING, streamed, "Long string"},
	      {{16#6035, 0}, ?VISIBLE_STRING, {atomic, ?MODULE}, "Mine2"},
	      {{16#6036, 0}, ?VISIBLE_STRING, {streamed, ?MODULE}, "Long string2"},
	      {{16#6037, 0}, ?VISIBLE_STRING, streamed, 
	       "Indefinite string"},
	      {{16#7033, 0}, ?INTEGER, atomic, 7},
	      {{16#7333, 2}, ?INTEGER, atomic, 0},
	      {{16#7334, 0}, ?INTEGER, atomic, 0}, %% To test timeout
	      {{16#6000, 0}, undef, atomic, undef}]). %% To test notify of mpdo

-record(loop_data,
	{
	  state,
	  co_node,
	  dict,
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
%% @spec start(CoSerial) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%%
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start(CoSerial) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [CoSerial], []).

%%--------------------------------------------------------------------
%% @spec stop() -> ok | {error, Error}
%% @doc
%%
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
    gen_server:call(?MODULE, stop).

loop_data() ->
    gen_server:call(?MODULE, loop_data).

dict() ->
    gen_server:call(?MODULE, dict).

%% transfer_mode == {atomic, Module}
set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg("~p: set ~.16B:~.8B to ~p\n",[?MODULE, Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).
get(Pid, {Index, SubInd}) ->
    ?dbg("~p: get ~.16B:~.8B\n",[?MODULE, Index, SubInd]),
    case gen_server:call(Pid, {get, {Index, SubInd}}) of
	{ok, _Type, Value} -> {ok, Value};
	Other -> Other
    end.

%% transfer_mode = {streamed, Module}
write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("~p: write_begin ~.16B:~.8B, ref = ~p\n",[?MODULE, Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).
write(Pid, Ref, Data) ->
    ?dbg("~p: write ref = ~p, data = ~p\n",[?MODULE, Ref, Data]),
    gen_server:cast(Pid, {write, Ref, Data}).
write_end(Pid, Ref, N) ->
    ?dbg("~p: write_end ref = ~p, n = ~p\n",[?MODULE, Ref, N]),
    gen_server:call(Pid, {write_end, Ref, N}).

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("~p: read_begin ~.16B:~.8B, ref = ~p\n",[?MODULE, Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
read(Pid, Bytes, Ref) ->
    ?dbg("~p: read ref = ~p, \n",[?MODULE, Ref]),
    gen_server:call(Pid, {read, Bytes, Ref}).

abort(Pid, Ref) ->
    ?dbg("~p: abort ref = ~p\n",[?MODULE, Ref]),
    gen_server:call(Pid, {abort, Ref}).
    
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
init([CoSerial]) ->
    Dict = ets:new(my_dict, [public, ordered_set]),
    {ok, _DictRef} = co_node:attach(CoSerial),
    load_dict(CoSerial, Dict),
    {ok, #loop_data {state=init, co_node = CoSerial, dict=Dict}}.

load_dict(CoSerial, Dict) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Transfer, _Value} = Entry) ->
			  ets:insert(Dict, Entry),
			  case Index of
			      16#6000 ->			      
				  co_node:subscribe(CoSerial, Index);
			      16#2003 ->			      
				  co_node:subscribe(CoSerial, Index);
			      _Other ->
				  co_node:reserve(CoSerial, Index, ?MODULE)
			  end
		  end, ?DICT).

%%--------------------------------------------------------------------
%% @spec handle_call(Request, From, LoopData) ->
%%                                   {reply, Reply, LoopData} |
%%                                   {reply, Reply, LoopData, Timeout} |
%%                                   {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, Reply, LoopData} |
%%                                   {stop, Reason, LoopData}
%%
%% Request = {get, Index, SubIndex} |
%%           {set, Index, SubInd, Value}
%% LoopData = term()
%% Index = integer()
%% SubInd = integer()
%% Value = term()
%%
%% @doc
%% Handling call messages.
%% Required to at least handle get and set requests as specified above.
%% Handling all non call/cast messages.
%% Required to at least handle a notify msg as specified above. <br/>
%% RemoteId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_call({get, {16#7334, _SubInd}}, _From, LoopData) ->
    %% To test timeout
    ?dbg("~p: handle_call: sleeping for 2 secs\n", [?MODULE]), 
    timer:sleep(2000),
    {reply, {ok, 0}, LoopData};
handle_call({get, {Index, SubInd}}, _From, LoopData) ->
    ?dbg("~p: handle_call: get ~.16B:~.8B \n",[?MODULE, Index, SubInd]),
    case ets:lookup(LoopData#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{{Index, SubInd}, _Type, _Transfer, Value}] ->
	    {reply, {ok, Value}, LoopData}
    end;
handle_call({set, {16#7334, _SubInd}, _NewValue}, _From, LoopData) ->
    %% To test timeout
    timer:sleep(2000),
    {reply, ok, LoopData};
handle_call({set, {Index, SubInd}, NewValue}, _From, LoopData) ->
    ?dbg("~p: handle_call: set ~.16B:~.8B to ~p\n",
	 [?MODULE, Index, SubInd, NewValue]),
    handle_set(LoopData, {Index, SubInd}, NewValue);
handle_call({write_begin, {Index, SubInd} = I, Ref}, _From, LoopData) ->
    ?dbg("~p: handle_call: write_begin ~.16B:~.8B, ref = ~p\n",
	 [?MODULE, Index, SubInd, Ref]),
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: handle_call: write_begin error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{I, Type, _Transfer, _OldValue}] ->
	    Store = #store {ref = Ref, index = I, type = Type},
	    {reply, ok, LoopData#loop_data {store = Store}}
    end;
handle_call({write_end, Ref, N}, _From, LoopData) ->
    ?dbg("~p: handle_call: write_end ref = ~p, n = ~p\n",[?MODULE, Ref,N]),
    Store = LoopData#loop_data.store,
    ?dbg("~p: handle_call: write_end data = ~p, type ~p\n",
	 [?MODULE, Store#store.data, Store#store.type]),
    AccData = Store#store.data,
    %% Check if all downloaded bytes should be used
    Data = if N =:= 0 ->
		AccData;
	   true ->
		Size1 = size(AccData) - N,
		<<TruncData:Size1/binary,_/binary>> = AccData,
		TruncData
	   end,
    {NewValue, _} = co_codec:decode(Data, Store#store.type),
    ?dbg("~p: handle_call: write_end decoded data = ~p\n",[?MODULE, NewValue]),
    handle_set(LoopData,Store#store.index, NewValue);
handle_call({read_begin, {16#6037 = Index, SubInd} = I, Ref}, _From, LoopData) ->
    %% To test 'real' streaming
    ?dbg("~p: handle_call: read_begin ~.16B:~.8B, ref = ~p\n",
	 [?MODULE, Index, SubInd, Ref]),
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: handle_call: read_begin error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{I, Type, _Transfer, Value}] ->
	    Data = co_codec:encode(Value, Type),
	    Store = #store {ref = Ref, index = I, type = Type, data = Data},
	    {reply, {ok, Ref, unknown}, LoopData#loop_data {store = Store}}
    end;
handle_call({read_begin, {Index, SubInd} = I, Ref}, _From, LoopData) ->
    ?dbg("~p: handle_call: read_begin ~.16B:~.8B, ref = ~p\n",
	 [?MODULE, Index, SubInd, Ref]),
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: handle_call: read_begin error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{I, Type, _Transfer, Value}] ->
	    Data = co_codec:encode(Value, Type),
	    Size = size(Data),
	    Store = #store {ref = Ref, index = I, type = Type, data = Data},
	    {reply, {ok, Ref, Size}, LoopData#loop_data {store = Store}}
    end;
handle_call({read, Bytes, Ref}, _From, LoopData) ->
    ?dbg("~p: handle_call: read ref = ~p\n",[?MODULE, Ref]),
    Store = LoopData#loop_data.store,
    Data = Store#store.data,
    Size = size(Data),
    case Size - Bytes of
	RestSize when RestSize > 0 -> 
	    <<DataToSend:Bytes/binary, RestData/binary>> = Data,
	    Store1 = Store#store {data = RestData},
	    {reply, {ok, Ref, DataToSend}, LoopData#loop_data {store = Store1}};
	RestSize when RestSize =< 0 ->
	    Store1 = Store#store {data = (<<>>)},
	    {reply, {ok, Ref, Data}, LoopData#loop_data {store = Store1}}
    end;
handle_call({abort, Ref}, _From, LoopData) ->
    ?dbg("~p: handle_call: abort ref = ~p\n",[?MODULE, Ref]),
    {reply, ok, LoopData};
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p\n", [?MODULE, LoopData]),
    {reply, ok, LoopData};
handle_call(dict, _From, LoopData) ->
    Dict = ets:tab2list(LoopData#loop_data.dict),
    io:format("~p: Dictionary = ~p\n", [?MODULE, Dict]),
    {reply, Dict, LoopData};    
handle_call(stop, _From, LoopData) ->
    ?dbg("~p: handle_call: stop\n",[?MODULE]),
    case whereis(list_to_atom(co_lib:serial_to_string(LoopData#loop_data.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    lists:foreach(
	      fun({{Index, _SubInd}, _Type, _Transfer, _Value}) ->
		      co_node:unsubscribe(LoopData#loop_data.co_node, Index)
	      end, ?DICT),
	    ?dbg("~p: stop: unsubscribed.\n",[?MODULE]),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ?dbg("~p: handle_call: stop detached.\n",[?MODULE]),
    {stop, normal, ok, LoopData};
handle_call(Request, _From, LoopData) ->
    ?dbg("~p: handle_call: bad call ~p.\n",[?MODULE, Request]),
    {reply, {error,bad_call}, LoopData}.

handle_set(LoopData, I, NewValue) ->
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: handle_set: set error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{I, _Type, _Transfer, NewValue}] ->
	    %% No change
	    ?dbg("~p: handle_set: set no change\n", [?MODULE]),
	    {reply, ok, LoopData};
	[{{Index, SubInd}, Type, Transfer, _OldValue}] ->
	    ets:insert(LoopData#loop_data.dict, {I, Type, Transfer, NewValue}),
	    ?dbg("~p: handle_set: set ~.16B:~.8B updated to ~p\n",[?MODULE, Index, SubInd, NewValue]),
	    {reply, ok, LoopData}
    end.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, LoopData) -> {noreply, LoopData} |
%%                                  {noreply, LoopData, Timeout} |
%%                                  {stop, Reason, LoopData}
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
%% transfer_mode == atomic
handle_cast({set, {Index, SubInd} = I, NewValue}, LoopData) ->
    ?dbg("~p: handle_cast: set ~.16B:~.8B to ~p\n",
	 [?MODULE, Index, SubInd, NewValue]),
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: set error = ~.16B\n", [?MODULE, ?ABORT_NO_SUCH_OBJECT]);
	[{I, _Type, _Transfer, NewValue}] ->
	    ok; %% No change
	[{I, Type, _Transfer, _OldValue}] ->
	    ets:insert(LoopData#loop_data.dict, {I, Type, NewValue})
    end,
    {noreply, LoopData};
%% transfer_mode == streamed
handle_cast({write, Ref, Data}, LoopData) ->
    ?dbg("~p: handle_cast: write ref = ~p, data = ~p\n",[?MODULE, Ref, Data]),
    Store = case LoopData#loop_data.store#store.data of
		undefined ->
		    LoopData#loop_data.store#store {data = <<Data/binary>>};
		OldData ->
		    LoopData#loop_data.store#store {data = <<OldData/binary, Data/binary>>}
	    end,
    {noreply, LoopData#loop_data {store = Store}};
handle_cast({object_event, Ix}, LoopData) ->
    ?dbg("~p: handle_cast: My object ~w has changed. ", [?MODULE, Ix]),
    {ok, Val} = co_node:value(LoopData#loop_data.co_node, Ix),
    ?dbg("New value is ~p\n", [Val]),
    {noreply, LoopData};
handle_cast(_Msg, LoopData) ->
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, LoopData) -> {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, LoopData}
%%
%% Info = {notify, RemoteId, Index, SubInd, Value}
%% LoopData = term()
%% RemoteId = integer()
%% Index = integer()
%% SubInd = integer()
%% Value = term()
%%
%% @doc
%% Handling all non call/cast messages.
%% Required to at least handle a notify msg as specified above. <br/>
%% RemoteId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_info({notify, RemoteId, {Index, SubInd}, Value}, LoopData) ->
    ?dbg("~p: handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [?MODULE, RemoteId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    ?dbg("~p: handle_info: Unknown Info ~p\n", [?MODULE, Info]),
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
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, LoopData, _Extra) ->
    %% Note!
    %% If the code change includes a change in which indexes that should be
    %% reserved it is vital to unreserve the indexes no longer used.
    {ok, LoopData}.

%%--------------------------------------------------------------------
%% @spec index_specification(Pid, {Index, SubInd}) -> 
%%      {spec, Spec::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
index_specification(_Pid, {Index, SubInd}) ->
    ?dbg("~p: index_specification ~.16B:~.8B \n",[?MODULE, Index, SubInd]),
    case lists:keyfind({Index, SubInd}, 1, ?DICT) of
	{{Index, SubInd}, Type, Transfer, _Value} ->
	    Spec = #index_spec{index = Index,
				type = Type,
				access = ?ACCESS_RW,
				transfer = Transfer},
	    {spec, Spec};
	false ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
index_specification(Pid, Index) ->
    index_specification(Pid, {Index, 0}).
