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
%%    Example CANopen application streaming a file.
%% 
%% @end
%%===================================================================

-module(co_test_stream_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").
%%-include("co_debug.hrl").

-behaviour(gen_server).
-behaviour(co_stream_app).

-compile(export_all).

%% API
-export([start/2, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% co_stream_app callbacks
-export([index_specification/2,
	 write_begin/3, write/4,
	 read_begin/3, read/3,
	 abort/3]).

%% Testing
-ifdef(debug).
-define(dbg(Tag,Fmt,As), ct:pal(atom_to_list(Tag) ++ (Fmt), (As))).
-else.
-define(dbg(Tag,Fmt,As), ok).
-endif.


-define(NAME, ?MODULE). 
-define(WRITE_SIZE, 28).

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
	  writefile
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
    gen_server:start_link({local, ?NAME}, ?MODULE, 
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

%%--------------------------------------------------------------------
%% @spec index_specification(Pid, {Index, SubInd}) -> 
%%    {spec, Spec::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
index_specification(_Pid, {Index, SubInd} = I) ->
    ?dbg(?NAME,"index_specification ~.16B:~.8B \n",[Index, SubInd]),
    gen_server:call(?MODULE, {index_specification, I}).

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
    ?dbg(?NAME,"write_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
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
    ?dbg(?NAME,"write ref = ~p, data = ~p, Eod = ~p\n",[Ref, Data, EodFlag]),
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
    ?dbg(?NAME,"read_begin ~.16B:~.8B, ref = ~p\n",[Index, SubInd, Ref]),
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
    ?dbg(?NAME,"read ref = ~p, \n",[Ref]),
    gen_server:call(Pid, {read, Bytes, Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Aborts stream transaction.
%% @end
%%--------------------------------------------------------------------
-spec abort(Pid::pid(), Ref::reference(), Reason::integer()) ->
		   ok.

abort(Pid, Ref, Reason) ->
    ?dbg(?NAME," abort ref = ~p, reason = ~p\n",[Ref, Reason]),
    gen_server:cast(Pid, {abort, Ref, Reason}).
    
loop_data() ->
    gen_server:call(?MODULE, loop_data).

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
    ct:pal(?NAME, "Starting with index = ~.16B, readfile = ~p, writefile = ~p\n",
	   [Index, RFileName, WFileName]),
    {ok, _DictRef} = co_api:attach(CoSerial),
    ok = co_api:reserve(CoSerial, Index, ?MODULE),
    {ok, #loop_data {starter = Starter, co_node = CoSerial, index = Index,
		     readfilename = RFileName, writefilename = WFileName}}.

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
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_call({index_specification, {Index, SubInd} = I}, _From, LoopData) ->   
    ?dbg(?NAME, "handle_call: index_specification ~.16B:~.8B\n", [Index, SubInd]),
    case LoopData#loop_data.index of
	Index ->
	    Spec = #index_spec{index = I,
			        type = ?VISIBLE_STRING,
				access = ?ACCESS_RW,
				transfer = streamed},
	    {reply, {spec, Spec}, LoopData};
	_OtherIndex ->
	    ?dbg(?NAME, "handle_call: index_specification error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({read_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: read_begin ~.16B:~.8B, ref = ~p\n",
	 [Index, SubInd, Ref]),
    case LoopData#loop_data.index of
	Index ->
	    ?dbg(?NAME, "handle_call: read_begin opening file ~p",
		   [LoopData#loop_data.readfilename]),
	    {ok, F} = file:open(LoopData#loop_data.readfilename, 
				[read, raw, binary, read_ahead]),
	    {reply, {ok, Ref, undefined}, 
	     LoopData#loop_data {ref = Ref, readfile = F}};
	_OtherIndex ->
	    ?dbg(?NAME, "handle_call: read_begin error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({read, Ref, Bytes}, _From, LoopData) ->
    case LoopData#loop_data.ref of
	Ref ->
	    case file:read(LoopData#loop_data.readfile, Bytes) of
		{ok, Data} ->
		    {reply, {ok, Ref, Data, false}, LoopData};
		eof ->
		    ?dbg(?NAME, "handle_call: read  eof reached\n", []), 
		    file:close(LoopData#loop_data.readfile),    
		    LoopData#loop_data.starter ! eof,
		    {reply, {ok, Ref, <<>>, true}, LoopData}
	    end;
	_OtherRef ->
	    ?dbg(?NAME, "handle_call: read error = wrong_ref\n", []), 
	    {reply, {error, ?ABORT_INTERNAL_ERROR}, LoopData}	    
    end;
handle_call({write_begin, {Index, SubInd}, Ref}, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: write_begin ~.16B:~.8B, ref = ~p\n",
	 [Index, SubInd, Ref]),
    case LoopData#loop_data.index of
	Index ->
	    {ok, F} = file:open(LoopData#loop_data.writefilename, 
				[write, raw, binary, delayed_write]),
	    {reply, {ok, Ref, ?WRITE_SIZE}, LoopData#loop_data {ref = Ref, writefile = F}};
	_OtherIndex ->
	    ?dbg(?NAME, "handle_call: read_begin error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData}
    end;
handle_call({write, Ref, Data, Eod}, _From, LoopData) ->
    case LoopData#loop_data.ref of
	Ref ->
	    file:write(LoopData#loop_data.writefile, Data),
	    if Eod ->
		    ?dbg(?NAME, "handle_call: write eof reached\n", []), 
		    file:close(LoopData#loop_data.writefile),
		    LoopData#loop_data.starter ! eof;
	       true ->
		    do_nothing
	    end,
	    {reply, {ok, Ref}, LoopData};
	_OtherRef ->
	    ?dbg(?NAME, "handle_call: read error = wrong_ref\n", []), 
	    {reply, {error, ?abort_internal_error}, LoopData}	    
    end;
handle_call(loop_data, _From, LoopData) ->
    ?dbg(?NAME, "LoopData = ~p\n", [LoopData]),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: stop\n",[]),
    case co_api:alive(LoopData#loop_data.co_node) of
	true ->
	    co_api:unreserve(LoopData#loop_data.co_node, LoopData#loop_data.index),
	    ?dbg(?NAME, "stop: unsubscribed.\n",[]),
	    co_api:detach(LoopData#loop_data.co_node);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg(?NAME, "handle_call: stop detached.\n",[]),
    {stop, normal, ok, LoopData};
handle_call(Request, _From, LoopData) ->
    ?dbg(?NAME, "handle_call: bad call ~p.\n",[Request]),
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
handle_cast({abort, _Ref, _Reason}, LoopData) ->
    ?dbg(?NAME, "handle_call: abort ref = ~p, Reason\n",[_Ref, _Reason]),
    {noreply, LoopData};
handle_cast(_Msg, LoopData) ->
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, LoopData) -> {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, LoopData}
%%
%% Info = {notify, RemoteCobId, Index, SubInd, Value}
%% LoopData = term()
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
handle_info({notify, _RemoteCobId, {Index, SubInd}, Value}, LoopData) ->
    ?dbg(?NAME, "handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [_RemoteCobId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    ?dbg(?NAME, "handle_info: Unknown Info ~p\n", [Info]),
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

