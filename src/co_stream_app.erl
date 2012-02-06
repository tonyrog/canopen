%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen application behaviour.
%%% Defines behaviour for an application using the 
%%% {streamed, Module} transfer mode in communicating with the 
%%% CANOpen node.
%%%
%%% File: co_stream_app.erl<br/>
%%% Created:  4 Jan 2012 by Marina Westman Lönne 
%%% @end


-module(co_stream_app).

-export([behaviour_info/1]).

%%--------------------------------------------------------------------
%% @doc
%% Defines needed callback functions.
%% @end
%%--------------------------------------------------------------------
-spec behaviour_info(Arg::callbacks) -> 
			    list({FunctionName::atom(), Arity::integer()}).
behaviour_info(callbacks) ->
    [{write_begin, 3}, {write, 4}, {read_begin, 3}, {read, 3},
     {index_specification, 2}, {abort, 3}];
behaviour_info(_) ->
    undefined.
