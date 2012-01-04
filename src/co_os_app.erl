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

%% API
-export([start/1, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% CO node callbacks
-export([get_entry/2,
	 set/3, get/2,
	 write_begin/3, write/4,
	 read_begin/3, read/3,
	 abort/2]).

%% Test
-export([loop_data/0]).

-define(NAME, os_command_app).
-define(WRITE_SIZE, 28).

-record(loop_data,
	{
	  state,
	  co_node,
	  command,
	  status,
	  reply
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
    gen_server:start_link({local, ?NAME}, ?MODULE, [CoSerial],[]).

	
%%--------------------------------------------------------------------
%% @spec stop() -> ok | {error, Error}
%% @doc
%%
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
    gen_server:call(?NAME, stop).

loop_data() ->
    gen_server:call(?NAME, loop_data).

%% transfer_mode == {atomic, Module}
set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg(?NAME," set ~.16B:~.8B to ~p\n",[Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).
get(Pid, {Index, SubInd}) ->
    ?dbg(?NAME," get ~.16B:~.8B\n",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).

%% transfer_mode = {streamed, Module}
write_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg(?NAME," write_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {write_begin, {Index, SubInd}, Ref}).
write(Pid, Ref, Data, EodFlag) ->
    ?dbg(?NAME," write ref = ~p, data = ~p, Eod = ~p\n",[Ref, Data, EodFlag]),
    gen_server:call(Pid, {write, Ref, Data, EodFlag}).

read_begin(Pid, {Index, SubInd}, Ref) ->
    ?dbg(?NAME," read_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
    gen_server:call(Pid, {read_begin, {Index, SubInd}, Ref}).
read(Pid, Bytes, Ref) ->
    ?dbg(?NAME," read ref = ~p, \n",[Ref]),
    gen_server:call(Pid, {read, Bytes, Ref}).

abort(Pid, Ref) ->
    ?dbg(?NAME," abort ref = ~p\n",[Ref]),
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
    put(dbg, true),
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
handle_call({set, {?IX_OS_COMMAND, ?SI_OS_COMMAND}, Command}, _From, LoopData) ->
    %% For now 
    C = binary_to_list(Command),
    try os:cmd(C) of
	{error, E} ->

	    ?dbg(?NAME," handle_call: execute command Error = ~p\n",[E]),    
	    {reply, ok, LoopData#loop_data {command = Command, 
					    status = 3, 
					    reply = E}};
	Result ->
	    ?dbg(?NAME," handle_call: execute command Result = ~p\n",[Result]),    
	    {reply, ok, LoopData#loop_data {command = Command, 
					    status = 1, 
					    reply = Result}}
    catch
	error:Reason ->
	    ?dbg(?NAME," handle_call: execute command catch Reason = ~p\n",[Reason]),    
	    {reply, ok, LoopData#loop_data {command = Command, 
					    status = 3, 
					    reply = "Internal Error"}}
    end;
handle_call({set, {Index, SubInd}, _NewValue}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: set ~.16B:~.8B \n",[Index, SubInd]),    
    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_COMMAND}}, _From, LoopData) ->
    {reply, {ok, LoopData#loop_data.command}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_STATUS}}, _From, LoopData) ->
    {reply, {ok, LoopData#loop_data.status}, LoopData};
handle_call({get, {?IX_OS_COMMAND, ?SI_OS_REPLY}}, _From, LoopData) ->
    {reply, {ok, LoopData#loop_data.reply}, LoopData};
handle_call({set, {Index, SubInd}}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: get ~.16B:~.8B \n",[Index, SubInd]),
    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
handle_call({abort, Ref}, _From, LoopData) ->
    ?dbg(?NAME," handle_call: abort ref = ~p\n",[Ref]),
    {reply, ok, LoopData};
handle_call(loop_data, _From, LoopData) ->
    io:format("~p: LoopData = ~p\n", [?MODULE,LoopData]),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ?dbg(?NAME," handle_call: stop\n",[]),
    case whereis(list_to_atom(co_lib:serial_to_string(LoopData#loop_data.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    co_node:unreserve(LoopData#loop_data.co_node, ?IX_OS_COMMAND),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ?dbg(?NAME," handle_call: stop detached.\n",[]),
    {stop, normal, ok, LoopData};
handle_call(Request, _From, LoopData) ->
    ?dbg(?NAME," handle_call: bad call ~p.\n",[Request]),
    {reply, {error,bad_call}, LoopData}.


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
    ?dbg(?NAME," handle_cast: My object ~w has changed. ", [Ix]),
    {ok, Val} = co_node:value(LoopData#loop_data.co_node, Ix),
    ?dbg(?NAME,"New value is ~p\n", [Val]),
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

%%--------------------------------------------------------------------
%% @spec get_entry(Pid, {Index, SubInd}) -> {entry, Entry::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
get_entry(_Pid, {?IX_OS_COMMAND = Index, 255} = I) ->
    ?dbg(?NAME," get_entry type ~.16B \n",[Index]),
    Value = (?UNSIGNED8 bsl 8) bor ?OBJECT_VAR, %% VAR/ARRAY .. fixme
    Entry = #app_entry{index = I,
		       type = ?UNSIGNED32,
		       access = ?ACCESS_RO,
		       transfer = {value, Value}},
    {entry,Entry};
get_entry(_Pid, {?IX_OS_COMMAND, 0} = I) ->
    reply_entry(I, ?UNSIGNED8, ?ACCESS_RO);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_COMMAND} = I) ->
    reply_entry(I, ?OCTET_STRING, ?ACCESS_RW);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_STATUS} = I) ->
    reply_entry(I, ?UNSIGNED8, ?ACCESS_RO);
get_entry(_Pid, {?IX_OS_COMMAND, ?SI_OS_REPLY} = I) ->
    reply_entry(I, ?OCTET_STRING, ?ACCESS_RO);
get_entry(Pid, Index) when is_integer(Index) ->
    get_entry(Pid, {Index, 0});
get_entry(_Pid, {Index, SubInd})  ->
    ?dbg(?NAME," get_entry ~.16B:~.8B \n",[Index, SubInd]),
    {error, ?ABORT_NO_SUCH_OBJECT}.

reply_entry({Index, SubInd} = I, Type, Access) ->
    ?dbg(?NAME," reply_entry ~.16B:~.8B, type = ~p, access = ~p\n",
	 [Index, SubInd, Type, Access]),
    Entry = #app_entry{index = I,
		       type = Type,
		       access = Access,
		       transfer = atomic},
    {entry, Entry}.

     
