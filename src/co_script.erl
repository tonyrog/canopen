%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%% CANopen script interpretor.
%%%
%%% File    : co_script.erl <br/>
%%% Created: 23 Feb 2010 by Tony Rogvall (as pds_conf)
%%% @end
%%%-------------------------------------------------------------------
-module(co_script).

-include("../include/co_debug.hrl").

-import(lists, [reverse/1]).

%% While testing ??
%%-compile(export_all).

-export([run/0, run/1, script/1]).
-export([file/1]).
-export([string/1]).


%%====================================================================
%% API
%%====================================================================
%% @private
-spec run() -> ok.
run() ->
    usage().

%%--------------------------------------------------------------------
%% @doc
%% Runs the command specified in File(s) and halts.
%% @end
%%--------------------------------------------------------------------
-spec run(list(File::atom() | string())) ->
	ok | {error, Reason::term()}.

run([File]) when is_atom(File) ->
    script(atom_to_list(File));
run([File]) when is_list(File) ->
    script(File);
run([]) ->
    usage().

%%--------------------------------------------------------------------
%% @doc
%% Gives usage info.
%% @end
%%--------------------------------------------------------------------
-spec usage() -> ok.

usage() ->
    io:format("usage: co_script <file>\n", []),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Runs the command specified in File and halts.
%% @end
%%--------------------------------------------------------------------
-spec script(File::string()) ->
	no_return().

script(File) ->
    case file(File) of
	ok -> hlt(0);
	_Error -> hlt(1)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Runs the command specified in File.
%% @end
%%--------------------------------------------------------------------
-spec file(File::string()) ->
	ok | {error, Reason::term()}.

file(File) ->
    FileName =
	case filename:dirname(File) of
	    "." when hd(File) =/= $. ->
		filename:join(code:priv_dir(canopen), File);
	    _ -> 
		File
	end,

    ?dbg("Filename = ~p", [FileName]),

    case file:read_file(FileName) of
	{ok,Bin} ->
	    string(File, binary_to_list(Bin));
	Error ->
	    Error
    end.

hlt(N) ->
    halt(N).

%% @private
string(Cs) ->
    string("*stdin*", Cs).

string(File, Cs) ->
    case erl_scan:string(Cs) of
	{ok,Ts,_Ln} ->
	    case exprs_list(File, Ts) of
		{ok,ExprsList} ->
		    co_mgr:start([]), %% just in case
		    ?dbg("Expressions = ~p", [ExprsList]),
		    eval_list(File, ExprsList);
		Error ->
		    Error
	    end;
	{error,Err={ErrLoc,Mod,Error}, _EndLoc} ->
	    io:format("~s:~w: ~s\n", [File,ErrLoc,Mod:format_error(Error)]),
	    {error,Err}
    end.

exprs_list(File, Ts) ->
    exprs_list(File, Ts, [], []).

exprs_list(File, [T={dot,_}|Ts], AccTs, ExprsList) ->
    case erl_parse:parse_exprs(reverse([T|AccTs])) of
	{ok, Exprs} ->
	    exprs_list(File, Ts, [], [Exprs|ExprsList]);
	{error,Err={Ln,Mod,Error}} ->
	    io:format("~s:~w: ~s\n", [File,Ln,Mod:format_error(Error)]),
	    {error,Err}
    end;
exprs_list(File, [T|Ts], AccTs, ExprsList) ->
    exprs_list(File, Ts, [T|AccTs], ExprsList);
exprs_list(_File, [], [], ExprsList) ->
    {ok, reverse(ExprsList)};
exprs_list(File, [], AccTs, ExprsList) ->
    case erl_parse:parse_exprs(reverse(AccTs)) of
	{ok, Exprs} ->
	    {ok, reverse([Exprs|ExprsList])};
	{error,Err={Ln,Mod,Error}} ->
	    io:format("~s:~w: ~s\n", [File,Ln,Mod:format_error(Error)]),
	    {error,Err}
    end.

eval_list(File, ExprsList) ->
    eval_list(File, ExprsList, erl_eval:new_bindings()).

eval_list(File, [Exprs|ExprsList], Bindings) ->
    ?dbg("Eval: ~p", [Exprs]),
    try erl_eval:exprs(Exprs, Bindings, {value, fun eval_func0/2}) of
	{value,Value,Bindings1} = _R ->
	    ?dbg("Result =  ~p", [_R]),
	    case File of
		"*stdin*" ->
		    io:format("~p\n", [Value]),
		    eval_list(File, ExprsList, Bindings1);
		_ ->
		    eval_list(File, ExprsList, Bindings1)
	    end
    catch
	error:Reason ->
	    io:format("~s:~w: error: ~p\n", [File, line(Exprs), Reason]),
	    {error,Reason}
    end;
eval_list(_File, [], _Bindings) ->
    ok.

line([T|_]) when is_tuple(T), size(T) > 1 ->
    element(2, T);
line(T) when is_tuple(T), size(T) > 1 ->
    element(2, T);
line(_) ->    
    0.

eval_func0(Name, Args) ->
    io:format("Exec: ~s(~p) = ", [Name, Args]),
    Reply = eval_func(Name, Args),
    io:format("~p\n", [Reply]),
    Reply.
    

eval_func(require, [Mod]) ->
    co_mgr:client_require(Mod);
eval_func(setnid, [Nid]) ->
    co_mgr:client_set_nid(Nid);
eval_func(store, [Nid,Index,SubInd,Value]) ->
    co_mgr:client_store(Nid,Index,SubInd, Value);
eval_func(store, [Index,SubInd,Value]) ->
    co_mgr:client_store(Index,SubInd,Value);
eval_func(store, [Index,Value]) ->
    co_mgr:client_store(Index,Value);
eval_func(fetch, [Nid,Index,SubInd]) ->
    co_mgr:client_fetch(Nid,Index,SubInd);
eval_func(fetch, [Index,SubInd]) ->
    co_mgr:client_fetch(Index,SubInd);
eval_func(fetch, [Index]) ->
     co_mgr:client_fetch(Index);
eval_func(noify, [Nid,Func,Index,SubInd,Value]) ->
    co_mgr:client_notify(Nid,Func,Index,SubInd,Value);
eval_func(notify, [Func,Index,SubInd,Value]) ->
    co_mgr:client_notify(Func,Index,SubInd,Value);
eval_func(notify, [Func,Index,Value]) ->
    co_mgr:client_notify(Func,Index,Value).



    

    






