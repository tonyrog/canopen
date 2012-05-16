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
%%    Example CANopen application using the CONode dictionary.
%% 
%% @end
%%===================================================================

-module(co_test_dict_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").

-behaviour(gen_server).
-behaviour(co_app).

-compile(export_all).

%% API
-export([start/2, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%% co_app and co_stream_app callbacks
-export([index_specification/2,
	 set/3, get/2]).

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
	  index_list = []
	}).



%%--------------------------------------------------------------------
%% @spec start(CoSerial, Objects) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%%
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start(CoSerial, Objects) ->
    gen_server:start_link({local, ?NAME}, ?MODULE, 
			  {CoSerial, Objects, self()}, []).

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
index_specification(Pid, {Index, SubInd} = I) ->
    ?dbg(?NAME," index_specification: ~.16B:~.8B \n",[Index, SubInd]),
    gen_server:call(Pid, {index_specification, I}).

set(Pid, {Index, SubInd}, NewValue) ->
    ?dbg(?NAME, "set: ~.16B:~.8B to ~p",[Index, SubInd, NewValue]),
    gen_server:call(Pid, {set, {Index, SubInd}, NewValue}).
get(Pid, {Index, SubInd}) ->
    ?dbg(?NAME, "get: ~.16B:~.8B",[Index, SubInd]),
    gen_server:call(Pid, {get, {Index, SubInd}}).


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
init({CoSerial, FileObjects, Starter}) ->
    ct:pal(?NAME, "Starting with objects = ~w\n", [FileObjects]),
    {ok, DictRef} = co_api:attach(CoSerial),
    DictObjects = co_file:load_objects(FileObjects, []),
    IndexList = load_objects(CoSerial, DictRef, DictObjects, []),
    {ok, #loop_data {starter = Starter, co_node = CoSerial, 
		     dict = DictRef, index_list = IndexList}}.

load_objects(_CoSerial, _DictRef, [], IndexList) ->
    IndexList;
load_objects(CoSerial, DictRef, [{Object, Entries} | Rest], Ixs) ->
    ets:insert(DictRef, Object),
    ok = co_api:reserve(CoSerial, Object#dict_object.index, ?MODULE),
    lists:foreach(fun(E) -> ets:insert(DictRef, E) end, Entries),
    load_objects(CoSerial, DictRef, Rest, [Object#dict_object.index | Ixs]).

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
handle_call({index_specification, {Index, SubInd} = I}, _From, 
	    LD=#loop_data {index_list = IList, dict = Dict}) ->
    ?dbg(?NAME, "handle_call: index_specification ~.16B:~.8B\n", [Index, SubInd]),
    case lists:member(Index, IList)  of
	true ->
	    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
		{ok,E} ->
		    Spec = #index_spec{index = I,
				       type = E#dict_entry.type,
				       access = E#dict_entry.access,
				       transfer = {dict, Dict}},
		    {reply, {spec, Spec}, LD};
		Other ->
		    {reply, Other, LD}
	    end;
	false ->
	    ?dbg(?NAME, "handle_call: index_specification error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD}
    end;
handle_call({get, {Index, SubInd}}, _From, 
	    LD=#loop_data {index_list = IList, dict = Dict}) ->
    ?dbg(?NAME, "handle_call: get ~.16B:~.8B ",[Index, SubInd]),

    case lists:member(Index, IList)  of
	true ->
	    {reply, co_dict:value(Dict, Index, SubInd), LD};
	false ->
	    ?dbg(?NAME, "handle_call: get error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD}
    end;
handle_call({set, {Index, SubInd}, NewValue}, _From,
	    LD=#loop_data {index_list = IList, dict = Dict}) ->
    ?dbg(?NAME, "handle_call: set ~.16B:~.8B to ~p", [Index, SubInd, NewValue]),

    case lists:member(Index, IList)  of
	true ->
	    {reply, co_dict:set_value(Dict, Index, SubInd, NewValue), LD};
	false ->
	    ?dbg(?NAME, "handle_call: get error = ~.16B\n", 
		 [?ABORT_NO_SUCH_OBJECT]),
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LD}
    end;

handle_call(loop_data, _From, LoopData) ->
    ?dbg(?NAME, "LoopData = ~p\n", [LoopData]),
    {reply, ok, LoopData};
handle_call(stop, _From, LoopData=#loop_data {index_list = IList, co_node = Co}) ->
    ?dbg(?NAME, "handle_call: stop\n",[]),
   case co_api:alive(Co) of
	true ->
	    lists:foreach(
	      fun(I) -> co_api:unreserve(Co, I) end, IList),
	    
	    ?dbg(?NAME, "stop: unsubscribed.\n",[]),
	    co_api:detach(Co);
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

