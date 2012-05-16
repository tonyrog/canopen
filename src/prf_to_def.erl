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
%% @hidden
%% Convert prf (python file) to erlang def file
%%

-module(prf_to_def).

-compile(export_all).

-import(lists, [reverse/1,map/2,foreach/2,foldl/3]).

file(File) ->
    {ok,Bin} = file:read_file(File),
    Text = c_hex_to_erl(binary_to_list(Bin)),
    {ok, Tokens, _Last} = erl_scan:string(Text),
    {Prf,[]} = parse(Tokens),
    Defs = prf_to_def(Prf),
    Ext  = filename:extension(File),
    OutFile = filename:basename(File, Ext) ++ ".def",
    case file:open(OutFile, [write]) of
	{ok, Fd} ->
	    Result = emit(Fd,Defs),
	    file:close(Fd),
	    Result;
	Error ->
	    Error
    end.

emit(Fd, Defs) ->
    each(
      fun({objdef,Index,Options},_) ->
	      io:format(Fd, "{objdef,~s,[\n", [format_index(Index)]),
	      each(
		fun({entry,SubIndex,EOptions},Delim1) ->
			io:format(Fd, "  {entry,~w,[\n", [SubIndex]),
			each(
			  fun(Kv, Delim2) ->
				  io:format(Fd, "    ~p~s\n", [Kv,Delim2])
			  end, EOptions, {",",",",""}),
			io:format(Fd, "  ]}~s\n",[Delim1]);
		   (Kv, Delim1) ->
			io:format(Fd, "  ~p~s\n", [Kv,Delim1])
		end, Options, {",",",",""}),
	      io:format(Fd, "]}.\n\n", [])
      end, Defs).

format_index({Start,Stop,Step}) ->
    io_lib:format("{16#~4.16.0B,16#~4.16.0B,~w}", [Start,Stop,Step]);
format_index({Start,Stop}) ->
    io_lib:format("{16#~4.16.0B,16#~4.16.0B}", [Start,Stop]);
format_index(Index) ->
    io_lib:format("16#~4.16.0B", [Index]).

%% Special formating each with first,next,last indication
each(Fun, List) ->
    each(Fun, List, {first,next,last}).

each(Fun, [H], FNL) ->
    Fun(H, element(3,FNL));
each(Fun, [H|T], FNL) ->
    Fun(H, element(1,FNL)),
    each1(Fun,T, FNL).

each1(Fun,[H],FNL) ->
    Fun(H, element(3,FNL));
each1(Fun,[H|T],FNL) ->
    Fun(H, element(2,FNL)),
    each1(Fun, T, FNL).

