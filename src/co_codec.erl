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
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%% CANopen bit encoding.
%%%                CANopen encode bytes in a little endian fashion.
%%%                Compound data is encoded by first encoding the
%%%                elements and the concatinating the result
%%%
%%% File    : co_codec.erl
%%%
%%% Created : 11 Feb 2009 by Tony Rogvall 
%%% @end
%%%-------------------------------------------------------------------

-module(co_codec).
-include("canopen.hrl").

-export([encode/2, decode/2,
	 encode_binary/2, decode_binary/2,
	 encode_pdo/2, decode_pdo/2,
	 bitsize/1, bytesize/1]).

-compile(export_all).

-type type_spec()::
	integer() | 
	atom() | 
	{Type::integer() | atom(),  Size::integer()}.
%%--------------------------------------------------------------------
%% @doc
%% Encodes data. 
%%
%% @end
%%--------------------------------------------------------------------
-spec encode(Data::term(), Type::type_spec() | list(type_spec())) -> 
		    Bin::binary().
%% special case for top level BOOLAN, since we can not send bitstrings (yet)
encode(Data, ?BOOLEAN) ->
    encode_e(Data,?UNSIGNED8);
encode(Data, Type) ->
    encode_e(Data,Type).

%% decode/2
%%    decode(Data, Type) -> {Value, BitsTail}
%%
%%--------------------------------------------------------------------
%% @doc
%% Decoded data. 
%%
%% @end
%%--------------------------------------------------------------------
-spec decode(Bin::binary(), Type::type_spec() | list(type_spec())) -> 
		    {Value::term(), BitsTail::binary()}.

decode(Data, Type) ->
    decode_e(Data,Type).

%%--------------------------------------------------------------------
%% @doc
%% Calculates bit size for a Type
%% R14 name !!!
%% @end
%%--------------------------------------------------------------------
-spec bitsize(Type::integer() | atom()) -> 
		    Size::pos_integer().

bitsize(Type) ->
    bitsize_e(Type).

%%--------------------------------------------------------------------
%% @doc
%% Calculates byte size for a Type
%% R14 name !!!
%% @end
%%--------------------------------------------------------------------
-spec bytesize(Type::integer() | atom()) -> 
		      Size::pos_integer().

bytesize(Type) ->
    (bitsize_e(Type) + 7) bsr 3.
    
