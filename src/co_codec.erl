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
	 set_binary_size/2,
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
    encode_e(0,Data,?UNSIGNED8,<<>>);
encode(Data, Type) ->
    encode_e(0,Data,Type,<<>>).

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

decode(Data,Type) ->
    decode_e(0,Data,Type).

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
    
encode_e(P, D, ?INTEGER8, B)   -> encode_signed(P, D, 8, B);
encode_e(P, D, ?INTEGER16, B)  -> encode_signed(P, D, 16, B);
encode_e(P, D, ?INTEGER24, B)  -> encode_signed(P, D, 24, B);
encode_e(P, D, ?INTEGER32, B)  -> encode_signed(P, D, 32, B);
encode_e(P, D, ?INTEGER40, B)  -> encode_signed(P, D, 40, B);
encode_e(P, D, ?INTEGER48, B)  -> encode_signed(P, D, 48, B);
encode_e(P, D, ?INTEGER56, B)  -> encode_signed(P, D, 56, B);
encode_e(P, D, ?INTEGER64, B)  -> encode_signed(P, D, 64, B);
encode_e(P, D, ?UNSIGNED8, B)  -> encode_unsigned(P, D, 8, B);
encode_e(P, D, ?UNSIGNED16, B) -> encode_unsigned(P, D, 16, B);
encode_e(P, D, ?UNSIGNED24, B) -> encode_unsigned(P, D, 24, B);
encode_e(P, D, ?UNSIGNED32, B) -> encode_unsigned(P, D, 32, B);
encode_e(P, D, ?UNSIGNED40, B) -> encode_unsigned(P, D, 40, B);
encode_e(P, D, ?UNSIGNED48, B) -> encode_unsigned(P, D, 48, B);
encode_e(P, D, ?UNSIGNED56, B) -> encode_unsigned(P, D, 56, B);
encode_e(P, D, ?UNSIGNED64, B) -> encode_unsigned(P, D, 64, B);
encode_e(P, D, ?BOOLEAN, B)    -> encode_unsigned(P, D, 1, B);
encode_e(P, D, ?REAL32, B)     -> encode_float(P, D, 32, B);
encode_e(P, D, ?REAL64, B)     -> encode_float(P, D, 64, B);
encode_e(P, D, ?VISIBLE_STRING, B) ->
    Bin = iolist_to_binary(D),
    encode_binary(P,Bin,bit_size(Bin), B);
encode_e(P, D, ?OCTET_STRING, B) -> 
    Bin = iolist_to_binary(D),
    encode_binary(P,Bin,bit_size(Bin), B);    
encode_e(P, D, ?UNICODE_STRING, B) -> 
    Bin = << <<X:16/little>> || X <- D >>,
    encode_binary(P,Bin,bit_size(Bin), B);
encode_e(P, D, ?DOMAIN, B) -> 
    Bin = iolist_to_binary(D),
    encode_binary(P,Bin,bit_size(Bin), B); 
encode_e(P, D, ?TIME_OF_DAY, B) ->
    encode_compound_e(P,[D#time_of_day.ms,0,D#time_of_day.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], B);
encode_e(P, D, ?TIME_DIFFERENCE, B) ->
    encode_compound_e(P,[D#time_difference.ms,0,D#time_difference.days],
		      [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}], B);
encode_e(P, D, {Type,Size}, B) ->
    encode_e(P, D, Type, Size, B);
encode_e(P, D, TypeList, B) when is_list(TypeList) ->
    encode_compound_e(P, D, TypeList, B);
encode_e(P, D, Type, B) when is_atom(Type) ->
    encode_e(P, D, co_lib:encode_type(Type), B).

encode_e(P, 0,    _Any,    S, B) -> encode_signed(P, 0, S, B);
encode_e(P, D, ?INTEGER8,  S, B) when S=<8  -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER16, S, B) when S=<16 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER24, S, B) when S=<24 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER32, S, B) when S=<32 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER40, S, B) when S=<40 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER48, S, B) when S=<48 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER56, S, B) when S=<56 -> encode_signed(P, D, S, B);
encode_e(P, D, ?INTEGER64, S, B) when S=<64 -> encode_signed(P, D, S, B);
encode_e(P, D, ?UNSIGNED8, S, B) when S=<8  -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED16,S, B) when S=<16 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED24,S, B) when S=<24 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED32,S, B) when S=<32 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED40,S, B) when S=<40 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED48,S, B) when S=<48 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED56,S, B) when S=<56 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?UNSIGNED64,S, B) when S=<64 -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?BOOLEAN, S, B) when S =< 1   -> encode_unsigned(P, D, S, B);
encode_e(P, D, ?REAL32, S, B) when S=:=32 -> encode_float(P, D, 32, B);
encode_e(P, D, ?REAL64, S, B) when S=:=64 -> encode_float(P, D, 64, B);
encode_e(P, D, ?VISIBLE_STRING, S, B) ->
    Bin = iolist_to_binary(D),
    encode_binary(P, Bin, S, B);
