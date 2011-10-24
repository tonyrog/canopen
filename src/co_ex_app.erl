%%% File    : co_ex_app.erl
%%% Author  : Malotte W Lönne <malotte@malotte.net>
%%% Description : Example canopen application
%%% Created : 19 October 2011 by Malotte W Lönne

-module(co_ex_app).
-include_lib("canopen/include/canopen.hrl").

-behaviour(gen_server).

-compile(export_all).

%% API
-export([start/1, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 
-define(TEST_IX, 16#2003).
-define(DICT,[{{16#2003, 0}, ?VISIBLE_STRING, "Mine"},
	      {{16#3003, 0}, ?INTEGER, 7},
	      {{16#3004, 0}, ?VISIBLE_STRING, "Long string"},
	      {{16#3333, 2}, ?INTEGER, 0},
	      {{16#6000, 0}, ?INTEGER, 0}]).

-record(loop_data,
	{
	  state,
	  co_node,
	  dict
	}).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start(CoNode) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [CoNode], []).

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
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, LoopData} |
%%                     {ok, LoopData, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([CoNode]) ->
    Dict = ets:new(my_dict, [public, ordered_set]),
    co_node:attach(CoNode),
    load_dict(CoNode, Dict),
    co_node:subscribe(CoNode, {?IX_RPDO_PARAM_FIRST, ?IX_RPDO_PARAM_LAST}),
    {ok, #loop_data {state=init, co_node = CoNode, dict=Dict}}.

load_dict(CoNode, Dict) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value} = Entry) ->
			  ets:insert(Dict, Entry),
			  co_node:subscribe(CoNode, Index)
		  end, ?DICT).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, LoopData) ->
%%                                   {reply, Reply, LoopData} |
%%                                   {reply, Reply, LoopData, Timeout} |
%%                                   {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, Reply, LoopData} |
%%                                   {stop, Reason, LoopData}
%% @end
%%--------------------------------------------------------------------
handle_call({get, Index, SubInd}, _From, LoopData) ->
    io:format("~p: get ~.16B:~.8B \n",[self(), Index, SubInd]),
    case ets:lookup(LoopData#loop_data.dict, {Index, SubInd}) of
	[] ->
	    {reply, {error, ?ABORT_NO_SUCH_OBJECT}, LoopData};
	[{{Index, SubInd}, Type, Value}] ->
	    {reply, {value, Type, Value}, LoopData}
    end;
handle_call({set, Index, SubInd, NewValue}, _From, LoopData) ->
    io:format("~p: set ~.16B:~.8B to ~p\n",[self(), Index, SubInd, NewValue]),
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
    io:format("LoopData = ~p\n", [LoopData]),
    {reply, ok, LoopData};
handle_call(dict, _From, LoopData) ->
    Dict = ets:tab2list(LoopData#loop_data.dict),
    io:format("Dictionary = ~p\n", [Dict]),
    {reply, ok, LoopData};    
handle_call(stop, _From, LoopData) ->
    {stop, normal, ok, LoopData};
handle_call(_Request, _From, LoopData) ->
    {reply, {error,bad_call}, LoopData}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, LoopData) -> {noreply, LoopData} |
%%                                  {noreply, LoopData, Timeout} |
%%                                  {stop, Reason, LoopData}
%% @end
%%--------------------------------------------------------------------
handle_cast({object_changed, Ix}, LoopData) ->
    io:format("My object ~w has changed\n", [Ix]),
    {noreply, LoopData};
handle_cast(_Msg, LoopData) ->
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, LoopData) -> {noreply, LoopData} |
%%                                   {noreply, LoopData, Timeout} |
%%                                   {stop, Reason, LoopData}
%% @end
%%--------------------------------------------------------------------
handle_info({notify, RemoteId, Index, SubInd, Value}, LoopData) ->
    io:format("handle_info:notify ~.16B: ID=~8.16.0B:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    {noreply, LoopData};
handle_info(Info, LoopData) ->
    io:format("handle_info: Unknown Info ~p\n", [Info]),
    {noreply, LoopData}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, LoopData) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, LoopData) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_node:unsubscribe(LoopData#loop_data.co_node, Index)
		  end, ?DICT),
    co_node:detach(LoopData#loop_data.co_node),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, LoopData, Extra) -> {ok, NewLoopData}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, LoopData, _Extra) ->
    {ok, LoopData}.

