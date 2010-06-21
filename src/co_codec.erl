%%% File    : co_codec.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : CANopen bit encoding
%%%                CANopen encode bytes in a little endian fashion.
%%%                Compound data is encoded by first encoding the
%%%                elements and the concatinating the result
%%% Created : 11 Feb 2009 by Tony Rogvall <tony@rogvall.se>

-module(co_codec).
-include("../include/canopen.hrl").

-compile(export_all).

%% encode/2
%%   encode(Data, Type) :: Binary
%%
encode(Data, Type) ->
    encode_e(Data,Type,little).

encode(Data, Type, Endian) ->
    encode_e(Data,Type, Endian).

%% decode/2
%%    decode(Data, Type) -> {Value, BitsTail}
%%
decode(Data, Type) ->
    decode_e(Data,Type,little).

decode(Data, Type, Endian) ->
    decode_e(Data,Type, Endian).

%%  bitsize/1
%%    bitsize(Type) :: non-negative
%%
bitsize(Type) ->
    bitsize_e(Type).

%%  bytesize/1
%%    bytesize(Type) :: non-negative 
%%
bytesize(Type) ->
    (bitsize_e(Type) + 7) bsr 3.
    

encode_e(Data, ?INTEGER8, E)   -> encode_signed(Data, 8, E);
encode_e(Data, ?INTEGER16, E)  -> encode_signed(Data, 16, E);
encode_e(Data, ?INTEGER24, E)  -> encode_signed(Data, 24, E);
encode_e(Data, ?INTEGER32, E)  -> encode_signed(Data, 32, E);
encode_e(Data, ?INTEGER40, E)  -> encode_signed(Data, 40, E);
encode_e(Data, ?INTEGER48, E)  -> encode_signed(Data, 48, E);
encode_e(Data, ?INTEGER56, E)  -> encode_signed(Data, 56, E);
encode_e(Data, ?INTEGER64, E)  -> encode_signed(Data, 64, E);
encode_e(Data, ?UNSIGNED8,  E) -> encode_unsigned(Data, 8, E);
encode_e(Data, ?UNSIGNED16, E) -> encode_unsigned(Data, 16, E);
encode_e(Data, ?UNSIGNED24, E) -> encode_unsigned(Data, 24, E);
encode_e(Data, ?UNSIGNED32, E) -> encode_unsigned(Data, 32, E);
encode_e(Data, ?UNSIGNED40, E) -> encode_unsigned(Data, 40, E);
encode_e(Data, ?UNSIGNED48, E) -> encode_unsigned(Data, 48, E);
encode_e(Data, ?UNSIGNED56, E) -> encode_unsigned(Data, 56, E);
encode_e(Data, ?UNSIGNED64, E) -> encode_unsigned(Data, 64, E);
encode_e(Data, ?REAL32, E)     -> encode_float(Data, 32, E);
encode_e(Data, ?REAL64, E)     -> encode_float(Data, 64, E);
encode_e(Data, ?VISIBLE_STRING, _E) -> list_to_binary(Data);
encode_e(Data, ?OCTET_STRING, _E) -> list_to_binary([Data]);
encode_e(Data, ?UNICODE_STRING,little) -> << <<X:16/little>> || X <- Data>>;
encode_e(Data, ?UNICODE_STRING,big) -> << <<X:16/big>> || X <- Data>>;
encode_e(Data, ?DOMAIN, _E) when is_binary(Data) -> Data;
encode_e(Data, ?DOMAIN, _E) when is_list(Data) -> list_to_binary(Data);
encode_e(Data, ?TIME_OF_DAY,E) ->
    encode_compound_e([Data#time_of_day.ms,0,Data#time_of_day.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], E);
encode_e(Data, ?TIME_DIFFERENCE,E) ->
    encode_compound_e([Data#time_difference.ms,0,Data#time_difference.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], E);
encode_e(Data, {Type,Size}, E) ->
    encode_e(Data, Type, Size, E);
encode_e(Data, TypeList, E) when is_list(TypeList) ->
    encode_compound_e(Data, TypeList, E);
encode_e(Data, Type, E) when is_atom(Type) ->
    encode_e(Data, canopen:encode_type(Type), E).


encode_e(Data, ?INTEGER8,  S, E) when S=<8 -> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER16, S, E) when S=<16 -> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER24, S, E) when S=<24 -> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER32, S, E) when S=<32-> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER40, S, E) when S=<40-> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER48, S, E) when S=<48-> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER56, S, E) when S=<56-> encode_signed(Data, S, E);
encode_e(Data, ?INTEGER64, S, E) when S=<64-> encode_signed(Data, S, E);
encode_e(Data, ?UNSIGNED8, S, E) when S=<8-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED16,S, E) when S=<16-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED24,S, E) when S=<24-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED32,S, E) when S=<32-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED40,S, E) when S=<40-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED48,S, E) when S=<48-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED56,S, E) when S=<56-> encode_unsigned(Data, S, E);
encode_e(Data, ?UNSIGNED64,S, E) when S=<64-> encode_unsigned(Data, S, E);
encode_e(Data, ?REAL32, S, E) when S==32 -> encode_float(Data, 32, E);
encode_e(Data, ?REAL64, S, E) when S==64 -> encode_float(Data, 64, E);
encode_e(Data, ?VISIBLE_STRING, S, _E) -> encode_binary(list_to_binary(Data), S);
encode_e(Data, ?OCTET_STRING, S, _E) -> encode_binary(list_to_binary(Data), S);
encode_e(Data, ?UNICODE_STRING, S, little) ->
    encode_binary(<< <<X:16/little>> || X <- Data>>, S);