encode_e(P, D, ?OCTET_STRING, S, B) -> 
    encode_binary(P,list_to_binary(D), S, B);
encode_e(P, D, ?UNICODE_STRING, S, B) ->
    encode_binary(P, << <<X:16/little>> || X <- D>>, S, B);
encode_e(P, D, ?DOMAIN, S, B) when is_bitstring(D) -> 
    encode_binary(P, D, S, B);
encode_e(P, D, ?DOMAIN, S, B) when is_list(D) -> 
    encode_binary(P, list_to_binary(D), S, B);
encode_e(P, D, Type, S, B) when is_atom(Type) ->
    encode_e(P, D, co_lib:encode_type(Type), S, B).

encode_compound_e(P,[D|Ds],[{Type,Size}|List],B) when is_integer(Size) ->
    encode_compound_e(P+Size,Ds,List,encode_e(P, D, Type, Size, B));
encode_compound_e(P,[D|Ds],[Size|List],B) when is_integer(Size) ->
    encode_compound_e(P+Size,Ds,List,encode_e(P, D, ?DOMAIN, Size, B));
encode_compound_e(_P, [], [], B) ->
    B.

encode_pdo(Ds, TypeList) ->
    encode_compound_e(0,Ds,TypeList,<<>>).

encode_signed(Pos, Data, Size, Bits) ->
    replace_lsb_bits(Pos, <<Data:Size/signed-integer-little>>, Bits).

encode_unsigned(Pos, Data, Size, Bits) ->
    replace_lsb_bits(Pos, <<Data:Size/unsigned-integer-little>>, Bits).
    
encode_float(Pos, Data, Size, Bits) ->
    replace_lsb_bits(Pos, <<Data:Size/float-little>>, Bits).

encode_binary(Pos, Data, Size, Bits) when is_bitstring(Data) ->
    replace_lsb_bits(Pos,<<Data:Size/bits>>, Bits).


replace_lsb_bits(Pos, Bits, BitString) ->
    Len = bit_size(Bits),
    BitString1 = ensure_size(BitString, ((Len+Pos+7) bsr 3)*8),
    Offs0 = (Pos bsr 3) bsl 3,
    ALen1 = Pos band 7,
    ALen  = (8-ALen1) band 7,
    if Len =< ALen -> %% Data fit in first byte
	    Offs1 = Offs0+(ALen-Len),
	    <<A0:Offs1/bits,_:Len/bits,A2:ALen1/bits,C0/bits>> = BitString1,
	    <<A0/bits, Bits/bits, A2/bits, C0/bits>>;
       ALen1 =:= 0 -> %% ALen = 0
	    BLen = (Len bsr 3)*8, %% middle bits
	    case Len-BLen of  %% tail
		0 ->  %% CLen=CLen1=0
		    <<A0:Offs0/bits,_:BLen/bits, C0/bits>> = BitString1,
		    <<A0/bits,Bits/bits,C0/bits>>;
		CLen ->
		    CLen1 = (8-CLen) band 7,
		    <<A0:Offs0/bits,_:BLen/bits,
		      C1:CLen1/bits,_:CLen/bits,C0/bits>> = BitString1,
		    <<Seg2:BLen/bits, Seg3:CLen/bits>> = Bits,
		    <<A0/bits,Seg2/bits,C1/bits,Seg3/bits,C0/bits>>
	    end;
       true -> %% Len > ALen!
	    TLen = Len - ALen,
	    BLen = (TLen bsr 3)*8, %% middle bits
	    CLen = TLen - BLen,    %% tail
	    CLen1 = (8-CLen) band 7,
	    <<A0:Offs0/bits, _:ALen/bits, A2:ALen1/bits,
	      _:BLen/bits,C1:CLen1/bits,_:CLen/bits,C0/bits>> = BitString1,
	    <<Seg1:ALen/bits, Seg2:BLen/bits, Seg3:CLen/bits>> = Bits,
	    <<A0/bits,Seg1/bits,A2/bits,Seg2/bits,C1/bits,Seg3/bits,C0/bits>>
    end.    

