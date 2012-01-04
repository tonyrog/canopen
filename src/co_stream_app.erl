%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Marina Westman Lönne
%%% @doc
%%%
%%% Description: Defines behaviour for an application using the 
%%% {streamed, Module} transfer mode in communicating with the 
%%% CANOpen node.
%%%

%%% @end
%%% Created :  4 Jan 2012 by Marina Westman Lönne <malotte@malotte.net>

-module(co_stream_app).

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [{write_begin, 3}, {write, 4}, {read_begin, 3}, {read, 3},
     {get_entry, 2}, {abort, 2}];
behaviour_info(_) ->
    undefined.
