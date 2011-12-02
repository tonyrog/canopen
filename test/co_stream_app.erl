%%-------------------------------------------------------------------
%% @author Malotte W Lonne <malotte@malotte.net>
%% @copyright (C) 2011, Tony Rogvall
%% @doc
%%    Example CANopen application streaming a file.
%% 
%% @end
%%===================================================================

-module(co_stream_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").

-behaviour(gen_server).

-compile(export_all).

%% API
-export([start/2, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% CO node callbacks
-export([get_entry/2]).

-define(SERVER, ?MODULE). 

-record(loop_data,
	{
	  starter,
	  co_node,
	  dict,
	  index,
	  ref,
	  readfilename,
	  readfile,
	  writefilename,
	  writefile,
	  writebuf
	}).



%%--------------------------------------------------------------------
%% @spec start(CoSerial) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%%
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start(CoSerial, {Index, RFile, WFile}) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, 
			  {CoSerial, {Index, RFile, WFile}, self()}, []).

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

%%--------------------------------------------------------------------
%% @spec get_entry(Pid, {Index, SubInd}) -> {entry, Entry::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
get_entry(_Pid, {Index, SubInd} = I) ->
    ct:pal("~p: get_entry ~.16B:~.8B \n",[?MODULE, Index, SubInd]),
    gen_server:call(?MODULE, {get_entry, I}).

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
init({CoSerial, {Index, RFileName, WFileName}, Starter}) ->
    ct:pal("Starting with index = ~.16B, readfile = ~p, writefile = ~p\n",
	   [Index, RFileName, WFileName]),
    {ok, _NodeId} = co_node:attach(CoSerial),
    ok = co_node:reserve(CoSerial, Index, ?MODULE),
    {ok, #loop_data {starter = Starter, co_node = CoSerial, index = Index,
		     readfilename = RFileName, writefilename = WFileName,
		     writebuf = (<<>>)}}.

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
%% Handling all non call/cast messages.
%% Required to at least handle a notify msg as specified above. <br/>
%% RemoteId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_call({get_entry, {Index, SubInd} = I}, _From, LoopData) ->   
    ct:pal("~p: handle_call: get_entry ~.16B:~.8B\n", [?MODULE, Index, SubInd]),
    case LoopData#loop_data.index of
	Index ->
	    Entry = #app_entry{index = I,
			       type = ?VISIBLE_STRING,
			       access = ?ACCESS_RW,
			       transfer = streamed},
	    {reply, {entry, Entry}, LoopData};
	_OtherIndex ->
	    ct:pal("~p: handle_call: get_entry error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({read_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    %% To test 'real' streaming
    ct:pal("~p: handle_call: read_begin ~.16B:~.8B, ref = ~p\n",
	 [?MODULE, Index, SubInd, Ref]),
    case LoopData#loop_data.index of
	Index ->
	    {ok, F} = file:open(LoopData#loop_data.readfilename, 
				[read, raw, binary, read_ahead]),
	    {reply, {ok, Ref, unknown}, 
	     LoopData#loop_data {ref = Ref, readfile = F}};
	_OtherIndex ->
	    ct:pal("~p: handle_call: read_begin error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({read, Bytes, Ref}, _From, LoopData) ->
%%    ct:pal("~p: handle_call: read ref = ~p\n",[?MODULE, Ref]),
    case LoopData#loop_data.ref of
	Ref ->
	    case file:read(LoopData#loop_data.readfile, Bytes) of
		{ok, Data} ->
%%		    ct:pal("~p: handle_call: read ref = ~p, data = ~p\n",
%%			   [?MODULE, Ref, Data]),
		    {reply, {ok, Ref, Data}, LoopData};
		eof ->
		    ct:pal("~p: handle_call: read  eof reached\n", [?MODULE]), 
		    file:close(LoopData#loop_data.readfile),    
		    LoopData#loop_data.starter ! eof,
		    {reply, {ok, Ref, <<>>}, LoopData}
	    end;
	_OtherRef ->
	    ct:pal("~p: handle_call: read error = wrong_ref\n", [?MODULE]), 
	    {reply, {error, ?ABORT_INTERNAL_ERROR}, LoopData}	    
    end;
handle_call({write_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    ct:pal("~p: handle_call: write_begin ~.16B:~.8B, ref = ~p\n",
	 [?MODULE, Index, SubInd, Ref]),
    case LoopData#loop_data.index of
	Index ->
	    {ok, F} = file:open(LoopData#loop_data.writefilename, 
				[write, raw, binary, delayed_write]),
	    {reply, ok, LoopData#loop_data {ref = Ref, writefile = F}};
	_OtherIndex ->
	    ct:pal("~p: handle_call: read_begin error = ~.16B\n", 
		 [?MODULE, ?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({write_end, Ref, N}, _From, LoopData) ->
    ct:pal("~p: handle_call: write_end ref = ~p, N = ~p\n",[?MODULE, Ref, N]),
    case LoopData#loop_data.ref of
	Ref ->
	    BufData = LoopData#loop_data.writebuf,
	    if BufData =/= (<<>>) ->
		    file:write(LoopData#loop_data.writefile, BufData);
	       true ->
		    do_nothing
	    end,
	    file:close(LoopData#loop_data.writefile),
	    LoopData#loop_data.starter ! eof,
	    {reply, ok, LoopData#loop_data {writebuf = (<<>>)}};
	_OtherRef ->
	    ct:pal("~p: handle_call: read error = wrong_ref\n", [?MODULE]), 
	    {reply, {error, ?ABORT_INTERNAL_ERROR}, LoopData}	    
    end;
handle_call({abort, Ref}, _From, LoopData) ->
    ct:pal("~p: handle_call: abort ref = ~p\n",[?MODULE, Ref]),
    {reply, ok, LoopData};
handle_call(loop_data, _From, LoopData) ->
    ct:pal("~p: LoopData = ~p\n", [?MODULE, LoopData]),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ct:pal("~p: handle_call: stop\n",[?MODULE]),
    case whereis(list_to_atom(co_lib:serial_to_string(LoopData#loop_data.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    co_node:unreserve(LoopData#loop_data.co_node, LoopData#loop_data.index),
	    ct:pal("~p: stop: unsubscribed.\n",[?MODULE]),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ct:pal("~p: handle_call: stop detached.\n",[?MODULE]),
    {stop, normal, ok, LoopData};
handle_call(Request, _From, LoopData) ->
    ct:pal("~p: handle_call: bad call ~p.\n",[?MODULE, Request]),
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
%% transfer_mode == streamed
handle_cast({write, Ref, Data}, LoopData) ->
    %% ct:pal("~p: handle_cast: write ref = ~p, data = ~p\n",[?MODULE,Ref,Data]),
    case LoopData#loop_data.ref of
	Ref ->
	    if LoopData#loop_data.writebuf =/= (<<>>) ->
		    file:write(LoopData#loop_data.writefile, 
			       LoopData#loop_data.writebuf);
	       true ->
		    do_nothing
	    end,
	    {noreply, LoopData#loop_data {writebuf = Data}};
	_OtherRef ->
	    ct:pal("~p: handle_call: read error = wrong_ref\n", [?MODULE]), 
	    {noreply, LoopData}	    
    end;
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
    ct:pal("~p: handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [?MODULE, RemoteId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    ct:pal("~p: handle_info: Unknown Info ~p\n", [?MODULE, Info]),
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