encode_e(Data, ?INTEGER8)   -> encode_signed(Data, 8);
encode_e(Data, ?INTEGER16)  -> encode_signed(Data, 16);
encode_e(Data, ?INTEGER24)  -> encode_signed(Data, 24);
encode_e(Data, ?INTEGER32)  -> encode_signed(Data, 32);
encode_e(Data, ?INTEGER40)  -> encode_signed(Data, 40);
encode_e(Data, ?INTEGER48)  -> encode_signed(Data, 48);
encode_e(Data, ?INTEGER56)  -> encode_signed(Data, 56);
encode_e(Data, ?INTEGER64)  -> encode_signed(Data, 64);
encode_e(Data, ?UNSIGNED8) -> encode_unsigned(Data, 8);
encode_e(Data, ?UNSIGNED16) -> encode_unsigned(Data, 16);
encode_e(Data, ?UNSIGNED24) -> encode_unsigned(Data, 24);
encode_e(Data, ?UNSIGNED32) -> encode_unsigned(Data, 32);
encode_e(Data, ?UNSIGNED40) -> encode_unsigned(Data, 40);
encode_e(Data, ?UNSIGNED48) -> encode_unsigned(Data, 48);
encode_e(Data, ?UNSIGNED56) -> encode_unsigned(Data, 56);
encode_e(Data, ?UNSIGNED64) -> encode_unsigned(Data, 64);
encode_e(Data, ?BOOLEAN)    -> encode_unsigned(Data, 1);
encode_e(Data, ?REAL32)     -> encode_float(Data, 32);
encode_e(Data, ?REAL64)     -> encode_float(Data, 64);
encode_e(Data, ?VISIBLE_STRING) -> list_to_binary(Data);
encode_e(Data, ?OCTET_STRING) -> iolist_to_binary(Data);
encode_e(Data, ?UNICODE_STRING) -> << <<X:16/little>> || X <- Data>>;
encode_e(Data, ?DOMAIN) -> iolist_to_binary(Data);
encode_e(Data, ?TIME_OF_DAY) ->
    encode_compound_e([Data#time_of_day.ms,0,Data#time_of_day.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]);
encode_e(Data, ?TIME_DIFFERENCE) ->
    encode_compound_e([Data#time_difference.ms,0,Data#time_difference.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]);
encode_e(Data, {Type,Size}) ->
    encode_e(Data, Type, Size);
encode_e(Data, TypeList) when is_list(TypeList) ->
    encode_compound_e(Data, TypeList);
encode_e(Data, Type) when is_atom(Type) ->
    encode_e(Data, co_lib:encode_type(Type)).

encode_e(0,    _Any,       S) -> encode_signed(0, S); %% Pad zeros ???
encode_e(Data, ?INTEGER8,  S) when S=<8  -> encode_signed(Data, S);
encode_e(Data, ?INTEGER16, S) when S=<16 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER24, S) when S=<24 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER32, S) when S=<32 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER40, S) when S=<40 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER48, S) when S=<48 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER56, S) when S=<56 -> encode_signed(Data, S);
encode_e(Data, ?INTEGER64, S) when S=<64 -> encode_signed(Data, S);
encode_e(Data, ?UNSIGNED8, S) when S=<8  -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED16,S) when S=<16 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED24,S) when S=<24 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED32,S) when S=<32 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED40,S) when S=<40 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED48,S) when S=<48 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED56,S) when S=<56 -> encode_unsigned(Data, S);
encode_e(Data, ?UNSIGNED64,S) when S=<64 -> encode_unsigned(Data, S);
encode_e(Data, ?BOOLEAN,S) when S =< 1   -> encode_unsigned(Data, S);
encode_e(Data, ?REAL32, S) when S=:=32 -> encode_float(Data, 32);
encode_e(Data, ?REAL64, S) when S=:=64 -> encode_float(Data, 64);
encode_e(Data, ?VISIBLE_STRING, S) -> encode_binary(list_to_binary(Data), S);
encode_e(Data, ?OCTET_STRING, S) -> encode_binary(list_to_binary(Data), S);
encode_e(Data, ?UNICODE_STRING, S) ->
    encode_binary(<< <<X:16/little>> || X <- Data>>, S);
encode_e(Data, ?DOMAIN, S) when is_binary(Data) -> 
    encode_binary(Data, S);
encode_e(Data, ?DOMAIN, S) when is_list(Data) -> 
    encode_binary(list_to_binary(Data), S);
encode_e(Data, Type, S) when is_atom(Type) ->
    encode_e(Data, co_lib:encode_type(Type), S).

encode_compound_e([D|Ds],[TS = {_T,_S}|TSs]) -> %% {Type, Size}
    %% io:format("encode_command_e: data ~w, ts ~w\n", [D, TS]), 
    Bits1 = encode_e(D, TS),
    Bits2 = encode_compound_e(Ds, TSs),
    concat_bits(Bits1, Bits2);
encode_compound_e([D|Ds],[S|Ss]) %% Size
  when is_integer(S) ->
    %% io:format("encode_command_e: data ~w, s ~w\n", [D, S]), 
    Bits1 = encode_binary(D,S),
    Bits2 = encode_compound_e(Ds, Ss),
    concat_bits(Bits1, Bits2);
encode_compound_e([], []) ->
    <<>>.

encode_pdo(Ds, Ts) ->
    %% io:format("encode_pdo: data ~w, ts ~w\n", [Ds, Ts]), 
    Bits = encode_compound_e(Ds,Ts),
    case bit_size(Bits) band 7 of
	0 -> Bits;
	R -> concat_bits(Bits, <<0:(8-R)>>)
    end.
    
