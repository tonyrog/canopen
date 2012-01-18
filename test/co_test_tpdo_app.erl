%%-------------------------------------------------------------------
%% @author Malotte W Lonne <malotte@malotte.net>
%% @copyright (C) 2011, Tony Rogvall
%% @doc
%%    Example CANopen application responsible for tpdos.
%% 
%% Required minimum API:
%% <ul>
%% <li>handle_call - get</li>
%% <li>handle_call - set</li>
%% <li>handle_info - notify</li>
%% </ul>
%% @end
%%===================================================================

-module(co_test_tpdo_app).
-include_lib("canopen/include/canopen.hrl").
-include("co_app.hrl").

-behaviour(gen_server).

-compile(export_all).

%% API
-export([start/3, stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% CO node callbacks
-export([tpdo_callback/3,
	 value/2]).


%% Testing
-ifdef(debug).
-define(dbg(Format, Args),
	ct:pal("~p: ~p: " ++ Format ++ "\n", ([self(), ?MODULE] ++ Args))).
-else.
-define(dbg(Fmt,As), ok).
-endif.

-record(loop_data,
	{
	  co_node,
	  offset,
	  tpdo_dict,
	  callback,
	  starter
	}).


%%--------------------------------------------------------------------
%% @spec start(CoSerial) -> {ok, Pid} | ignore | {error, Error}
%% @doc
%%
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start(CoSerial, Offset, IndexList) ->
    gen_server:start_link({local, ?MODULE}, 
			  ?MODULE, [CoSerial, Offset, IndexList, self()], []).
    	
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
%%   {entry, Entry::record()} | false
%%
%% @doc
%% Returns the data structure for {Index, SubInd}.
%% Should if possible be implemented without process context switch.
%%
%% @end
%%--------------------------------------------------------------------
index_specification(_Pid, {Index, SubInd} = I) ->
    ?dbg("index_specification: ~.16B:~.8B ",[Index, SubInd]),
    case ets:lookup(tpdo_dict, I) of
	[{I, Type, _Value}] ->
	    Spec = #index_spec{index = I,
			       type = co_test_lib:type(Type),
			       access = ?ACCESS_RW,
			       transfer = atomic},
	    {spec, Spec};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
index_specification(Pid, Index) when is_integer(Index) ->
    index_specification(Pid, {Index, 0}).


%% TPDO callbacks
tpdo_callback(_Pid, {Index, SubInd} = I, MF) ->
    ?dbg("tpdo_callback: ~.16B:~.8B callback = ~w",[Index, SubInd, MF]),
    case ets:lookup(tpdo_dict, I) of
	[{I, Type, _Value}] ->
	    gen_server:cast(?MODULE, {callback, I, MF}),
	    {ok, co_test_lib:type(Type)};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end.

value(_Pid, {Index, SubInd} = I) ->
    ?dbg("value: ~.16B:~.8B ",[Index, SubInd]),
    case ets:lookup(tpdo_dict, I) of
	[{I, _Type, Value}] ->
	    gen_server:cast(?MODULE, {value, I}),
	    {ok, Value};
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
value(Pid, Index) when is_integer(Index) ->
    value(Pid, {Index, 0}).

set(_Pid, {Index, SubInd} = I, NewValue) ->
    ?dbg("value: ~.16B:~.8B ",[Index, SubInd]),
    case ets:lookup(tpdo_dict, I) of
	[{I, Type, _Value}] ->
	    ets:insert(tpdo_dict, {I, Type, NewValue}),
	    gen_server:cast(?MODULE, {set, I, NewValue}),
	    ok;
	[] ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
set(Pid, Index, NewValue) when is_integer(Index) ->
    set(Pid, {Index, 0}, NewValue).

loop_data() ->
    gen_server:call(?MODULE, loop_data).

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
init([CoSerial, Offset, IndexList, Starter]) ->
    put(dbg, true),
    DictTable = ets:new(tpdo_dict, [public, named_table, ordered_set]),
    {ok, _NodeId} = co_node:attach(CoSerial),
    load_dict(CoSerial, DictTable, IndexList),
    {ok, #loop_data {co_node = CoSerial, offset = Offset,
		     tpdo_dict = DictTable, starter = Starter}}.


load_dict(CoSerial, DictTable, IndexList) ->
    ?dbg("Dict ~p", [IndexList]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value} = Entry) ->
			  ets:insert(DictTable, Entry),
			  ?dbg("Inserting entry = ~p", [Entry]),
			  co_node:reserve(CoSerial, Index, ?MODULE)
		  end, IndexList).

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
%% RemoteId = Id of remote CANnode initiating the msg. <br/>
%% Index = Index in Object Dictionary <br/>
%% SubInd = Sub index in Object Disctionary  <br/>
%% Value = Any value the node chooses to send.
%% 
%% @end
%%--------------------------------------------------------------------
handle_call(loop_data, _From, LD) ->
    io:format("~p: LD = ~p", [?MODULE, LD]),
    {reply, ok, LD};
handle_call(stop, _From, LD) ->
    ?dbg("handle_call: stop",[]),
    CoNode = case LD#loop_data.co_node of
		 co_mgr -> co_mgr;
		 Serial ->
		     list_to_atom(co_lib:serial_to_string(Serial))
	     end,
    case whereis(CoNode) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    lists:foreach(
	      fun({{Index, _SubInd}, _Type, _Value}) ->
		      co_node:unreserve(LD#loop_data.co_node, Index)
	      end, ets:tab2list(LD#loop_data.tpdo_dict)),
	    ?dbg("stop: unsubscribed.",[]),
	    co_node:detach(LD#loop_data.co_node)
    end,
    ?dbg("handle_call: stop detached.",[]),
    {stop, normal, ok, LD};
handle_call(Request, _From, LD) ->
    ?dbg("handle_call: bad call ~p.",[Request]),
    {reply, {error,bad_call}, LD}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, LD) -> {noreply, LD} |
%%                                  {noreply, LD, Timeout} |
%%                                  {stop, Reason, LD}
%% @doc
%% Handling cast messages:
%% <ul>
%% <li>  callback </li>
%% <li>  value </li>
%% <li>  set </li>
%% </ul>
%% @end
%%--------------------------------------------------------------------
handle_cast({callback, {_Ix, _Si}, MF} = Msg, LD) ->
    ?dbg("handle_cast: callback called for ~.16B:~.8B with mf = ~p",
	 [_Ix, _Si, MF]),
    LD#loop_data.starter ! Msg,
    {noreply, LD#loop_data {callback = MF}};
handle_cast({value, {_Ix, _Si}} = Msg, LD) ->
    ?dbg("handle_cast: value called for ~.16B:~.8B ",[_Ix, _Si]),
    LD#loop_data.starter ! Msg,
    {noreply, LD};
handle_cast({set, {_Ix, _Si} = I, Value} = Msg, 
	    LD=#loop_data {co_node = CoNode, callback = {M, F}}) ->
    ?dbg("handle_cast: set called for ~.16B:~w with ~p",[_Ix, _Si, Value]),
    ok = M:F(CoNode, I, Value),
    LD#loop_data.starter ! Msg,
    {noreply, LD};
handle_cast(_Msg, LD) ->
    ?dbg("handle_cast: Unknown message ~p. ", [_Msg]),
    {noreply, LD}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, LD) -> {noreply, LD} |
%%                                   {noreply, LD, Timeout} |
%%                                   {stop, Reason, LD}
%%
%% Info = {notify, RemoteId, Index, SubInd, Value}
%% LD = term()
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
 
