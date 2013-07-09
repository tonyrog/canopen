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
%%-----------------------------------------------------------------------------
%% @author Malotte W Lönne <malotte@malotte.net>
%% @copyright (C) 2013, Tony Rogvall
%% @doc
%%    OS command CANopen application.<br/>
%%    Implements index 16#1023 (os_command).<br/>
%%    os_command makes it possible to send an os command 
%%    to a CANOpen node and have it executed there. <br/>
%%
%% File: co_os_app.erl<br/>
%% Created: December 2011 by Malotte W Lönne
%% @end
%%-----------------------------------------------------------------------------
-module(co_os_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").
-include("co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_app).
-behaviour(co_stream_app).

%% API
-export([start/1, 
	 start_link/1, 
	 stop/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% co_app and co_stream_app callbacks
-export([index_specification/2,
	 set/3, 
	 get/2,
	 write_begin/3, 
	 write/4,
	 read_begin/3, 
	 read/3,
	 abort/3]).

%% Execution process
-export([execute_command/2]).

%% Test
-export([loop_data/1,
	 debug/2]).

-define(NAME, os_cmd).
-define(WRITE_SIZE, 56).    %% Size of data chunks when receiving

-record(loop_data,
	{
	  state            ::atom(),
	  command = ""     ::string() | binary(),   %% Subindex 1
	  status = 0       ::integer(),  %% Subindex 2
	  reply =""        ::string(),   %% Subindex 3
	  exec_pid         ::pid(),      %% Pid of process executing command
	  co_node          ::node_identity(),  %% Identity of co_node
	  ref              ::reference(),%% Reference for communication with session
	  read_buf = (<<>>)::binary()    %% Tmp buffer when uploading reply
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
    gen_server:start_link({local,  name(CoNode)}, ?MODULE, CoNode,[]).
	
%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop(CoNode::node_identity()) -> ok | 
		{error, Error::atom()}.

stop(Pid) when is_pid(Pid)->
    gen_server:call(Pid, stop);
stop(CoNode) ->
    case whereis(name(CoNode)) of
	undefined -> do_nothing;
	Pid -> gen_server:call(Pid, stop)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start(CoNode::node_identity()) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::atom()}.

start(CoNode) ->
    gen_server:start({local,  name(CoNode)}, ?MODULE, CoNode,[]).
	
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
		       {spec, Spec::#index_spec{}} |
		       {error, Reason::atom()}.

index_specification(_Pid, {?IX_OS_COMMAND = _Index, 255} = I) ->
    ?dbg("index_specification: type ~.16B \n",[_Index]),
    Value = ((?COMMAND_PAR band 16#ff) bsl 8) bor (?OBJECT_RECORD band 16#ff),
    reply_specification(I, ?UNSIGNED32, ?ACCESS_RO, {value, Value});
index_specification(_Pid, {?IX_OS_COMMAND, 0} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, {value, 3});
index_specification(_Pid, {?IX_OS_COMMAND, ?SI_OS_COMMAND} = I) ->
    reply_specification(I, ?OCTET_STRING, ?ACCESS_RW, streamed);
index_specification(_Pid, {?IX_OS_COMMAND, ?SI_OS_STATUS} = I) ->
    reply_specification(I, ?UNSIGNED8, ?ACCESS_RO, atomic);
index_specification(_Pid, {?IX_OS_COMMAND, ?SI_OS_REPLY} = I) ->
    reply_specification(I, ?OCTET_STRING, ?ACCESS_RO, streamed);
index_specification(Pid, Index) when is_integer(Index) ->
    index_specification(Pid, {Index, 0});
index_specification(_Pid, {?IX_OS_COMMAND, _SubInd})  ->
    ?dbg("index_specification: Unknown subindex ~.8B \n",[_SubInd]),
    {error, ?abort_no_such_subindex};
index_specification(_Pid, {_Index, _SubInd})  ->
    ?dbg("index_specification: Unknown index~.16B:~.8B \n",
	 [_Index, _SubInd]),
    {error, ?abort_no_such_object}.

reply_specification({_Index, _SubInd} = I, Type, Access, Mode) ->
    ?dbg("reply_specification: ~.16B:~.8B, type = ~p, access = ~p, mode = ~p\n",
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

set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg("set ~.16B:~.8B to ~p\n",[Index, SubInd, NewValue]),
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
    ?dbg("get ~.16B:~.8B\n",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).

%%--------------------------------------------------------------------
%% Callback functions for transfer_mode = {streamed, Module}
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Intializes download of data. Returns max size of data chunks.<br/>
%% Used for transfer_mode =  {streamed, Module}
%% @end
%%--------------------------------------------------------------------
-spec write_begin(Pid::pid(), {Index::integer(), SubInd::integer()}, 
		  Ref::reference()) ->
		 {ok, Ref::reference(), WriteSize::integer()} |
		 {error, Reason::atom()}.

write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("write_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Downloads data.<br/>
%% Used for transfer_mode =  {streamed, Module}
%% @end
%%--------------------------------------------------------------------
-spec write(Pid::pid(), Ref::reference(), Data::binary(), EodFlag::boolean()) ->
		 {ok, Ref::reference()} |
		 {error, Reason::atom()}.
write(Pid, Ref, Data, EodFlag) ->
    ?dbg("write ref = ~p, data = ~p, Eod = ~p\n",[Ref, Data, EodFlag]),
    gen_server:call(Pid, {write, Ref, Data, EodFlag}).

%%--------------------------------------------------------------------
%% @doc
%% Intializes upload of data. Returns size of data.<br/>
%% Used for transfer_mode =  {streamed, Module}
%% @end
%%--------------------------------------------------------------------
-spec read_begin(Pid::pid(), {Index::integer(), SubInd::integer()}, 
		  Ref::reference()) ->
		 {ok, Ref::reference(), Size::integer()} |
		 {error, Reason::atom()}.

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg("read_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
%%--------------------------------------------------------------------
%% @doc
%% Uploads data.<br/>
%% Used for transfer_mode =  {streamed, Module}
%% @end
%%--------------------------------------------------------------------
-spec read(Pid::pid(), Ref::reference(), Bytes::integer()) ->
		 {ok, Ref::reference(), Data::binary(), EodFlag::boolean()} |
		 {error, Reason::atom()}.
read(Pid, Ref, Bytes) ->
    ?dbg("read ref = ~p, \n",[Ref]),
    gen_server:call(Pid, {read, Bytes, Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Aborts stream transaction.<br/>
%% Used for transfer_mode =  {streamed, Module}
%% @end
%%--------------------------------------------------------------------
-spec abort(Pid::pid(), Ref::reference(), Reason::integer()) ->
		   ok |
		   {error, Reason::atom()}.
abort(Pid, Ref, Reason) ->
    ?dbg("abort ref = ~p\n",[Ref]),
    gen_server:cast(Pid, {abort, Ref, Reason}).
    
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
-spec init(CoNode::node_identity()) -> {ok, LoopData::#loop_data{}}.

init(CoNode) ->
    process_flag(trap_exit, true),
    CoName = {name, _Name} = co_api:get_option(CoNode, name),
    {ok, _Dict} = co_api:attach(CoNode),
    co_api:reserve(CoNode, ?IX_OS_COMMAND, ?MODULE),
    {ok, #loop_data {state=init, co_node=CoName}}.

%%--------------------------------------------------------------------
%% @doc
%% Handling call messages.
%% Used for transfer mode atomic (set, get) and streamed 
%% (write_begin, write, read_begin, read).
%%
%% Index = Index in Object Dictionary <br/>
%% SubInd =  SubIndex in Object Dictionary  <br/>
%% Value =  Any value the node chooses to send.
%% Ref - Reference in communication with the CANopen node.
%%
%% For description of requests compare with the correspondig functions:
%% @see set/3  
%% @see get/2 
%% @see write_begin/3
%% @see write/4
%% @see read_begin/3
%% @see read/3.
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{get, {Index::integer(), SubIndex::integer()}} |
	{set, {Index::integer(), SubInd::integer()}, Value::term()} |
	{write_begin, {Index::integer(), SubInd::integer()}, Ref::reference()} |
	{write, Ref::reference(), Data::binary(), Eod::boolean()} |
	{read_begin, {Index::integer(), SubInd::integer()}, Ref::reference()} |
	{read, Ref::reference(), Bytes::integer()} |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), term()}, LoopData::#loop_data{}) ->
			 {reply, Reply::term(), LoopData::#loop_data{}} |
			 {noreply, LoopData::#loop_data{}} |
			 {stop, Reason::atom(), Reply::term(), LoopData::#loop_data{}}.

handle_call({set, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Command}, _From, LoopData) ->
    ?dbg("handle_call: set command = ~p\n",[Command]),
    handle_command(LoopData#loop_data {command = Command});
handle_call({set, {?IX_OS_COMMAND, _SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg("handle_call: set unknown subindex ~.8B \n",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({set, {_Index, _SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg("handle_call: set ~.16B:~.8B \n",[_Index, _SubInd]),    
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({get, {?IX_OS_COMMAND, 0}}, _From, LoopData) ->
    ?dbg("handle_call: get object size = 3\n",[]),    
    {reply, {ok, 3}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_COMMAND}}, _From, LoopData) ->
    ?dbg("handle_call: get command = ~p\n",[LoopData#loop_data.command]),    
    {reply, {ok, LoopData#loop_data.command}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_STATUS}}, _From, LoopData) ->
    ?dbg("handle_call: get status = ~p\n",[LoopData#loop_data.status]),    
    {reply, {ok, LoopData#loop_data.status}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_REPLY}}, _From, LoopData) ->
    ?dbg("handle_call: get reply = ~p\n",[LoopData#loop_data.reply]),    
    {reply, {ok, LoopData#loop_data.reply}, LoopData};
handle_call({get, {?IX_OS_COMMAND, _SubInd}}, _From, LoopData) ->
    ?dbg("handle_call: get unknown subindex ~.8B \n",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({get, {_Index, _SubInd}}, _From, LoopData) ->
    ?dbg("handle_call: get ~.16B:~.8B \n",[_Index, _SubInd]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({write_begin, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Ref}, _From, LoopData) ->
    ?dbg("handle_call: write_begin command, Ref = ~p\n",[Ref]),
    {reply, {ok, Ref, ?WRITE_SIZE}, LoopData#loop_data {ref = Ref}}; 
handle_call({write_begin, {?IX_OS_COMMAND, _SubInd}, _Ref}, _From, LoopData) ->
    ?dbg("handle_call: write_begin unknown subindex ~.8B \n",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({write_begin, {_Index, _SubInd}, _Ref}, _From, LoopData) ->
    ?dbg("handle_call: write_begin unknown Index ~.16B:~.8B, ref = ~p\n",
	 [_Index, _SubInd, _Ref]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({write, Ref, Data, Eod}, _From, LoopData) ->
    ?dbg("handle_call: write ref = ~p, data = ~p, eod = ~p\n",
	 [Ref, Data, Eod]),
    if Ref =/= LoopData#loop_data.ref ->
	    {reply, {error, ?abort_internal_error}, LoopData};
       true ->
	    handle_write(Data, Eod, LoopData#loop_data {state = storing})
    end;
handle_call({read_begin, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Ref}, _From, LoopData) ->
    ?dbg("handle_call: read_begin ref = ~p\n", [Ref]),  
    Data = co_codec:encode(LoopData#loop_data.command, ?OCTET_STRING),
    {reply, {ok, Ref, size(Data)}, LoopData#loop_data {ref = Ref, read_buf = Data}};
handle_call({read_begin, {?IX_OS_COMMAND, ?SI_OS_REPLY}, Ref}, _From, LoopData) ->
    ?dbg("handle_call: read_begin ref = ~p\n", [Ref]),  
    Data = co_codec:encode(LoopData#loop_data.reply, ?OCTET_STRING),
    {reply, {ok, Ref, size(Data)}, LoopData#loop_data {ref = Ref, read_buf = Data}};
handle_call({read_begin, {?IX_OS_COMMAND, _SubInd}, _Ref}, _From, LoopData) ->
    ?dbg("handle_call: read_begin unknown subindex ~.8B \n",[_SubInd]),    
    {reply, {error, ?abort_no_such_subindex}, LoopData};
handle_call({read_begin, {_Index, _SubInd}, _Ref}, _From, LoopData) ->
    ?dbg("handle_call: read_begin unknown Index ~.16B:~.8B, ref = ~p\n",
	 [_Index, _SubInd, _Ref]),
    {reply, {error, ?abort_no_such_object}, LoopData};
handle_call({read, Ref, Bytes}, _From, LoopData) ->
    ?dbg("handle_call: read ref = ~p\n", [Ref]),
    if Ref =/= LoopData#loop_data.ref ->
	    {reply, {error, ?abort_internal_error}, LoopData};
       true ->
	    handle_read(Bytes, LoopData#loop_data {state = reading})
    end;
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p\n", [?MODULE,LoopData]),
    {reply, ok, LoopData};
handle_call({debug, TrueOrFalse}, _From, LoopData) ->
    co_lib:debug(TrueOrFalse),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ?dbg("handle_call: stop\n",[]),    
    handle_stop(LoopData);
handle_call(_Request, _From, LoopData) ->
    ?dbg("handle_call: bad call ~p.\n",[_Request]),
    {reply, {error,bad_call}, LoopData}.

handle_write(Data, Eod, LoopData=#loop_data {command = ""}) ->
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

handle_command(LoopData=#loop_data {command = Command, ref = Ref}) 
  when is_list(Command) ->
    ?dbg("handle_command: command = ~p.\n",[Command]),
    Pid = proc_lib:spawn_link(?MODULE, execute_command, [Command, self()]),
    ?dbg("handle_command: spawned = ~p.\n",[Pid]),
    {reply, {ok, Ref}, LoopData#loop_data {state = executing,
				    status = 255, 
				    reply = "",
				    exec_pid = Pid}};
handle_command(LoopData=#loop_data {command = Command}) ->
    ?dbg("handle_command: convert iolist = ~p.\n",[Command]),
    try iolist_size(Command) of
	_Size -> 
	    handle_command(LoopData#loop_data 
			   {command = binary_to_list(iolist_to_binary(Command))})
    catch
	{error, _Reason} -> 
	    {reply, {error, ?abort_local_data_error}, LoopData}
    end.

%% @private
execute_command(Command, Starter) ->
    Res = execute_command(Command),
    ?dbg("execute_command: result = ~p.\n",[Res]),
    Starter ! Res,
    exit(normal).

execute_command(Command) ->
    try os:cmd(Command) of
	[] ->
	    ?dbg("handle_command: execute no result\n",[]),  
	    {0, ""};
	Result ->
	    ?dbg("handle_command: execute Result = ~p\n",[Result]), 
	    {1, Result}
    catch
	error:_Reason ->
	    ?dbg("handle_command: execute catch Reason = ~p\n",[_Reason]), 
	    {3, "Internal Error"}
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
    case co_api:alive(LoopData#loop_data.co_node) of
	true ->
	    co_api:unreserve(LoopData#loop_data.co_node, ?IX_OS_COMMAND),
	    co_api:detach(LoopData#loop_data.co_node);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg("handle_stop: detached.\n",[]),
    {stop, normal, ok, LoopData}.


%%--------------------------------------------------------------------
%% @doc
%% Handling cast messages.
%%
%% Ref - Reference in communication with the CANopen node.
%% 
%% For description of message compare with the correspondig functions:
%% @see abort/2  
%% @end
%%--------------------------------------------------------------------
-type cast_msg()::
	{abort, Ref::reference(), Reason::atom()} |
	{name_change, OldName::atom(), NewName::atom()} |
	term().

-spec handle_cast(Msg::cast_msg(), LoopData::#loop_data{}) ->
			 {noreply, LoopData::#loop_data{}}.
			 
handle_cast({abort, Ref, _Reason}, LoopData) ->
    ?dbg("handle_cast: abort ref = ~p, reason\n", [Ref, _Reason]),
     if Ref =/= LoopData#loop_data.ref ->
	     ?dbg("handle_cast: Abort of unknown reference", []),
	     {noreply, LoopData};
	true ->
	     ?dbg("handle_cast: Abort reason = ~p. ", [_Reason]),
	     {noreply, LoopData#loop_data {read_buf = (<<>>), state = init, 
					   ref = undefined,
					   command = "", status = 0, reply = ""}}
     end;

handle_cast({name_change, OldName, NewName}, 
	    LoopData=#loop_data {co_node = {name, OldName}}) ->
   ?dbg("handle_cast: co_node name change from ~p to ~p.", 
	 [OldName, NewName]),
    {noreply, LoopData#loop_data {co_node = {name, NewName}}};

handle_cast({name_change, _OldName, _NewName}, LoopData) ->
   ?dbg("handle_cast: co_node name change from ~p to ~p, ignored.", 
	 [_OldName, _NewName]),
    {noreply, LoopData};

handle_cast(_Msg, LoopData) ->
    ?dbg("handle_cast: Message = ~p. ", [_Msg]),
    {noreply, LoopData}.


%%--------------------------------------------------------------------
%% @doc
%% Handling all non call/cast messages.
%%
%% Info types: <br/>
%% {Status, Reply} - When spawned process has finished executing. <br/>
%% {'EXIT', Pid, Reason} - When spawned process has terminated. <br/>
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{Status::integer(), Reply::term()} |
	{'EXIT', Pid::pid(), Reason::term()} |
	%% Unknown info
	term().

-spec handle_info(Info::info(), LoopData::#loop_data{}) ->
			 {noreply, LoopData::#loop_data{}}.
			 
handle_info({Status, Reply} = _Info, LoopData) ->
    %% Result received from spawned process
    ?dbg("handle_info: Received result ~p\n", [_Info]),
    {noreply, LoopData#loop_data {state = executed,
				  status = Status, 
				  reply = Reply}};

handle_info({'EXIT', Pid, normal}, LoopData=#loop_data {exec_pid = Pid}) ->
    %% Execution process terminated normally
    {noreply, LoopData};
handle_info({'EXIT', Pid, _Reason}, LoopData=#loop_data {exec_pid = Pid}) ->
    ?dbg("handle_info: unexpected EXIT for process ~p received, reason ~p", 
	 [Pid, _Reason]),
     {noreply, LoopData#loop_data {state = executed,
				   status = 3, 
				   reply = "Internal Error"}};
handle_info({'EXIT', _Pid, _Reason}, LoopData) ->
    %% Other process terminated
   ?dbg("handle_info: unexpected EXIT for process ~p received, reason ~p", 
	 [_Pid, _Reason]),
    {noreply, LoopData};

handle_info(_Info, LoopData) ->
    ?dbg("handle_info: Unknown Info ~p\n", [_Info]),
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
%% Convert process state when code is changed
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
name(CoNode) when is_integer(CoNode) ->
    list_to_atom(atom_to_list(?MODULE) ++ integer_to_list(CoNode,16));
name({name, CoNode}) when is_atom(CoNode)->
    list_to_atom(atom_to_list(?MODULE) ++ atom_to_list(CoNode)).

