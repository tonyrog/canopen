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
%%%-------------------------------------------------------------------
%%% @author Malotte W Lonne <malotte@malotte.net>
%%% @copyright (C) 2011, Tony Rogvall
%%% @doc
%%%    Defines for debugging.
%%% @end
%%% Created : 15 December 2011
%%%-------------------------------------------------------------------
-ifndef(CO_DEBUG_HRL).
-define(CO_DEBUG_HRL, true).


%% Switching to lager (ale)
-define(dbg(Format, Args),
 	lager:debug(Format, Args)).


-define(dbg(Tag, Format, Args),
 	lager:debug([Tag], Format,[Args])).

-endif.