%%
%% concat bits from A and bits from B in such a way that simulates
%% bitpacking from left to right in every byte, instead of the
%% Erlang way right to left.
%%
%% Example: A=a9,a8,a7,a6,a5,a4,a3,a2,a1,a0
%%          B=b7,b6,b5,b4,b3,b2,b1,b0
%%
%% concat_bits =>
%%                    B0                    B1                   Tail
%%          a9,a8,a7,a6,a5,a4,a3,a2 | b7,b6,b5,b4,b3,b2,a1,a0 | b1,b0
%%
%% Erlang:
%%          a9,a8,a7,a6,a5,a4,a3,a2 | a1,a0,b7,b6,b5,b4,b3,b2 | b1,b0
%% 
%%
%%
concat_bits(A, B) ->
    Am = bit_size(A),
    Ak = Am band 16#7,  %% number of tail bits
    if Ak =:= 0 ->
	    <<A/bits,B/bits>>;
       true ->
	    Al = Am bsr 3,      %% number of bytes
	    <<A1:Al/binary,A2/bits>> = A,
	    Bk = 8-Ak,          %% head B bits
	    Bn = bit_size(B),   %% all B bits
	    if Bn < Bk ->
		    <<A1/binary,B/bits,A2/bits>>;
	       true ->
		    <<B1:Bk/bits, B2/bits>> = B,
		    <<A1/binary,B1/bits,A2/bits,B2/bits>>
	    end
    end.

encode_signed(Data, Size) ->
    <<Data:Size/signed-integer-little>>.

encode_unsigned(Data, Size) ->
    <<Data:Size/unsigned-integer-little>>.
    
encode_float(Data, Size) ->
    <<Data:Size/float-little>>.

encode_binary(Data, Size) when Size > bit_size(Data) ->
    Pad = Size - bit_size(Data),
    <<Data/bits, 0:Pad>>;
encode_binary(Data, Size) ->
    <<Data:Size/bits>>.

