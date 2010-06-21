%%% File    : co_crc.erl
%%% Author  : Tony Rogvall <tony@PBook.local>
%%% Description : CCITT CRC 16 (initial=0)
%%% Created :  5 Feb 2008 by Tony Rogvall <tony@PBook.local>

-module(co_crc).

-export([init/0]).
-export([final/1]).
-export([update/2]).
-export([checksum/1]).


init() -> 0.
final(CRC) -> CRC.
update(CRC, [H|T]) ->
    if is_integer(H) ->
	    update(update_byte(CRC,H), T);
       true ->
	    update(update(CRC, H), T)
    end;
update(CRC, []) -> CRC;
update(CRC, Value) when is_integer(Value) ->
    update_byte(CRC, Value);
update(CRC, Bin) when is_binary(Bin) ->
    update_bin(CRC, Bin).

update_bin(CRC, <<>>) ->
    CRC;
update_bin(CRC, <<Value:8,Bin/binary>>) ->
    update_bin(update_byte(CRC,Value), Bin).

-define(u8(X), ((X) band 16#ff)).
-define(u16(X), ((X) band 16#ffff)).

update_byte(CRC, Val) ->
    CRC0 = ?u8(CRC bsr 8) bor (CRC bsl 8),
    CRC1 = ?u16(CRC0 bxor Val),
    CRC2 = CRC1 bxor (?u8(CRC1) bsr 4),
    CRC3 = CRC2 bxor ?u16(?u16(CRC2 bsl 8) bsl 4),
    CRC3 bxor ?u16(?u16(?u8(CRC3) bsl 4) bsl 1).
	     
checksum(Data) ->
    CRC0 = init(),
    CRC1 = update(CRC0, Data),
    final(CRC1).