encode_e(Data, ?UNICODE_STRING, S, big) -> 
    encode_binary(<< <<X:16/little>> || X <- Data>>, S);
encode_e(Data, ?DOMAIN, S, _E) when is_binary(Data) -> 
    encode_binary(Data, S);
encode_e(Data, ?DOMAIN, S, _E) when is_list(Data) -> 
        encode_binary(list_to_binary(Data), S);
encode_e(Data, Type, S, E) when is_atom(Type) ->
    encode_e(Data, canopen:encode_type(Type), S, E).

encode_compound_e(Ds, Ts, little) ->
    Bin = encode_compound_little(Ds, Ts),
    %% pad to bytes to front and reverse
    BitSize = bit_size(Bin),
    Pad = (8 - (BitSize rem 8)) rem 8,
    Size = BitSize + Pad,
    <<X:Size>> = <<0:Pad, Bin/bits>>,
    <<X:Size/little>>;
encode_compound_e(Ds, Ts, big) ->
    Bin = encode_compound_big(Ds, Ts),
    %% pad to bytes to front and reverse
    BitSize = bit_size(Bin),
    Pad = (8 - (BitSize rem 8)) rem 8,
    <<Bin/bits, 0:Pad>>.

%% build big enidan components reversed (later reverse the bytes)
encode_compound_little([D|Ds],[T|Ts]) ->
    Bits1 = encode_compound_little(Ds, Ts),
    Bits2 = encode_e(D, T, big),
    <<Bits1/bits, Bits2/bits >>;
encode_compound_little([], []) ->
    <<>>.

%% build big enidan components
encode_compound_big([D|Ds],[T|Ts]) ->
    Bits1 = encode_e(D, T, big),
    Bits2 = encode_compound_big(Ds, Ts),
    <<Bits1/bits,Bits2/bits>>;
encode_compound_big([], []) ->
    <<>>.

encode_signed(Data, Size, little)   -> <<Data:Size/signed-integer-little>>;
encode_signed(Data, Size, big)      -> <<Data:Size/signed-integer-big>>.

encode_unsigned(Data, Size, little) -> <<Data:Size/unsigned-integer-little>>;
encode_unsigned(Data, Size, big)    -> <<Data:Size/unsigned-integer-big>>.
    
encode_float(Data, Size, little)    -> <<Data:Size/float-little>>;
encode_float(Data, Size, big)       -> <<Data:Size/float-big>>.