%%
%% Decoder ->
%%   Data -> { Element, Bits }
%%
decode_e(Data, ?INTEGER8)   -> decode_signed(Data, 8);
decode_e(Data, ?INTEGER16)  -> decode_signed(Data, 16);
decode_e(Data, ?INTEGER24)  -> decode_signed(Data, 24);
decode_e(Data, ?INTEGER32)  -> decode_signed(Data, 32);
decode_e(Data, ?INTEGER40)  -> decode_signed(Data, 40);
decode_e(Data, ?INTEGER48)  -> decode_signed(Data, 48);
decode_e(Data, ?INTEGER56)  -> decode_signed(Data, 56);
decode_e(Data, ?INTEGER64)  -> decode_signed(Data, 64);
decode_e(Data, ?UNSIGNED8)  -> decode_unsigned(Data, 8);
decode_e(Data, ?UNSIGNED16) -> decode_unsigned(Data, 16);
decode_e(Data, ?UNSIGNED24) -> decode_unsigned(Data, 24);
decode_e(Data, ?UNSIGNED32) -> decode_unsigned(Data, 32);
decode_e(Data, ?UNSIGNED40) -> decode_unsigned(Data, 40);
decode_e(Data, ?UNSIGNED48) -> decode_unsigned(Data, 48);
decode_e(Data, ?UNSIGNED56) -> decode_unsigned(Data, 56);
decode_e(Data, ?UNSIGNED64) -> decode_unsigned(Data, 64);
decode_e(Data, ?BOOLEAN)    -> decode_unsigned(Data, 1);
decode_e(Data, ?REAL32)     -> decode_float(Data, 32);
decode_e(Data, ?REAL64)     -> decode_float(Data, 64);
decode_e(Data, ?VISIBLE_STRING) -> {binary_to_list(Data), <<>>};
decode_e(Data, ?OCTET_STRING)   -> {Data, <<>>};
decode_e(Data, ?UNICODE_STRING) -> {[ X || <<X:16/little>> <= Data ], <<>>};
decode_e(Data, ?DOMAIN) ->  {Data, <<>>};
decode_e(Data, ?TIME_OF_DAY) ->
    {[Ms,_,Days],Bits} =
	decode_compound_e(Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]),
    {#time_of_day { ms=Ms, days=Days }, Bits};
decode_e(Data, ?TIME_DIFFERENCE) ->
    {[Ms,_,Days],Bits} =
	decode_compound_e(Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]),
    {#time_difference { ms = Ms, days=Days }, Bits};
decode_e(Data, {Type,Size}) ->
    decode_e(Data, Type, Size);
decode_e(Data, TypeList) when is_list(TypeList) ->
    decode_compound_e(Data, TypeList);
decode_e(Data, Type) when is_atom(Type) ->
    decode_e(Data, co_lib:encode_type(Type)).

%% decode parts of data types
decode_e(Data, ?INTEGER8,  S) when S=<8 -> decode_signed(Data, S);
decode_e(Data, ?INTEGER16, S) when S=<16 -> decode_signed(Data, S);
decode_e(Data, ?INTEGER24, S) when S=<24 -> decode_signed(Data, S);
decode_e(Data, ?INTEGER32, S) when S=<32-> decode_signed(Data, S);
decode_e(Data, ?INTEGER40, S) when S=<40-> decode_signed(Data, S);
decode_e(Data, ?INTEGER48, S) when S=<48-> decode_signed(Data, S);
decode_e(Data, ?INTEGER56, S) when S=<56-> decode_signed(Data, S);
decode_e(Data, ?INTEGER64, S) when S=<64-> decode_signed(Data, S);
decode_e(Data, ?UNSIGNED8, S) when S=<8-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED16,S) when S=<16-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED24,S) when S=<24-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED32,S) when S=<32-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED40,S) when S=<40-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED48,S) when S=<48-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED56,S) when S=<56-> decode_unsigned(Data, S);
decode_e(Data, ?UNSIGNED64,S) when S=<64-> decode_unsigned(Data, S);
decode_e(Data, ?BOOLEAN,S)    when S=<1 -> decode_unsigned(Data, S);
decode_e(Data, ?REAL32, S) when S=:=32 -> decode_float(Data, 32);
decode_e(Data, ?REAL64, S) when S=:=64 -> decode_float(Data, 64);
decode_e(Data, ?VISIBLE_STRING, S) -> 
    {X, Y} = decode_binary(Data, S),
    {binary_to_list(X), Y};
decode_e(Data, ?OCTET_STRING, S) ->
    decode_binary(Data, S);
decode_e(Data, ?UNICODE_STRING, S) ->
    decode_binary(<< <<X:16/little>> || X <- Data>>, S);
decode_e(Data, ?DOMAIN, S) ->
    decode_binary(Data, S);
decode_e(Data, Type, S) when is_atom(Type) ->
    decode_e(Data, co_lib:encode_type(Type), S).

decode_compound_e(Data,[TS = {_T,_S}|TSs]) -> %% {Type, Size}
    %% io:format("decode_compound_e: data ~w, ts ~p, tss ~p\n", [Data, TS, TSs]), 
    Sz = bitsize_e(TS),
    {DataT,DataTs} = split_bits(Data,Sz),
    {D,<<>>} = decode(DataT,TS),
    {Ds,Data1} = decode_compound_e(DataTs,TSs),
    {[D|Ds], Data1};
decode_compound_e(Data,[S|Ss]) ->%% Size
    %% io:format("decode_compound_e: data ~w, s ~p, ss ~p\n", [Data, S, Ss]), 
    {DataS,DataSs} = split_bits(Data,S),
    {D,<<>>} = decode_binary(DataS,S),
    {Ds,Data1} = decode_compound_e(DataSs,Ss),
    {[D|Ds], Data1};
decode_compound_e(Data, []) ->
    {[], Data}.

