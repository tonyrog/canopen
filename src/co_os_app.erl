%%-------------------------------------------------------------------
%% @author Malotte W Lonne <malotte@malotte.net>
%% @copyright (C) 2011, Tony Rogvall
%% @doc
%%    OS command CANOpen application.
%% 
%% @end
%%===================================================================

-module(co_os_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_app).
-behaviour(co_stream_app).

%% API
-export([start/1, stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% co_app and co_stream_app callbacks
-export([get_entry/2,
	 set/3, get/2,
	 write_begin/3, write/4,
	 read_begin/3, read/3,
	 abort/2]).

%% Test
-export([loop_data/0,
	 debug/1]).

-define(NAME, os_command_app).
-define(WRITE_SIZE, 56).    %% Size of data chunks when receiving

-record(loop_data,
	{
	  state,
	  command = "",     %% Subindex 1
	  status = 0,       %% Subindex 2
	  reply ="",        %% Subindex 3
	  co_node,          %% Name of co_node
	  ref,              %% Reference for communication with session
	  read_buf = <<>>   %% Tmp buffer when uploading reply
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
    gen_server:start_link({local, ?NAME}, ?MODULE, [CoSerial],[]).
	
%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | 
		{error, Error::atom()}.

stop() ->
    gen_server:call(?NAME, stop).

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
-spec get_entry(Pid::pid(), {Index::integer(), SubInd::integer()}) -> 
		       {entry, Entry::record()} |
		       {error, Reason::atom()}.

get_entry(_Pid, {?IX_OS_COMMAND = Index, 255} = I) ->
    ?dbg(?NAME," get_entry type ~.16B \n",[Index]),
    Value = (?UNSIGNED8 bsl 8) bor ?OBJECT_VAR, %% VAR/ARRAY .. fixme
    reply_entry(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
get_entry(_Pid, {?IX_OS_COMMAND, 0} = I) ->
    reply_entry(I, ?UNSIGNED8, ?ACCESS_RO, atomic);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_COMMAND} = I) ->
    reply_entry(I, ?OCTET_STRING, ?ACCESS_RW, streamed);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_STATUS} = I) ->
    reply_entry(I, ?UNSIGNED8, ?ACCESS_RO, atomic);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_REPLY} = I) ->
    reply_entry(I, ?OCTET_STRING, ?ACCESS_RO, streamed);
get_entry(Pid, Index) when is_integer(Index) ->
    get_entry(Pid, {Index, 0});
get_entry(_Pid, {?IX_OS_COMMAND, SubInd})  ->
    ?dbg(?NAME," get_entry Unknown subindex ~.8B \n",[SubInd]),
    {error, ?abort_no_such_subindex};
get_entry(_Pid, {Index, SubInd})  ->
    ?dbg(?NAME," get_entry ~.16B:~.8B \n",[Index, SubInd]),
    {error, ?abort_no_such_object}.

reply_entry({Index, SubInd} = I, Type, Access, Mode) ->
    ?dbg(?NAME," reply_entry ~.16B:~.8B, type = ~p, access = ~p, mode = ~p\n",
	 [Index, SubInd, Type, Access, Mode]),
    Entry = #app_entry{index = I,
		       type = Type,
		       access = Access,
		       transfer = Mode},
    {entry, Entry}.

%%--------------------------------------------------------------------
%% @doc
%% Callback functions for transfer_mode == {atomic, Module}
%% @end
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Sets {Index, SubInd} to NewValue.
%% @end
%%--------------------------------------------------------------------
-spec set(Pid::pid(), {Index::integer(), SubInd::integer()}, NewValue::term()) ->
		 ok |
		 {error, Reason::atom()}.

