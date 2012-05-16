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
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen application behaviour. <br/>
%%% Defines behaviour for an application reserving an index that is
%%% part of a TPDO.
%%%
%%% File: co_tpdo_app.erl <br/>
%%% Created:  4 Jan 2012 by Malotte Westman Lönne 
%%% @end

-module(co_tpdo_app).

-export([behaviour_info/1]).


%%--------------------------------------------------------------------
%% @doc
%% Defines needed callback functions.
%% @end
%%--------------------------------------------------------------------
-spec behaviour_info(Arg::callbacks) -> 
			    list({FunctionName::atom(), Arity::integer()}).
behaviour_info(callbacks) ->
    [{tpdo_callback, 3}, {index_specification, 2}];
behaviour_info(_) ->
    undefined.