%% convert 0x => 16#
c_hex_to_erl([$0,$x|Cs]) ->    
    [$1,$6,$#|c_hex_to_erl(Cs)];
c_hex_to_erl([C|Cs]) ->
    [C | c_hex_to_erl(Cs)];
c_hex_to_erl([]) -> [].

%%
%% Parse prf tokens into objdef format
%%   {objdef, Index, Options}
%%
%%     Options = {name,Nm} | ... {entry,SubIndex,Options}
%%
%%
parse([{var,_,'Mapping'},{'=',_}|Ts]) ->
    parse_value(Ts).

%% Parse value
parse_value([{atom,_,Value}|Ts])    -> {Value, Ts};
parse_value([{string,_,Value}|Ts])  -> {Value, Ts};
parse_value([{integer,_,Value}|Ts]) -> {Value, Ts};
parse_value([{var,_,'False'}|Ts])   -> {false, Ts};
parse_value([{var,_,'True'}|Ts])    -> {true, Ts};
parse_value([{'[',_}|Ts]) -> parse_list(Ts, []);
parse_value([{'{',_}|Ts]) -> parse_map(Ts, []).

%% Parse a list '[' [ value (, value)* ] ']'
parse_list([{']',_}|Ts], Elems) ->
    {reverse(Elems), Ts};
parse_list(Ts, Elems) ->
    case parse_value(Ts) of
	{Value, [{',',_}|Ts1]} ->
	    parse_list(Ts1, [Value|Elems]);
	{Value, [{']',_}|Ts1]} ->
	    {reverse([Value|Elems]), Ts1}
    end.

%% Parse a map  '{' [ (key ':' value) [(, key ':' value )*] ] '}'
%% Assume key is either string or integer
parse_map([{'}',_}|Ts], Map) ->
    {reverse(Map), Ts};
parse_map([{integer,_,Key},{':',_}|Ts], Map) ->
    case parse_value(Ts) of
	{Value,[{',',_}|Ts1]} ->
	    parse_map(Ts1, [{Key,Value}|Map]);
	{Value,[{'}',_}|Ts1]} ->
	    {reverse([{Key,Value}|Map]), Ts1}
    end;
parse_map([{string,_,Key},{':',_}|Ts], Map) ->
    case parse_value(Ts) of
	{Value,[{',',_}|Ts1]} ->
	    parse_map(Ts1, [{Key,Value}|Map]);
	{Value,[{'}',_}|Ts1]} ->
	    {reverse([{Key,Value}|Map]), Ts1}
    end.

%% Parse assoc array elements
parse_assoc_elems([{string,Key},{':',_}|Ts], Acc) ->
    {Value, Ts1} = parse_value(Ts),
    parse_assoc_elems(Ts1, [{Key,Value}|Acc]);
parse_assoc_elems(Ts, Acc) ->
    {reverse(Acc), Ts}.
    
%%
%% Convert PRF into objdef format
%%
prf_to_def(Objs) ->
    map(fun({Index,Options}) ->
		Opts = reverse(obj_options(Options)),
		{Index1,Opts1} = def_index(Index, Opts),
		{objdef,Index1,Opts1}
	end, Objs).

%% Transform index into:  
%%   Index
%%   {From,To}        - step = 1
%%   {From,To,Step}
def_index(Index, Opts) ->
    case lists:keysearch(nbmax,1,Opts) of
	false -> {Index,Opts};
	{value,V1={nbmax,Max}} ->
	    case lists:keysearch(incr,1,Opts) of
		false ->
		    {{Index,Index+(Max-1)}, Opts--[V1]};
		{value,V2={incr,1}} ->
		    {{Index,Index+(Max-1)}, Opts--[V1,V2]};
		{value,V2={incr,I}} when I>1 ->
		    {{Index,Index+I*(Max-1),I}, Opts--[V1,V2]}
	    end
    end.
	    

obj_options(Options) ->
    foldl(
      fun({"name",Name},Acc) ->      [{name,Name}|Acc];
	 ({"struct",Struct},Acc) ->  [{struct,Struct}|Acc];
	 ({"incr",Inc}, Acc)     ->  [{incr,Inc}|Acc];
	 ({"nbmax",Max},Acc)     ->  [{nbmax,Max}|Acc];
	 ({"need", true},Acc) ->     [{category,mandatory}|Acc];
	 ({"need", false},Acc) ->    [{category,optional}|Acc];
	 ({"values", Values},Acc) -> obj_entries(Values,Acc,0)
      end, [], Options).

obj_entries([Entry|Entries],Acc,Index) ->
    Es = map(
	   fun({"name",Name}) -> {name,Name};
	      ({"type",T})    -> {type,co_lib:decode_type(T)};
	      ({"access",A})  -> {access,A};
	      ({"pdo",true})  -> {pdo_mapping,optional};
	      ({"pdo",false}) -> {pdo_mapping,no};
	      ({"nbmax",Max}) -> {nbmax,Max}
	   end, Entry),
    E = case lists:keysearch(nbmax, 1, Es) of
	    false ->
		{entry,Index,Es};
	    {value,V={nbmax,Max}} ->
		{entry,{Index,Max},Es--[V]}
	end,
    obj_entries(Entries,[E|Acc],Index+1);
obj_entries([],Acc,_Index) ->
    Acc.

    

