%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen application behaviour. <br/>
%%% Defines behaviour for an application using the 
%%% {atomic, Module} transfer mode in communicating with the 
%%% CANOpen node.
%%%
%%% File: co_app.erl <br/>
%%% Created:  4 Jan 2012 by Malotte Westman Lönne 
%%% @end

-module(co_app).

-export([behaviour_info/1]).


%%--------------------------------------------------------------------
%% @doc
%% Defines needed callback functions.
%% @end
%%--------------------------------------------------------------------
-spec behaviour_info(Arg::callbacks) -> 
			    list({FunctionName::atom(), Arity::integer()}).
behaviour_info(callbacks) ->
    [{set, 3}, {get, 2}, {index_specification, 2}];
behaviour_info(_) ->
    undefined.