%%
%% RPDO decoding. 
%% FIXME: handle error cases, Data to small etc.
%%
decode_pdo(Data, Ts) ->
    %% io:format("decode_pdo: data ~w, ts ~w\n", [Data, Ts]), 
    Sz = bitsize_e(Ts),
    {Data1,Data2} = split_bits(Data,Sz),
    {Ds,<<>>} = decode_compound_e(Data1,Ts),
    {Ds,Data2}.

%%
%% split Bits in {A,B} where bit_size(A) =< Sz
%% using CANopen encoding rules (little endian bit packing)
%%
split_bits(Bits, -1) ->
    {Bits, <<>>};
split_bits(Bits, Sz) when is_bitstring(Bits), Sz =< bit_size(Bits) ->
    N = bit_size(Bits),
    Ak = Sz band 16#7,  %% number of tail bits
    if Ak =:= 0 ->
	    <<A:Sz/bits, B/bits>> = Bits,
	    {A,B};
       true ->
	    Al = Sz bsr 3,  %% number of bytes
	    Bk = 8 - Ak,    %% head bits of B
	    Bn = N - Sz,    %% All B bits
	    if Bn < Bk ->
		    <<A1:Al/binary,B:Bn/bits,A2:Ak/bits>> = Bits,
		    {<<A1/bits,A2/bits>>, B};
	       true ->
		    <<A1:Al/binary,B1:Bk/bits,A2:Ak/bits,B2/bits>> = Bits,
		    {<<A1/bits,A2/bits>>, <<B1/bits,B2/bits>>}
	    end
    end.

decode_signed(Data, Size)   -> 
    <<X:Size/signed-integer-little, Bits/bits>> = Data,
    {X, Bits}.

decode_unsigned(Data, Size) -> 
    <<X:Size/unsigned-integer-little, Bits/bits>> = Data,
    {X, Bits}.
    
decode_float(Data, Size) -> 
    <<X:Size/float-little, Bits/bits>> = Data,
    {X, Bits}.

decode_binary(Data, -1) ->
    {Data, <<>>};
decode_binary(Data, Size) ->
    <<X:Size/bits, Bits/bits>> = Data,
    {X, Bits}.

%% Calculate the the bit size of a type
bitsize_e(?INTEGER8)   -> 8;
bitsize_e(?INTEGER16)  -> 16;
bitsize_e(?INTEGER24)  -> 24;
bitsize_e(?INTEGER32)  -> 32;
bitsize_e(?INTEGER40)  -> 40;
bitsize_e(?INTEGER48)  -> 48;
bitsize_e(?INTEGER56)  -> 56;
bitsize_e(?INTEGER64)  -> 64;
bitsize_e(?UNSIGNED8)  -> 8;
bitsize_e(?UNSIGNED16) -> 16;
bitsize_e(?UNSIGNED24) -> 24;
bitsize_e(?UNSIGNED32) -> 32;
bitsize_e(?UNSIGNED40) -> 40;
bitsize_e(?UNSIGNED48) -> 48;
bitsize_e(?UNSIGNED56) -> 56;
bitsize_e(?UNSIGNED64) -> 64;
bitsize_e(?REAL32)     -> 32;
bitsize_e(?REAL64)     -> 64;
bitsize_e(?VISIBLE_STRING) -> 0;
bitsize_e(?OCTET_STRING)  -> 0;
bitsize_e(?UNICODE_STRING) -> 0;
bitsize_e(?DOMAIN) -> 0;
bitsize_e(?TIME_OF_DAY) -> 48;
bitsize_e(?TIME_DIFFERENCE) -> 48;
bitsize_e({_Type,Size}) -> Size;
bitsize_e(TypeList) when is_list(TypeList) ->
    bitsize_compound_e(TypeList);
bitsize_e(Type) when is_atom(Type) ->
    bitsize_e(co_lib:encode_type(Type)).

bitsize_compound_e([{_T,S}|TSs]) -> %% {Type, Size}
    S + bitsize_compound_e(TSs);
bitsize_compound_e([S|Ss]) -> %% Size
    S + bitsize_compound_e(Ss);
bitsize_compound_e([]) ->
    0.