encode_binary(Data, Size) -> <<Data:Size/bits>>.
%%
%% Decoder ->
%%   Data -> { Element, Bits }
%%
decode_e(Data, ?INTEGER8, E)   -> decode_signed(Data, 8, E);
decode_e(Data, ?INTEGER16, E)  -> decode_signed(Data, 16, E);
decode_e(Data, ?INTEGER24, E)  -> decode_signed(Data, 24, E);
decode_e(Data, ?INTEGER32, E)  -> decode_signed(Data, 32, E);
decode_e(Data, ?INTEGER40, E)  -> decode_signed(Data, 40, E);
decode_e(Data, ?INTEGER48, E)  -> decode_signed(Data, 48, E);
decode_e(Data, ?INTEGER56, E)  -> decode_signed(Data, 56, E);
decode_e(Data, ?INTEGER64, E)  -> decode_signed(Data, 64, E);
decode_e(Data, ?UNSIGNED8,  E) -> decode_unsigned(Data, 8, E);
decode_e(Data, ?UNSIGNED16, E) -> decode_unsigned(Data, 16, E);
decode_e(Data, ?UNSIGNED24, E) -> decode_unsigned(Data, 24, E);
decode_e(Data, ?UNSIGNED32, E) -> decode_unsigned(Data, 32, E);
decode_e(Data, ?UNSIGNED40, E) -> decode_unsigned(Data, 40, E);
decode_e(Data, ?UNSIGNED48, E) -> decode_unsigned(Data, 48, E);
decode_e(Data, ?UNSIGNED56, E) -> decode_unsigned(Data, 56, E);
decode_e(Data, ?UNSIGNED64, E) -> decode_unsigned(Data, 64, E);
decode_e(Data, ?REAL32, E)     -> decode_float(Data, 32, E);
decode_e(Data, ?REAL64, E)     -> decode_float(Data, 64, E);
decode_e(Data, ?VISIBLE_STRING, _E) -> {binary_to_list(Data), <<>>};
decode_e(Data, ?OCTET_STRING, _E) -> {Data, <<>>};
decode_e(Data, ?UNICODE_STRING,little) ->
    {[ X || <<X:16/little>> <= Data ], <<>>};
decode_e(Data, ?UNICODE_STRING,big) ->
    {[ X || <<X:16/big>> <= Data ], <<>>};
decode_e(Data, ?DOMAIN, _E) when is_binary(Data) -> 
    {Data, <<>>};
decode_e(Data, ?DOMAIN, _E) when is_list(Data) -> 
    {list_to_binary(Data), <<>>};
decode_e(Data, ?TIME_OF_DAY,E) ->
    {[Ms,_,Days],Bits} =
	decode_compound_e(Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], E),
    {#time_of_day { ms=Ms, days=Days }, Bits};
decode_e(Data, ?TIME_DIFFERENCE,E) ->
    {[Ms,_,Days],Bits} =
	decode_compound_e(Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], E),
    {#time_difference { ms = Ms, days=Days }, Bits};
decode_e(Data, {Type,Size}, E) ->
    decode_e(Data, Type, Size, E);
decode_e(Data, TypeList, E) when is_list(TypeList) ->
    decode_compound_e(Data, TypeList, E);
decode_e(Data, Type, E) when is_atom(Type) ->
    decode_e(Data, canopen:encode_type(Type), E).

%% decode parts of data types
decode_e(Data, ?INTEGER8,  S, E) when S=<8 -> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER16, S, E) when S=<16 -> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER24, S, E) when S=<24 -> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER32, S, E) when S=<32-> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER40, S, E) when S=<40-> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER48, S, E) when S=<48-> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER56, S, E) when S=<56-> decode_signed(Data, S, E);
decode_e(Data, ?INTEGER64, S, E) when S=<64-> decode_signed(Data, S, E);
decode_e(Data, ?UNSIGNED8, S, E) when S=<8-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED16,S, E) when S=<16-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED24,S, E) when S=<24-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED32,S, E) when S=<32-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED40,S, E) when S=<40-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED48,S, E) when S=<48-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED56,S, E) when S=<56-> decode_unsigned(Data, S, E);
decode_e(Data, ?UNSIGNED64,S, E) when S=<64-> decode_unsigned(Data, S, E);
decode_e(Data, ?REAL32, S, E) when S==32 -> decode_float(Data, 32, E);
decode_e(Data, ?REAL64, S, E) when S==64 -> decode_float(Data, 64, E);
decode_e(Data, ?VISIBLE_STRING, S, _E) -> decode_binary(list_to_binary(Data), S);
decode_e(Data, ?OCTET_STRING, S, _E) -> decode_binary(list_to_binary(Data), S);
decode_e(Data, ?UNICODE_STRING, S, little) ->
    decode_binary(<< <<X:16/little>> || X <- Data>>, S);
