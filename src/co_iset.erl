%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% Integer Set operations.
%%
%% Representation:<br/>
%%  List of interval and points.<br/>
%%
%%  Points:<br/>
%%       A sorted list of values and/or closed intervals where
%%       intervals are represented as pairs with as {Low,High}.
%%       It may also be the empty list if no specific points are
%%       given even though Max and Min has values.<br/>
%%
%%  operations:
%% <ul>
%%       <li>new()</li>
%%       <li>new(Points)</li>
%%       <li>new(Min, Max)</li>
%%       <li>new(Min, Max, Points)</li>
%%       <li>intersect(D1, D2)</li>
%%       <li>difference(D1,D2)</li>
%%       <li>union(D1, D2)</li>
%%       <li>is_equal(D1, D2)</li>
%%       <li>is_subset(D1, D2)</li>
%%       <li>is_psubset(D1,D2)</li>
%%       <li>sizeof(D)</li>
%%       <li>member(N, D)</li>
%%       <li>first(D)</li>
%%       <li>last(D)</li>
%%       <li>write(Device, D)</li>
%% </ul>
%%%
%%% File: co_iset.erl<br/>
%%% Created:  26 Jan 2006 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(co_iset).

%% @private

-export([new/0, new/1, new/2]).
-export([member/2, sizeof/1, is_equal/2, is_subset/2, is_psubset/2]).
-export([first/1, last/1]).
-export([format/1]).

-export([union/2, intersect/2, difference/2]).
-export([add/2, subtract/2, multiply/2, divide/2, reminder/2, negate/1]).
-export([map/2,fold/3, foreach/2]).

-import(lists, [reverse/1]).

-define(iv(A,B), {A,B}).

%%
%% Create a new iset
%%
new() ->  
    [].

new(I) when is_integer(I) ->  
    [I];
new({I,I}) when is_integer(I) -> 
    [I];
new({I,J}) when is_integer(I),is_integer(J), I<J ->  
    [{I,J}];
new(Is) when is_list(Is) -> 
    from_list(Is).

new(I,I) when is_integer(I) ->
    [I];
new(I,J) when is_integer(I),is_integer(J),I < J -> 
    [{I, J}].
%%
%% List to iset
%%
from_list([]) ->
    [];
from_list(Is) when is_list(Is) ->
    [H|T] = lists:sort(Is),
    from_list(H,H,T,[]).

from_list(L,H,[H|T],Acc) ->
    from_list(L,H,T,Acc);
from_list(L,H,[I|T],Acc) when I==H+1 ->
    from_list(L,H+1,T,Acc);
from_list(L,H,[J|T],Acc) ->
    if L == H ->
	    from_list(J,J,T,[L|Acc]);
       true ->
	    from_list(J,J,T,[{L,H}|Acc])
    end;
from_list(L,H,[],Acc) ->
    if L == H ->
	    reverse([L|Acc]);
       true ->
	    reverse([{L,H}|Acc])
    end.

%%
%% memberof(N, Domain)
%%
%% returns:
%%   true if N is a member of Domain
%%   false otherwise
%%
member(N, [N | _]) -> true;
member(N, [X | _]) when is_integer(X), N < X -> false;
member(N, [X | L]) when is_integer(X), N > X -> member(N,L);
member(N, [?iv(X0,X1)|_]) when N >= X0, N =< X1 -> true;
member(N, [?iv(X0,_X1) | _]) when N < X0 -> false;
member(N, [?iv(_X0,X1) | L]) when N  > X1 -> member(N, L);
member(_N, []) -> false.

%%
%% Calculate size of domain
%%
%% returns:
%%       0 if empty set
%%       N number of members
%%  
sizeof(L) ->
    sizeof(L, 0).

sizeof([V | L], N) when is_integer(V) -> sizeof(L, N+1);
sizeof([?iv(Low,High)|L], N) -> sizeof(L, N+(High-Low)+1);
sizeof([], N) -> N.

%%
%% Get maximum and minimum value
%%
first([?iv(V,_) | _]) -> V;
first([V | _]) -> V.

last(D) ->
    case lists:reverse(D) of
	[?iv(_,V) | _] -> V;
	[V | _]     -> V
    end.

%%
%% Fold
%%

fold(Fun,Acc,[D|Ds]) when is_integer(D) ->
    fold(Fun,Fun(D,Acc),Ds);
fold(Fun,Acc,[?iv(L,H)|Ds]) ->
    fold_range(Fun,Acc,L,H,Ds);
fold(_Fun,Acc,[]) ->
    Acc.

fold_range(Fun,Acc,I,N,Ds) when I > N ->
    fold(Fun,Acc,Ds);