%%
%% Decoder ->
%%   Data -> { Element, Bits }
%%
decode_e(P, Data, ?INTEGER8)   -> decode_signed(P, Data, 8);
decode_e(P, Data, ?INTEGER16)  -> decode_signed(P, Data, 16);
decode_e(P, Data, ?INTEGER24)  -> decode_signed(P,Data, 24);
decode_e(P, Data, ?INTEGER32)  -> decode_signed(P,Data, 32);
decode_e(P, Data, ?INTEGER40)  -> decode_signed(P,Data, 40);
decode_e(P, Data, ?INTEGER48)  -> decode_signed(P,Data, 48);
decode_e(P, Data, ?INTEGER56)  -> decode_signed(P,Data, 56);
decode_e(P, Data, ?INTEGER64)  -> decode_signed(P,Data, 64);
decode_e(P, Data, ?UNSIGNED8)  -> decode_unsigned(P, Data, 8);
decode_e(P, Data, ?UNSIGNED16) -> decode_unsigned(P, Data, 16);
decode_e(P, Data, ?UNSIGNED24) -> decode_unsigned(P, Data, 24);
decode_e(P, Data, ?UNSIGNED32) -> decode_unsigned(P, Data, 32);
decode_e(P, Data, ?UNSIGNED40) -> decode_unsigned(P, Data, 40);
decode_e(P, Data, ?UNSIGNED48) -> decode_unsigned(P, Data, 48);
decode_e(P, Data, ?UNSIGNED56) -> decode_unsigned(P, Data, 56);
decode_e(P, Data, ?UNSIGNED64) -> decode_unsigned(P, Data, 64);
decode_e(P, Data, ?BOOLEAN)    -> decode_unsigned(P, Data, 1);
decode_e(P, Data, ?REAL32)     -> decode_float(P, Data, 32);
decode_e(P, Data, ?REAL64)     -> decode_float(P, Data, 64);
decode_e(P, Data, ?VISIBLE_STRING) ->
    Size = bit_size(Data) - P,
    binary_to_list(decode_binary(P, Data, Size));
decode_e(P, Data, ?OCTET_STRING)   ->
    Size = bit_size(Data) - P,    
    decode_binary(P, Data, Size);
decode_e(P, Data, ?UNICODE_STRING) ->
    Size = bit_size(Data) - P,
    Bin = decode_binary(P, Data, Size),
    [ X || <<X:16/little>> <= Bin ];
decode_e(P, Data, ?DOMAIN) ->
    Size = bit_size(Data) - P,
    decode_binary(P, Data, Size);
decode_e(P, Data, ?TIME_OF_DAY) ->
    [Ms,_,Days] =
	decode_compound_e(P,Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]),
    #time_of_day { ms=Ms, days=Days };
decode_e(P, Data, ?TIME_DIFFERENCE) ->
    [Ms,_,Days] =
	decode_compound_e(P, Data,
			  [{?UNSIGNED,28},{?UNSIGNED,4},{?UNSIGNED,16}]),
    #time_difference { ms = Ms, days=Days };
decode_e(P, D, {Type,Size}) ->
    decode_e(P, D, Type, Size);
decode_e(P, D, TypeList) when is_list(TypeList) ->
    decode_compound_e(P, D, TypeList);
decode_e(P, D, Type) when is_atom(Type) ->
    decode_e(P, D, co_lib:encode_type(Type)).

%% decode parts of data types
decode_e(P, Data, ?INTEGER8,  S) when S=<8 ->  decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER16, S) when S=<16 -> decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER24, S) when S=<24 -> decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER32, S) when S=<32->  decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER40, S) when S=<40->  decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER48, S) when S=<48->  decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER56, S) when S=<56->  decode_signed(P, Data, S);
decode_e(P, Data, ?INTEGER64, S) when S=<64->  decode_signed(P, Data, S);
decode_e(P, Data, ?UNSIGNED8, S) when S=<8->   decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED16,S) when S=<16->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED24,S) when S=<24->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED32,S) when S=<32->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED40,S) when S=<40->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED48,S) when S=<48->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED56,S) when S=<56->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?UNSIGNED64,S) when S=<64->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?BOOLEAN,S)    when S=<1 ->  decode_unsigned(P, Data, S);
decode_e(P, Data, ?REAL32, S) when S=:=32 ->   decode_float(P, Data, 32);
decode_e(P, Data, ?REAL64, S) when S=:=64 ->   decode_float(P, Data, 64);
decode_e(P, Data, ?VISIBLE_STRING, S) ->
    binary_to_list(decode_binary(P, Data, S));
