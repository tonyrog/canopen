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
	 bitsize/1, bytesize/1]).

-compile(export_all).
%%--------------------------------------------------------------------
%% @doc
%% Encodes data. 
%%
%% @end
%%--------------------------------------------------------------------
-spec encode(Data::term(), Type::integer() | atom()) -> 
		    Bin::binary().

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
-spec decode(Bin::binary(), Type::integer() | atom()) -> 
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

encode_compound_e([D|Ds],[T|Ts]) ->
    Bits1 = encode_e(D, T),
    Bits2 = encode_compound_e(Ds, Ts),
    concat_bits(Bits1, Bits2);
encode_compound_e([], []) ->
    <<>>.

%% encode a complete PDO frame (possibly too big)
encode_pdo(Ds, Ts) ->
    Bits = encode_compound_e(Ds,Ts),
    case bit_size(Bits) band 7 of
	0 -> Bits;
	R -> concat_bits(Bits, <<0:(8-R)>>)
    end.
    
%%
%% concat bits from A and bits from B in such a way that:
%% A = a0...am-1,  B = b0 .. bn-1  AB = a0..am-1,b0...bn-1
%% the bits are formatted in a little endian way so that
%% AB = a7,a6..a0,a15,..,a8,..
%%
%% The idea is to split A in (A1,A2) where A1 contains
%% the bytes and A2 the tail bits. The split B in (B1,B2)
%% where B1 is the head bits (8-sz(A1)) and B2 is the tail bits
%% then combine as: A1,B1,A2,B2
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
decode_e(Data, ?REAL32, S) when S==32 -> decode_float(Data, 32);
decode_e(Data, ?REAL64, S) when S==64 -> decode_float(Data, 64);
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

decode_compound_e(Data,[T|Ts]) ->
    Sz = bitsize_e(T),
    {DataT,DataTs} = split_bits(Data,Sz),
    {D,<<>>} = decode(DataT,T),
    {Ds,Data1} = decode_compound_e(DataTs,Ts),
    {[D|Ds], Data1};
decode_compound_e(Data, []) ->
    {[], Data}.

%%
%% RPDO decoding. 
%% FIXME: handle error cases, Data to small etc.
%%
decode_pdo(Data, Ts) ->
    Sz = bitsize_e(Ts),
    {Data1,Data2} = split_bits(Data,Sz),
    {Ds,<<>>} = decode_compound_e(Data1,Ts),
    {Ds,Data2}.

%%
%% split Bits in {A,B} where bit_size(A) =< Sz
%% using CANopen encoding rules (little endian bit packing)
%%
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

bitsize_compound_e([{_T,Size}|Ts]) ->
    Size + bitsize_compound_e(Ts);
bitsize_compound_e([T|Ts]) ->
    case bitsize_e(T) of
	0 -> 0;
	Size -> Size + bitsize_compound_e(Ts)
    end;
bitsize_compound_e([]) ->
    0.