fold_range(Fun,Acc,I,N,Ds) ->
    fold_range(Fun,Fun(I,Acc),I+1,N,Ds).

%%
%% Map over iset
%%
map(_Fun, []) ->
    [];
map(Fun, [D|Ds]) when is_integer(D) ->
    [Fun(D) | map(Fun,Ds)];
map(Fun, [?iv(L,H)|Ds]) ->
    map_range(Fun, L, H, Ds).

map_range(Fun, I, N, Ds) when I > N ->
    map(Fun, Ds);
map_range(Fun, I, N, Ds) ->
    [Fun(I) | map_range(Fun,I+1,N,Ds)].

%%
%% Foreach
%%
foreach(_Fun, []) ->
    true;
foreach(Fun, [D|Ds]) when is_integer(D) ->
    Fun(D),
    foreach(Fun,Ds);
foreach(Fun, [?iv(L,H)|Ds]) ->
    foreach_range(Fun, L, H, Ds).

foreach_range(Fun, I, N, Ds) when I > N ->
    foreach(Fun, Ds);
foreach_range(Fun, I, N, Ds) ->
    Fun(I),
    foreach_range(Fun,I+1,N,Ds).

%%
%% Utilities:
%%
%% value(A,B)   make A-B a domain value
%% min_max(A,B) returns {Min,Max}
%%
low(?iv(L,_)) -> L;
low(L) -> L.

high(?iv(_,H)) -> H;
high(H) -> H.

range(R=?iv(_,_)) -> R;
range(L) -> {L,L}.

value(N,N) -> N;
value(L,H) -> ?iv(L,H).

%%
%% Check if two domains are equal
%%
is_equal(D, D) -> true;
is_equal(_, _) -> false.

%%
%% Check if D1 is a subset D2
%%
is_subset(D1,D2) ->
    case intersect(D1, D2) of
	D1 -> true;
	_  -> false
    end.

%%
%% Check if D1 is a proper subset of D2
%%
is_psubset(D1, D2) ->
    case intersect(D1, D2) of
	D1 ->
	    case difference(D2,D1) of
		[] -> false;
		_  -> true
	    end;
	_ -> false
    end.

%%
%% insert(Point, Domain)
%%
%% description:
%%   Creates a domain given a list of integers and
%%   intervals and simplifies them as much as possible
%%
%% returns:
%%   Domain
%%

insert([Value | List], Domain) ->
    insert(List, union(new(Value), Domain));
insert([], Domain) ->
    Domain.

%%
%% union(Domain1, Domain2)
%%
%% description:
%%  Create a union of two domains
%% 
%%
union(D,D) -> D;
union(D1,D2) ->
    union(D1,D2,new()).

union(D, [], U) -> 
    lists:reverse(U,D);
union([],D, U)  ->
    lists:reverse(U,D);
union(S1=[D1 | D1s], S2=[D2 | D2s], U) ->
    {Min1,Max1} = range(D1),
    {Min2,Max2} = range(D2),
    if Min2 == Max1+1 ->
	    union(D1s,[value(Min1,Max2) | D2s], U);
       Min1 == Max2+1 ->
	    union([value(Min2,Max1)|D1s], D2s, U);
       Min2 > Max1 ->
	    union(D1s, S2, [D1|U]);
       Min1 > Max2 ->
	    union(S1, D2s, [D2|U]);
       Max1 > Max2 ->
	    union([value(erlang:min(Min1,Min2),Max1)|D1s], D2s, U);
       true ->
	    union(D1s,[value(erlang:min(Min1,Min2),Max2)|D2s], U)
    end.

%%
%% intersect(Domain1, Domain2)
%%
%% description:
%%   Create the intersection between two domains
%%
%%

intersect([], _) -> [];
intersect(_, []) -> [];
intersect(D1, D2) ->
    intersect(D1, D2, new()).

intersect(_D, [], I) -> reverse(I);
intersect([], _D, I) -> reverse(I);
intersect(S1=[D1|D1s], S2=[D2|D2s], I) ->
    {Min1,Max1} = range(D1),
    {Min2,Max2} = range(D2),
    if Min2 > Max1 ->
 	    intersect(D1s, S2, I);
       Min1 > Max2 ->
	    intersect(S1, D2s, I);
       Max1<Max2 ->
	    intersect(D1s,S2,
		      [value(erlang:max(Min1,Min2),Max1)|I]);
       true ->
	    intersect(S1, D2s,
		      [value(erlang:max(Min1,Min2),Max2)|I])
    end.

%%
%% difference(D1,D2)
%%
%% returns:
%%   The difference between D1 and D2, by removeing the
%%   values in D2 from D1 i.e D1 - D2.
%%   
%%

