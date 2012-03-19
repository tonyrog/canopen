%%%------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen script file.
%%%
%%% File    : co_script.erl <br/>
%%% Created: 23 Feb 2010 by Tony Rogvall (as pds_conf)
%%% @end
%%%-------------------------------------------------------------------

-module(co_script).

-import(lists, [reverse/1]).

-export([run/0, run/1, script/1]).
-export([file/1]).
-export([string/1]).

run() ->
    usage().

run([File]) when is_atom(File) ->
    script(atom_to_list(File));
run([]) ->
    usage().

usage() ->
    io:format("usage: COscript <file>\n", []),
    ok.

script(File) ->
    case file(File) of
	ok -> hlt(0);
	_Error -> hlt(1)
    end.

file(File) ->
    Filename =
	case filename:dirname(File) of
	    "." when hd(File) =/= $. ->
		filename:join(code:priv_dir(pds), File);
	    _ -> 
		File
	end,
    case file:read_file(Filename) of
	{ok,Bin} ->
	    string(File, binary_to_list(Bin));
	Error ->
	    Error
    end.

hlt(N) ->
    halt(N).


string(Cs) ->
    string("*stdin*", Cs).

string(File, Cs) ->
    case erl_scan:string(Cs) of
	{ok,Ts,_Ln} ->
	    case exprs_list(File, Ts) of
		{ok,ExprsList} ->
		    co_mgr:start([]), %% just in case
		    eval_list(File, ExprsList);
		Error ->
		    Error
	    end;
	{error,Err={Ln,Mod,Error}} ->
	    io:format("~s:~w: ~s\n", [File,Ln,Mod:format_error(Error)]),
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
    try erl_eval:exprs(Exprs, Bindings, {value, fun eval_func0/2}) of
	{value,Value,Bindings1} ->
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
    co_mgr:require(Mod);
eval_func(setnid, [Nid]) ->
    co_mgr:setnid(Nid);
eval_func(set, [Nid,Index,SubInd,Value,Type]) ->
    co_mgr:store(Nid,Index,SubInd,segment,{value, Value, Type});
eval_func(get, [Nid,Index,SubInd,Type]) ->
    co_mgr:fetch(Nid,Index,SubInd,segment,{value, Type});
eval_func(noify, [Nid,Index,SubInd,Value]) ->
    co_mgr:notify(Nid,Index,SubInd,Value);
eval_func(notify, [Index,SubInd,Value]) ->
    co_mgr:notify(Index,SubInd,Value);
eval_func(notify, [Index,Value]) ->
    co_mgr:notify(Index,Value).



    

    






