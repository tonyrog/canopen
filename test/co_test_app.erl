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
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").

-behaviour(gen_server).
-behaviour(co_app).

-compile(export_all).

%% API
-export([start/2, stop/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% CO node callbacks
-export([get_entry/2,
	 set/3, get/2,
	 write_begin/3, write/4,
	 read_begin/3, read/3,
	 abort/2]).

%% Testing
-ifdef(debug).
-define(dbg(Fmt,As), ct:pal((Fmt), (As))).
-else.
-define(dbg(Fmt,As), ok).
-endif.

-define(WRITE_SIZE, 28).

-record(loop_data,
	{
	  state,
	  co_node,
	  dict,
	  name_table,
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
start(CoSerial, Dict) ->
    gen_server:start_link({local, name(CoSerial)}, 
			  ?MODULE, [CoSerial, Dict], []).

name(Serial) when is_integer(Serial) ->
    list_to_atom("co_test_app" ++ integer_to_list(Serial));
name(Serial) when is_atom(Serial) ->
    %% co_mgr ??
    list_to_atom("co_test_app" ++ atom_to_list(Serial)).
    
	
%%--------------------------------------------------------------------
%% @spec stop() -> ok | {error, Error}
%% @doc
%%
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop(CoSerial) ->
    gen_server:call(name(CoSerial), stop).

loop_data(CoSerial) ->
    gen_server:call(name(CoSerial), loop_data).

dict(CoSerial) ->
    gen_server:call(name(CoSerial), dict).

%% transfer_mode == {atomic, Module}
set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg("~p: set ~.16B:~.8B to ~p\n",[?MODULE, Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).
get(Pid, {Index, SubInd}) ->
    ?dbg("~p: get ~.16B:~.8B\n",[?MODULE, Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).

%% transfer_mode = {streamed, Module}
write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("~p: write_begin ~.16B:~.8B, ref = ~p\n",[?MODULE, Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).
write(Pid, Ref, Data, EodFlag) ->
    ?dbg("~p: write ref = ~p, data = ~p, Eod = ~p\n",[?MODULE, Ref, Data, EodFlag]),
    gen_server:call(Pid, {write, Ref, Data, EodFlag}).

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("~p: read_begin ~.16B:~.8B, ref = ~p\n",[?MODULE, Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
read(Pid, Ref, Bytes) ->
    ?dbg("~p: read ref = ~p, \n",[?MODULE, Ref]),
    gen_server:call(Pid, {read, Ref, Bytes}).

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
init([CoSerial, Dict]) ->
    DictTable = ets:new(dict_table(self()), [public, named_table, ordered_set]),
    NameTable = ets:new(name_to_index, [private, ordered_set]),
    {ok, _NodeId} = co_node:attach(CoSerial),
    load_dict(CoSerial, Dict, DictTable, NameTable),
    {ok, #loop_data {state=init, co_node = CoSerial, dict=DictTable, 
		     name_table=NameTable}}.

dict_table(Pid) ->
    list_to_atom("dict" ++ pid_to_list(Pid)).

load_dict(CoSerial, Dict, DictTable, NameTable) ->
    ?dbg("Dict ~p", [Dict]),
    lists:foreach(fun({Name, 
		       {{Index, _SubInd}, _Type, _Mode, _Value} = Entry}) ->
			  ets:insert(DictTable, Entry),
			  ?dbg("Inserting entry = ~p", [Entry]),
			  ets:insert(NameTable, {Name, Index}),
			  case Name of
			      notify ->			      
				  co_node:subscribe(CoSerial, Index);
			      mpdo ->			      
				  co_node:subscribe(CoSerial, Index);
			      _Other ->
				  co_node:reserve(CoSerial, Index, ?MODULE)
			  end
		  end, Dict).

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
handle_call({get, {Index, SubInd}}, _From, LoopData) ->
    ?dbg("~p: handle_call: get ~.16B:~.8B \n",[?MODULE, Index, SubInd]),

    [{timeout, I}] = ets:lookup(LoopData#loop_data.name_table, timeout),
    case Index of
	I ->
	    %% To test timeout
	    ?dbg("~p: handle_call: sleeping for 2 secs\n", [?MODULE]), 
	    timer:sleep(2000);
	_Other ->
	    do_nothing
    end,

    case ets:lookup(LoopData#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{{Index, SubInd}, _Type, _Transfer, Value}] ->
	    {reply, {ok, Value}, LoopData}
    end;
handle_call({set, {Index, SubInd}, NewValue}, _From, LoopData) ->
     ?dbg("~p: handle_call: set ~.16B:~.8B to ~p\n",
	 [?MODULE, Index, SubInd, NewValue]),

    [{timeout, I}] = ets:lookup(LoopData#loop_data.name_table, timeout),
    case Index of
	I ->
	    %% To test timeout
	    ?dbg("~p: handle_call: sleeping for 2 secs\n", [?MODULE]), 
	    timer:sleep(2000);
	_Other ->
	    do_nothing
    end,
    
    handle_set(LoopData, {Index, SubInd}, NewValue, undefined);
%% transfer_mode == streamed
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
	    {reply, {ok, Ref, ?WRITE_SIZE}, LoopData#loop_data {store = Store}}
    end;
handle_call({write, Ref, Data, Eod}, _From, LoopData) ->
    ?dbg("~p: handle_call: write ref = ~p, data = ~p\n",[?MODULE, Ref, Data]),
    Store = case LoopData#loop_data.store#store.data of
		undefined ->
		    LoopData#loop_data.store#store {data = <<Data/binary>>};
		OldData ->
		    LoopData#loop_data.store#store {data = <<OldData/binary, Data/binary>>}
	    end,
    if Eod ->
	    {NewValue, _} = co_codec:decode(Store#store.data, type(Store#store.type)),
	    ?dbg("~p: handle_call: write decoded data = ~p\n",[?MODULE, NewValue]),
	    handle_set(LoopData,Store#store.index, NewValue, Ref);
       true ->
	    {reply, {ok, Ref}, LoopData#loop_data {store = Store}}
    end;
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
	    Data = co_codec:encode(Value, type(Type)),
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
	    Data = co_codec:encode(Value, type(Type)),
	    Size = size(Data),
	    Store = #store {ref = Ref, index = I, type = Type, data = Data},
	    {reply, {ok, Ref, Size}, LoopData#loop_data {store = Store}}
    end;
handle_call({read, Ref, Bytes}, _From, LoopData) ->
    ?dbg("~p: handle_call: read ref = ~p\n",[?MODULE, Ref]),
    Store = LoopData#loop_data.store,
    Data = Store#store.data,
    Size = size(Data),
    case Size - Bytes of
	RestSize when RestSize > 0 -> 
	    <<DataToSend:Bytes/binary, RestData/binary>> = Data,
	    Store1 = Store#store {data = RestData},
	    {reply, {ok, Ref, DataToSend, false}, LoopData#loop_data {store = Store1}};
	RestSize when RestSize < 0 ->
	    Store1 = Store#store {data = (<<>>)},
	    {reply, {ok, Ref, Data, true}, LoopData#loop_data {store = Store1}}
    end;
handle_call({abort, Ref}, _From, LoopData) ->
    ?dbg("~p: handle_call: abort ref = ~p\n",[?MODULE, Ref]),
    {reply, ok, LoopData};
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p\n", [?MODULE, LoopData]),
    {reply, ok, LoopData};
handle_call(dict, _From, LoopData) ->
    Dict = ets:tab2list(LoopData#loop_data.dict),
%%    io:format("~p: Dictionary = ~p\n", [?MODULE, Dict]),
    {reply, Dict, LoopData};    
handle_call(stop, _From, LoopData) ->
    ?dbg("~p: handle_call: stop\n",[?MODULE]),
    CoNode = case LoopData#loop_data.co_node of
		 co_mgr -> co_mgr;
		 Serial ->
		     list_to_atom(co_lib:serial_to_string(Serial))
	     end,
    case whereis(CoNode) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    Name2Index = ets:tab2list(LoopData#loop_data.name_table),
	    lists:foreach(
	      fun({{Index, _SubInd}, _Type, _Transfer, _Value}) ->
		      case lists:keyfind(Index, 2, Name2Index) of
			  {notify, Ix} ->
			      co_node:unsubscribe(LoopData#loop_data.co_node, Ix);
			  {mpdo, Ix} ->
			      co_node:unsubscribe(LoopData#loop_data.co_node, Ix);
			  {_Any, Ix} ->
			      co_node:unreserve(LoopData#loop_data.co_node, Ix)
		      end
	      end, ets:tab2list(LoopData#loop_data.dict)),
	    ?dbg("~p: stop: unsubscribed.\n",[?MODULE]),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ?dbg("~p: handle_call: stop detached.\n",[?MODULE]),
    {stop, normal, ok, LoopData};
handle_call(Request, _From, LoopData) ->
    ?dbg("~p: handle_call: bad call ~p.\n",[?MODULE, Request]),
    {reply, {error,bad_call}, LoopData}.

handle_set(LoopData, I, NewValue, Ref) ->
    Reply = case Ref of
		undefined -> ok;
		R -> {ok, R}
	    end,
    case ets:lookup(LoopData#loop_data.dict, I) of
	[] ->
	    ?dbg("~p: handle_set: set error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{I, _Type, _Transfer, NewValue}] ->
	    %% No change
	    ?dbg("~p: handle_set: set no change\n", [?MODULE]),
	    {reply, Reply, LoopData};
	[{{Index, SubInd}, Type, Transfer, _OldValue}] ->
	    ets:insert(LoopData#loop_data.dict, {I, Type, Transfer, NewValue}),
	    ?dbg("~p: handle_set: set ~.16B:~.8B updated to ~p\n",[?MODULE, Index, SubInd, NewValue]),
	    {reply, Reply, LoopData}
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
handle_cast({object_changed, Ix}, LoopData) ->
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
%% @spec get_entry(Pid, {Index, SubInd}) -> {entry, Entry::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
get_entry(Pid, {Index, 255}) ->
    ?dbg("~p: get_entry type ~.16B \n",[?MODULE, Index]),
    case ets:lookup(dict_table(Pid), {Index, 0}) of
	[{I, Type, _Transfer}] ->
	    Value = (type(Type) bsl 8) bor ?OBJECT_VAR, %% VAR/ARRAY .. fixme
	    Entry = #app_entry{index = I,
			       type = ?UNSIGNED32,
			       access = ?ACCESS_RO,
			       transfer = {value, Value}},
	    {entry,Entry};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
get_entry(Pid, {Index, SubInd} = I) ->
    ?dbg("~p: get_entry ~.16B:~.8B \n",[?MODULE, Index, SubInd]),
    case ets:lookup(dict_table(Pid), I) of
	[{I, Type, Transfer, _Value}] ->
	    Entry = #app_entry{index = I,
			       type = type(Type),
			       access = ?ACCESS_RW,
			       transfer = Transfer},
	    {entry, Entry};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
get_entry(Pid, Index) when is_integer(Index) ->
    get_entry(Pid, {Index, 0}).


type(string) -> ?VISIBLE_STRING;
type(int) -> ?INTEGER;
type(_) -> unknown.
     