difference(D, []) -> D;
difference([], _) -> [];
difference(D1, D2) ->
    difference(D1,D2,new()).

difference(D1s,[],Diff) -> 
    lists:reverse(Diff,D1s);
difference(D1s,[D2|D2s],Diff) ->
    Min2 = low(D2),
    Max2 = high(D2),
    ddiff(D1s, Min2, Max2, D2, D2s, Diff).

ddiff([], _Min2, _Max2, _D2, _D2s, Diff) ->
    reverse(Diff);
ddiff([D1 | D1s], Min2, Max2, D2, D2s, Diff) ->
    {Min1,Max1} = range(D1),
    ddiffer(Min1, Max1, Min2, Max2, D1, D2, D1s,D2s,Diff).

ddiffer(Min1,Max1,Min2,Max2,D1,D2,D1s,D2s,Diff) ->
    if Min2 > Max1 ->
	    ddiff(D1s, Min2, Max2, D2, D2s, [D1 | Diff]);
       Min1 > Max2 ->
	    difference([D1 | D1s], D2s, Diff);
       Min1<Min2 ->
	    D = value(Min1, Min2-1),
	    NewD1 = value(Min2, Max1),
	    ddiffer(Min2, Max1, Min2, Max2, 
		    NewD1, D2, D1s, D2s, [D|Diff]);
       Max1 > Max2 ->
	    NewD1 = value(Max2+1, Max1),
	    ddiffer(Max2+1, Max1, Min2, Max2, 
		    NewD1, D2, D1s, D2s, Diff);
       true ->
	    ddiff(D1s, Min2, Max2, D2, D2s, Diff)
    end.

%%
%% Arithmetic in universe
%%
%% negate(A)      Integer negate values in domain A
%% add(A,B)       Integer add of values in domains A and B
%% subtract(A,B)  Integer subtract of values in domains A and B
%% multiply(A,B)  Integer multiplication of values in domains A and B
%% divide(A,B)    Integer division of values in domain A with values in B
%% reminder(A,B)  Integer remainder of values in domain A with values in B
%%

%%
%% Negate domain
%% returns:
%%  { x | x = -a, a in A}
%%
negate(A) ->
    negate(A, new()).

negate([?iv(I,J) | As], Neg) ->
    negate(As, [value(-J,-I)|Neg]);
negate([I | As], Neg) ->
    negate(As, [-I|Neg]);
negate([], Neg) ->
    Neg.

%%
%% Add of domains
%% returns:
%%   { x | x = a+b, a in A, b in B }
%%
%%
add(As, Bs) ->
    fold(fun(A,S) ->
		 {LA,HA} = range(A),
		 S1 = lists:map(
			fun(B) ->
				{LB,HB} = range(B),
				{LA+LB,HA+HB}
			end, Bs),
		 insert(S1, S)
	 end, new(), As).

%%
%% Subtract of domains
%% returns:
%%   { x | x = a-b, a in A, b in B }
%%
%%
subtract(As, Bs) ->
    fold(fun(A,S) ->
		 {LA,HA} = range(A),
		 S1 = lists:map(
			fun(B) ->
				{LB,HB} = range(B),
				{HA-HB,LA-LB}
			end, Bs),
		 insert(S1, S)
	 end, new(), As).

%%
%% Product of domains
%% returns:
%%   { x | x = a*b, a in A, b in B }
%%
multiply(As, Bs) ->
    fold(fun(A,P) ->
		 Q = from_list(map(fun(B) -> A*B end, Bs)),
		 union(P,Q)
	 end, new(), As).

%%
%% Divide of domains
%% returns:
%%   { x | x = a div b, a in A, b in B }
%%
divide(As, Bs) ->
    fold(fun(A,P) ->
		 Q = from_list(map(fun(B) -> A div B end, Bs)),
		 union(P,Q)
	 end, new(), As).
    
%%
%% Reminder of domains
%% returns:
%%   { x | x = a rem b, a in A, b in B }
%%
reminder(As, Bs) ->
    fold(fun(A,P) ->
		 Q = from_list(map(fun(B) -> A rem B end, Bs)),
		 union(P,Q)
	 end, new(), As).

%%
%% format(D)
%%
%% output a domain
%%
format([]) -> "{}";
format([D]) -> ["{", format1(D), "}"];
format([D|Ds]) -> 
    ["{", format1(D), lists:map(fun(D1) -> [",",format1(D1)] end, Ds), "}"].

format1({Low,High}) -> [$[,integer_to_list(Low),"..",integer_to_list(High),$]];
format1(Value)      -> [integer_to_list(Value)].