decode_e(P, Data, ?OCTET_STRING, S) ->
    decode_binary(P, Data, S);
decode_e(P, Data, ?UNICODE_STRING, S) ->
    Bin = decode_binary(P, Data, S),
    [X || <<X:16/little>> <= Bin];
decode_e(P, Data, ?DOMAIN, S) ->
    decode_binary(P, Data, S);
decode_e(P, Data, Type, S) when is_atom(Type) ->
    decode_e(P, Data, co_lib:encode_type(Type), S).

decode_compound_e(P,B,[{Type,Size}|List]) when is_integer(Size) ->
    [decode_e(P,B,Type,Size) | decode_compound_e(P+Size,B,List)];
decode_compound_e(P,B,[Size|List]) when is_integer(Size) ->
    [decode_e(P,B,?DOMAIN,Size) | decode_compound_e(P+Size,B,List)];
decode_compound_e(_P,_B,[]) ->
    [].

%%
%% RPDO decoding. 
%% FIXME: handle error cases, Data to small etc.
%%
decode_pdo(Data, TypeList) when is_list(TypeList) ->
    Size = bitsize_e(TypeList),
    Bits = extract_lsb_bits(0, Size, Data),
    PdoData = decode_compound_e(0, Bits, TypeList),
    Tail = extract_lsb_bits(Size, bit_size(Data)-Size, Data),
    {PdoData,Tail}.

decode_signed(Pos, Data, Size) ->
    <<X:Size/signed-integer-little>> = extract_lsb_bits(Pos, Size, Data),
    X.

decode_unsigned(Pos, Data, Size) -> 
    <<X:Size/unsigned-integer-little>> = extract_lsb_bits(Pos, Size, Data),
    X.

decode_float(Pos, Data, Size) -> 
    <<X:Size/float-little>> = extract_lsb_bits(Pos, Size, Data),
    X.

decode_binary(Pos, Data, -1) ->
    Size = bit_size(Data) - Pos,
    extract_lsb_bits(Pos, Size, Data);
decode_binary(Pos, Data, Size) ->
    extract_lsb_bits(Pos, Size, Data).

extract_lsb_bits(Pos, Len, BitString) ->
    BitString1 = ensure_size(BitString, Len+Pos),
    Offs0    = (Pos bsr 3) bsl 3,
    ALen1    = Pos band 7,
    ALen     = (8-ALen1) band 7,
    if Len =< ALen ->
	    Offs1 = Offs0 + (ALen-Len),
	    <<_:Offs1/bits,Bits:Len/bits,_/bits>> = BitString1,
	    Bits;
       ALen1 =:= 0 -> %% => ALen = 0
	    BLen = (Len bsr 3)*8,    %% middle bits
	    case Len-BLen of
		0 ->
		    <<_:Offs0/bits,Bits:BLen/bits,_/binary>> = BitString1,
		    Bits;
		CLen ->
		    CLen1 = (8-CLen) band 7,
		    <<_:Offs0/bits,
		      B:BLen/bits,_:CLen1/bits,C2:CLen/bits,_/binary>> = 
			BitString1,
		    <<B/bits,C2/bits>>
	    end;
       true -> %% Len > ALen
	    TLen = Len - ALen,
	    BLen = (TLen bsr 3)*8,    %% middle bits
	    CLen = TLen - BLen,       %% tail
	    CLen1 = (8-CLen) band 7,
	    <<_:Offs0/bits,A1:ALen/bits,_:ALen1/bits,
	      B:BLen/bits,_:CLen1/bits,C2:CLen/bits,_/binary>> = BitString1,
	    <<A1/bits,B/bits,C2/bits>>
    end.

ensure_size(BitString, NBits) when bit_size(BitString) >= NBits ->
    BitString;
ensure_size(BitString, NBits) ->
    Pad = NBits - bit_size(BitString),
    <<BitString/bits, 0:Pad>>.


set_binary_size(BitString, Size) ->
    BitSize = bit_size(BitString),
    if BitSize =:= Size -> BitString;
       BitSize > Size -> <<BitString:Size/bits>>;
       true -> 
	    Pad = Size - BitSize,
	    <<BitString/bits, Pad:0>>
    end.

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

bitsize_compound_e([{_Type,Size}|Ts]) when is_integer(Size) ->
    Size + bitsize_compound_e(Ts);
bitsize_compound_e([Size|Ts]) when is_integer(Size) -> %% is this used?conflict?
    Size + bitsize_compound_e(Ts);
bitsize_compound_e([]) ->
    0.