set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg(?NAME," set ~.16B:~.8B to ~p\n",[Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).

%%--------------------------------------------------------------------
%% @doc
%% Gets Value for {Index, SubInd}.
%% @end
%%--------------------------------------------------------------------
-spec get(Pid::pid(), {Index::integer(), SubInd::integer()}) ->
		 {ok, Value::term()} |
		 {error, Reason::atom()}.

get(Pid, {Index, SubInd}) ->
    ?dbg(?NAME," get ~.16B:~.8B\n",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).

%%--------------------------------------------------------------------
%% @doc
%% Callback functions for transfer_mode = {streamed, Module}
%% @end
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Intializes download of data. Returns max size of data chunks.
%% @end
%%--------------------------------------------------------------------
-spec write_begin(Pid::pid(), {Index::integer(), SubInd::integer()}, 
		  Ref::reference()) ->
		 {ok, Ref::reference(), WriteSize::integer()} |
		 {error, Reason::atom()}.

write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg(?NAME," write_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Downloads data.
%% @end
%%--------------------------------------------------------------------
-spec write(Pid::pid(), Ref::reference(), Data::binary(), EodFlag::boolean()) ->
		 {ok, Ref::reference()} |
		 {error, Reason::atom()}.
write(Pid, Ref, Data, EodFlag) ->
    ?dbg(?NAME," write ref = ~p, data = ~p, Eod = ~p\n",[Ref, Data, EodFlag]),
    gen_server:call(Pid, {write, Ref, Data, EodFlag}).

%%--------------------------------------------------------------------
%% @doc
%% Intializes upload of data. Returns size of data.
%% @end
%%--------------------------------------------------------------------
-spec read_begin(Pid::pid(), {Index::integer(), SubInd::integer()}, 
		  Ref::reference()) ->
		 {ok, Ref::reference(), Size::integer()} |
		 {error, Reason::atom()}.

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg(?NAME," read_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
%%--------------------------------------------------------------------
%% @doc
%% Uploads data.
%% @end
%%--------------------------------------------------------------------
-spec read(Pid::pid(), Ref::reference(), Bytes::integer()) ->
		 {ok, Ref::reference(), Data::binary(), EodFlag::boolean()} |
		 {error, Reason::atom()}.
read(Pid, Ref, Bytes) ->
    ?dbg(?NAME," read ref = ~p, \n",[Ref]),
    gen_server:call(Pid, {read, Bytes, Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Aborts stream transaction.
%% @end
%%--------------------------------------------------------------------
-spec abort(Pid::pid(), Ref::reference()) ->
		   ok |
		   {error, Reason::atom()}.
abort(Pid, Ref) ->
    ?dbg(?NAME," abort ref = ~p\n",[Ref]),
    gen_server:call(Pid, {abort, Ref}).
    
%% Test functions
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?NAME, {debug, TrueOrFalse}).

loop_data() ->
    gen_server:call(?NAME, loop_data).



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
    {ok, _NodeId} = co_node:attach(CoSerial),
    co_node:reserve(CoSerial, ?IX_OS_COMMAND, ?MODULE),
    {ok, #loop_data {state=init, co_node = CoSerial}}.

%%--------------------------------------------------------------------
%% @spec handle_call(Request, From, LoopData) ->
%%                                   {reply, Reply, LoopData} |
%%                                   {reply, Reply, LoopData, Timeout} |
%%                                   {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, Reply, LoopData} |
%%                                   {stop, Reason, LoopData}
%%
%% Request = {get, {Index, SubIndex}} |
%%           {set, {Index, SubInd}, Value}
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
handle_call({set, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Command}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: set command = ~p\n",[Command]),
    handle_command(LoopData#loop_data {command = Command});
handle_call({set, {?IX_OS_COMMAND, SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: set unknown subindex ~.8B \n",[SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({set, {Index, SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: set ~.16B:~.8B \n",[Index, SubInd]),    
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_COMMAND}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get command = ~p\n",[LoopData#loop_data.command]),    
    {reply, {ok, LoopData#loop_data.command}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_STATUS}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get status = ~p\n",[LoopData#loop_data.status]),    
    {reply, {ok, LoopData#loop_data.status}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_REPLY}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get reply = ~p\n",[LoopData#loop_data.reply]),    
    {reply, {ok, LoopData#loop_data.reply}, LoopData};
handle_call({get, {?IX_OS_COMMAND, SubInd}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get unknown subindex ~.8B \n",[SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({get, {Index, SubInd}}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: get ~.16B:~.8B \n",[Index, SubInd]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({write_begin, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: write_begin command, Ref = ~p\n",[Ref]),
    {reply, {ok, Ref, ?WRITE_SIZE}, LoopData#loop_data {ref = Ref}}; 
handle_call({write_begin, {?IX_OS_COMMAND, SubInd}, _Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: write_begin unknown subindex ~.8B \n",[SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({write_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: write_begin unknown Index ~.16B:~.8B, ref = ~p\n",
	 [Index, SubInd, Ref]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({write, Ref, Data, Eod}, _From, LoopData) ->
    ?dbg(?NAME,"handle_call: write ref = ~p, data = ~p, eod = ~p\n",
	 [Ref, Data, Eod]),
    if Ref =/= LoopData#loop_data.ref ->
	    {reply, {error, ?abort_internal_error}, LoopData};
       true ->
	    handle_write(Data, Eod, LoopData#loop_data {state = storing})
    end;
handle_call({read_begin, {?IX_OS_COMMAND, ?SI_OS_REPLY}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: read_begin ref = ~p\n", [Ref]),  
    Data = co_codec:encode(LoopData#loop_data.reply, ?OCTET_STRING),
    {reply, {ok, Ref, size(Data)}, LoopData#loop_data {ref = Ref, read_buf = Data}};
handle_call({read_begin, {?IX_OS_COMMAND, SubInd}, _Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: read_begin unknown subindex ~.8B \n",[SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({read_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: read_begin unknown Index ~.16B:~.8B, ref = ~p\n",
	 [Index, SubInd, Ref]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({read, Ref, Bytes}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: read ref = ~p\n", [Ref]),
    if Ref =/= LoopData#loop_data.ref ->
	    {reply, {error, ?abort_internal_error}, LoopData};
       true ->
	    handle_read(Bytes, LoopData#loop_data {state = reading})
    end;
handle_call({abort, Ref}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: abort ref = ~p\n", [Ref]),
     if Ref =/= LoopData#loop_data.ref ->
	     {reply, {error, ?abort_internal_error}, LoopData};
	true ->
	     {reply, ok, LoopData#loop_data {read_buf = (<<>>), state = init, 
					     ref = undefined,
					     command = "", status = 0, reply = ""}}
    end;
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p\n", [?MODULE,LoopData]),
    {reply, ok, LoopData};
handle_call({debug, TrueOrFalse}, _From, LoopData) ->
    OldDebug = get(dbg),
    io:format("handle_call: debug is = ~p, set it to ~p\n",[OldDebug,TrueOrFalse]),
    put(dbg, TrueOrFalse),
    NewDebug = get(dbg),
    io:format("handle_call: debug is = ~p\n",[NewDebug]),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ?dbg(?NAME," handle_call: stop\n",[]),    
    handle_stop(LoopData);
handle_call(Request, _From, LoopData) ->
    ?dbg(?NAME," handle_call: bad call ~p.\n",[Request]),
    {reply, {error,bad_call}, LoopData}.

handle_write(Data, Eod, LoopData=#loop_data {command = undefined}) ->
    handle_write_i(<<Data/binary>>, Eod, LoopData);
handle_write(Data, Eod, LoopData=#loop_data {command = S}) when is_list(S) ->
    %% Old command, remove ??
    handle_write_i(<<Data/binary>>, Eod, LoopData);
handle_write(Data, Eod, LoopData=#loop_data {command = OldC}) when is_binary(OldC) ->
    handle_write_i(<<OldC/binary, Data/binary>>, Eod, LoopData).

handle_write_i(NewC, true, LoopData) ->
    handle_command(LoopData#loop_data {command = NewC});
handle_write_i(NewC, false, LoopData=#loop_data {ref = Ref}) ->
    {reply, {ok, Ref}, LoopData#loop_data {command = NewC}}.


handle_command(LoopData=#loop_data {command = Command}) when is_binary(Command) ->
    ?dbg(?NAME," handle_command: converting command ~p.\n",[Command]),
    handle_command(LoopData#loop_data {command = binary_to_list(Command)});
handle_command(LoopData=#loop_data {command = Command}) when is_list(Command) ->
    ?dbg(?NAME," handle_command: command = ~p.\n",[Command]),
    try os:cmd(Command) of
	{error, E} ->

	    ?dbg(?NAME," handle_command: execute Error = ~p\n",[E]),    
	    {reply, ok, LoopData#loop_data {state = executed,
					    status = 3, 
					    reply = E}};
	[] ->
	    ?dbg(?NAME," handle_command: execute no result\n",[]),    
	    {reply, ok, LoopData#loop_data {state = executed,
					    status = 0, 
					    reply = ""}};
	Result ->
	    ?dbg(?NAME," handle_command: execute Result = ~p\n",[Result]),    
	    {reply, ok, LoopData#loop_data {state = executed,
					    status = 1, 
					    reply = Result}}
    catch
	error:Reason ->
	    ?dbg(?NAME," handle_command: execute catch Reason = ~p\n",[Reason]),    
	    {reply, ok, LoopData#loop_data {state = executed,
					    status = 3, 
					    reply = "Internal Error"}}
    end.

handle_read(Bytes, LoopData=#loop_data {ref = Ref, read_buf = Data}) ->
    Size = size(Data),
    case Size - Bytes of
	RestSize when RestSize > 0 -> 
	    <<DataToSend:Bytes/binary, RestData/binary>> = Data,
	    {reply, {ok, Ref, DataToSend, false}, 
	     LoopData#loop_data {read_buf = RestData}};
	RestSize when RestSize < 0 ->
	    {reply, {ok, Ref, Data, true}, LoopData#loop_data {read_buf = (<<>>)}}
    end.
    

handle_stop(LoopData) ->
    case whereis(list_to_atom(co_lib:serial_to_string(LoopData#loop_data.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    co_node:unreserve(LoopData#loop_data.co_node, ?IX_OS_COMMAND),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ?dbg(?NAME," handle_stop: detached.\n",[]),
    {stop, normal, ok, LoopData}.


%%--------------------------------------------------------------------
%% @spec handle_cast(Msg, LoopData) -> {noreply, LoopData} |
%%                                     {noreply, LoopData, Timeout} |
%%                                     {stop, Reason, LoopData}
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, LoopData) ->
    ?dbg(?NAME," handle_cast: Message = ~p. ", [Msg]),
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
    ?dbg(?NAME," handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    ?dbg(?NAME," handle_info: Unknown Info ~p\n", [Info]),
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

     
