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
-export([get_entry/2]).

%% Testing
-ifdef(debug).
-define(dbg(Fmt,As), io:format((Fmt), (As))).
-else.
-define(dbg(Fmt,As), ok).
-endif.

-define(SERVER, ?MODULE). 
-define(TEST_IX, 16#2003).
-define(DICT,[{{16#2003, 0}, undef, undef}, %% To test notify after central set
	      {{16#6033, 0}, ?VISIBLE_STRING, "Mine"},
	      {{16#6034, 0}, ?VISIBLE_STRING, "Long string"},
	      {{16#7033, 0}, ?INTEGER, 7},
	      {{16#7333, 2}, ?INTEGER, 0},
	      {{16#7334, 0}, ?INTEGER, 0}, %% To test timeout
	      {{16#6000, 0}, undef, undef}]). %% To test notify of mpdo

-record(loop_data,
	{
	  state,
	  co_node,
	  dict
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
    gen_server:call(co_ex_app, stop).

loop_data() ->
    gen_server:call(co_ex_app, loop_data).

dict() ->
    gen_server:call(co_ex_app, dict).

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
    {ok, _NodeId} = co_node:attach(CoSerial),
    load_dict(CoSerial, Dict),
    {ok, #loop_data {state=init, co_node = CoSerial, dict=Dict}}.

load_dict(CoSerial, Dict) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value} = Entry) ->
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
handle_call({get, 16#7334, _SubInd}, _From, LoopData) ->
    %% To test timeout
    timer:sleep(2000),
    {reply, {ok, 0}, LoopData};
handle_call({get, Index, SubInd}, _From, LoopData) ->
    ?dbg("~p: get ~.16B:~.8B \n",[self(), Index, SubInd]),
    case ets:lookup(LoopData#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{{Index, SubInd}, Type, Value}] ->
	    {reply, {value, Type, Value}, LoopData}
    end;
handle_call({set, 16#7334, _SubInd, _NewValue}, _From, LoopData) ->
    %% To test timeout
    timer:sleep(2000),
    {reply, ok, LoopData};
handle_call({set, Index, SubInd, NewValue}, _From, LoopData) ->
    ?dbg("~p: set ~.16B:~.8B to ~p\n",[self(), Index, SubInd, NewValue]),
    case ets:lookup(LoopData#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{{Index, SubInd}, _Type, NewValue}] ->
	    %% No change
	    {reply, ok, LoopData};
	[{{Index, SubInd}, Type, _OldValue}] ->
	    ets:insert(LoopData#loop_data.dict, {{Index, SubInd}, Type, NewValue}),
	    {reply, ok, LoopData}
    end;
handle_call(loop_data, _From, LoopData) ->
    ?dbg("LoopData = ~p\n", [LoopData]),
    {reply, ok, LoopData};
handle_call(dict, _From, LoopData) ->
    Dict = ets:tab2list(LoopData#loop_data.dict),
    io:format("Dictionary = ~p\n", [Dict]),
    {reply, ok, LoopData};    
handle_call(stop, _From, LoopData) ->
    ?dbg("~p: stop:\n",[?MODULE]),
    case whereis(list_to_atom(co_lib:serial_to_string(LoopData#loop_data.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    lists:foreach(
	      fun({{Index, _SubInd}, _Type, _Value}) ->
		      co_node:unsubscribe(LoopData#loop_data.co_node, Index)
	      end, ?DICT),
	    ?dbg("~p: stop: unsubscribed.\n",[?MODULE]),
	    co_node:detach(LoopData#loop_data.co_node)
    end,
    ?dbg("~p: stop: detached.\n",[?MODULE]),
    {stop, normal, ok, LoopData};
handle_call(_Request, _From, LoopData) ->
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
    ?dbg("My object ~w has changed. ", [Ix]),
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
handle_info({notify, RemoteId, Index, SubInd, Value}, LoopData) ->
    ?dbg("handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    ?dbg("handle_info: Unknown Info ~p\n", [Info]),
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
get_entry(_Pid, {Index, SubInd}) ->
    ?dbg("~p: get_entry ~.16B:~.8B \n",[self(), Index, SubInd]),
    case lists:keyfind({Index, SubInd}, 1, ?DICT) of
	{{Index, SubInd}, Type, _Value} ->
	    Entry = #app_entry{index = Index,
			       type = Type,
			       access = ?ACCESS_RW,
			       transfer = undefined},
	    {entry, Entry};
	false ->
	    {error, ?ABORT_NO_SUCH_OBJECT}
    end;
get_entry(Pid, Index) ->
    get_entry(Pid, {Index, 0}).