decode_e(Data, ?UNICODE_STRING, S, big) -> 
    decode_binary(<< <<X:16/little>> || X <- Data>>, S);
decode_e(Data, ?DOMAIN, S, _E) when is_binary(Data) -> 
    decode_binary(Data, S);
decode_e(Data, ?DOMAIN, S, _E) when is_list(Data) -> 
        decode_binary(list_to_binary(Data), S);
decode_e(Data, Type, S, E) when is_atom(Type) ->
    decode_e(Data, canopen:encode_type(Type), S, E).

    

decode_compound_e(Data, Ts, little) ->
    Bits = bitsize_e(Ts),
    Pad  = (8 - (Bits rem 8)) rem 8,
    Bits8 = (Bits + Pad),
    %% Bytes = Bits8 bsr 3,
    <<X:Bits8, Data2/binary>> = Data,
    <<_:Pad, Data1/bits>> = <<X:Bits8/little>>,  %% reverse and skip pad
    {Ds,_} = decode_compound_little(Data1, Ts),
    {Ds, Data2};
decode_compound_e(Data, Ts, big) ->
    Bits = bitsize_e(Ts),
    Bytes = (Bits + 7) bsr 3,
    <<Data1:Bytes/binary, Data2/binary>> = Data,
    {Ds, _} = decode_compound_big(Data1, Ts),
    {Ds, Data2}.

decode_compound_little(Data,[T]) ->
    {X, Data1} = decode_e(Data, T, big),
    {[X], Data1};
decode_compound_little(Data,[T|Ts]) ->
    {Xs, Data1} = decode_compound_little(Data, Ts),
    {X, Data2} = decode_e(Data1, T, big),
    {[X|Xs],Data2};
decode_compound_little(Data, []) ->
    {[], Data}.


decode_compound_big(Data,[T|Ts]) ->
    {X, Data1} = decode_e(Data, T, big),
    {Xs, Data2} = decode_compound_big(Data1, Ts),
    {[X|Xs], Data2};
decode_compound_big(Data, []) ->
    {[], Data}.


decode_signed(Data, Size, little)   -> 
    <<X:Size/signed-integer-little, Bits/bits>> = Data,
    {X, Bits};
decode_signed(Data, Size, big)      ->
    <<X:Size/signed-integer-big, Bits/bits>> = Data,
    {X, Bits}.

decode_unsigned(Data, Size, little) -> 
    <<X:Size/unsigned-integer-little, Bits/bits>> = Data,
    {X, Bits};
decode_unsigned(Data, Size, big) ->
    <<X:Size/unsigned-integer-big, Bits/bits>> = Data,
    {X, Bits}.
    
decode_float(Data, Size, little)    -> 
    <<X:Size/float-little, Bits/bits>> = Data,
    {X, Bits};
decode_float(Data, Size, big) -> 
    <<X:Size/float-big, Bits/bits>> = Data,
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
    bitsize_e(canopen:encode_type(Type)).

bitsize_compound_e([{_T,Size}|Ts]) ->
    Size + bitsize_compound_e(Ts);
bitsize_compound_e([T|Ts]) ->
    case bitsize_e(T) of
	0 -> 0;
	Size -> Size + bitsize_compound_e(Ts)
    end;
bitsize_compound_e([]) ->
    0.


