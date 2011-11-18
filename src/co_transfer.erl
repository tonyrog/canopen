%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%   Canopen data transfer functions
%%% @end
%%% Created :  4 Jun 2010 by Tony Rogvall <tony@rogvall.se>

-module(co_transfer).

-include_lib("can/include/can.hrl").
-include("../include/canopen.hrl").
-include("../include/sdo.hrl").
-include("../include/co_app.hrl").

-export([write_begin/3, write/3, write_end/2]).
-export([write_data_begin/3, write_get_data/1]).
-export([write_size/2]).
-export([write_block_segment/3, write_block_segment_end/1,
	 write_block_end/5]).

-export([read_begin/3, read/2, read_end/1]).
-export([read_data_begin/4]).
-export([app_t_handle/3]).

-export([get_block_seqno/1]).
-export([get_max_size/1]).
-export([get_size/1]).


-record(t_handle,
	{
	  storage,      %% copy of dictionary handle or pid
	  type,         %% item type
	  index,        %% item index
	  subind,       %% item sub-index
	  data,         %% item data
	  size,         %% current item size
	  block=[],     %% block segment list [{1,Bin},...{127,Bin}]
	  max_size,     %% item max size
	  transfer_mode,%% mode for transfer to application 
	  endf          %% transfer end callback
	}).
   
-define(is_seq(N), ((N) band -128)=:=0, (N) =/= 0).
-ifdef(debug).
-define(dbg(Fmt,As), io:format(Fmt, As)).
-else.
-define(dbg(Fmt, As), ok).
-endif.

%%
%% Start a write operation 
%% return
%%     {error, AbortCcode}
%%  |  {ok, Handle, MaxSize}
%%
%%
write_begin(Ctx, Index, SubInd) ->
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg("~p: write_begin: No reserver for index ~7.16.0#\n", [?MODULE,Index]),
	    central_write_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid) ->
	    ?dbg("~p: write_begin: Process ~p has reserved index ~7.16.0#\n", 
		 [?MODULE, Pid, Index]),
	    app_write_begin(Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg("~p: write_begin: Reserver process dead.\n", [?MODULE]),
	    {error, ?abort_internal_error}; %% ???
	Other ->
	    ?dbg("~p: write_begin: Other case = ~p\n", [?MODULE,Other]),
	    {error, ?abort_internal_error}
    end.


central_write_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	Err = {error,_} ->
	    Err;
	{ok,E=#dict_entry{type=Type}} ->
	    if E#dict_entry.access =:= ?ACCESS_RO;
	       E#dict_entry.access =:= ?ACCESS_C ->
		    {error,?abort_write_not_allowed};
	       true ->
		    MaxSize = co_codec:bytesize(Type),
		    Handle = #t_handle { storage = Dict, type=Type,
					 index=Index, subind=SubInd,
					 data=(<<>>), size=0, 
					 max_size=MaxSize },
		    {ok, Handle, MaxSize}
	    end
    end.

app_write_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_WO) =:= ?ACCESS_WO ->
		    MaxSize = co_codec:bytesize(Entry#app_entry.type),
		    Transfer = case Entry#app_entry.transfer of
				   streamed -> 
				       Ref = make_ref(),
				       gen_server:cast(Pid, {write_begin, {Index, SubInd}, Ref}),
				       {streamed, Ref};
				   {streamed, Module} -> 
				       Ref = make_ref(),
				       Module:write_begin(Pid, {Index, SubInd}, Ref),
				       {streamed, Module, Ref};
				   Other ->
				       Other
			       end,
		    ?dbg("~p: app_write_begin: Transfer mode = ~p\n", [?MODULE, Transfer]),
		    Handle = #t_handle { storage = Pid,  type=Entry#app_entry.type,
					 index=Index, subind=SubInd,
					 data=(<<>>), size=0,
					 max_size=MaxSize,
				         transfer_mode=Transfer },
		    {ok, Handle, MaxSize};
	       true ->
		    {entry, ?abort_unsupported_access}
	    end;
	{error, Reason}  ->
	    {error, Reason}
    end.
    
    
%% 
%%  Start a write operation with just a value no dictionary
%% 
write_data_begin(Index, SubInd, EndF) ->
    MaxSize = 0,
    Handle = #t_handle { index=Index, subind=SubInd,
			 data=(<<>>), size=0, 
			 max_size=MaxSize,
			 endf = EndF
		       },
    {ok, Handle, MaxSize}.

%%
%% Set maximum write size if not set already
%%
write_size(TH, Size) when TH#t_handle.size =:= Size ->
    TH;
write_size(TH, Size) when 
      TH#t_handle.size =:= 0; TH#t_handle.size =:= undefined ->
    TH#t_handle { max_size=Size };
write_size(_TH, _Size) ->
    {error, ?abort_data_length_error}.

%%
%% Fetch current data
%%

write_get_data(Handle) ->
    Handle#t_handle.data.

%% Write data
%%  return 
%%     {error, AbortCode}
%%   | {ok, Handle', NBytesWritten}
%%
write(Handle, Data, NBytes) ->
    <<Data1:NBytes/binary, _/binary>> = Data,
    NewData = <<(Handle#t_handle.data)/binary, Data1/binary>>,
    NewSize = Handle#t_handle.size + NBytes,
    if Handle#t_handle.max_size =:= 0;
       NewSize =< Handle#t_handle.max_size ->
	    %% Check if streaming to application
	    case Handle#t_handle.transfer_mode of
		{streamed, Ref} ->
		    gen_server:cast(Handle#t_handle.storage, {write, Ref, Data1});
		{streamed, Mod, Ref} ->
		    Mod:write(Handle#t_handle.storage, Ref, Data1);
		_Other ->
		    do_nothing %% atomic
	    end,

	    {ok, Handle#t_handle { size=NewSize, data=NewData}, NBytes};
       true ->
	    {error, ?abort_unsupported_access}
    end.


%% Write block segment data (7 bytes) Seq=1..127 
%% Imply that max block size 127*7 = 889 bytes
write_block_segment(Handle, Seq, Data) when ?is_seq(Seq),
					    byte_size(Data) =:= 7 ->
    Block = [{Seq,Data} | Handle#t_handle.block],
    {ok, Handle#t_handle { block = Block}, 7};
write_block_segment(_Handle, _Seq, _Data) ->
    {error, ?abort_invalid_sequence_number}.

%% Concatinate and write all segments
write_block_segment_end(TH) ->
    Bin = list_to_binary(lists:map(fun({_,Data}) -> Data end,
				   lists:reverse(TH#t_handle.block))),
    MaxSize = TH#t_handle.max_size,
    Size = byte_size(Bin),
    %% io:format("write_block_segment_end: max=~w, sz=~w, bin=~p\n", [MaxSize, size(Bin), Bin]),
    if MaxSize =:= 0 ->
	    write(TH, Bin, Size);
       true ->
	    Remain = MaxSize - TH#t_handle.size,
	    if Remain =< 0 ->
		    {error, ?abort_data_length_too_high};
	       Size =< Remain; (Size-Remain) < 7 ->
		    NewData = <<(TH#t_handle.data)/binary, Bin/binary>>,
		    NewSize = TH#t_handle.size + Size,
		    TH1 = TH#t_handle { size=NewSize,data=NewData,block=[]},
		    {ok, TH1, Size};
	       true ->
		    {error, ?abort_data_length_too_high}
	    end
    end.

%% Handle the end of block data
%% Check CRC if needed.

write_block_end(Ctx,Handle,N,CRC,CheckCrc) ->
    Handle1 =
	if N =:= 0 ->
		Handle;
	   true ->
		Size1 = Handle#t_handle.size - N,
		<<Data1:Size1/binary,_/binary>> = Handle#t_handle.data,
		Handle#t_handle { data=Data1, size=Size1 }
	end,
    if Handle1#t_handle.max_size > 0,
       Handle1#t_handle.size > Handle1#t_handle.max_size ->
	    {error, ?abort_data_length_too_high};
       CheckCrc ->
	    Data = Handle1#t_handle.data,
	    io:format("co_transfer: data0=~p, size=~w, data=~p\n", [Handle#t_handle.data,size(Data),Data]),
	    case co_crc:checksum(Handle1#t_handle.data) of
		CRC ->
		    write_end(Ctx, Handle1);
		_ ->
		    {error, ?abort_crc_error}
	    end;
       true ->
	    write_end(Ctx, Handle1)
    end.
    

%% Finalize write
%%  return 
%%    {error, AbortCode}
%%  | ok
%%  | {ok, Data}   - no dictionary
%%
write_end(_Ctx, Handle) when Handle#t_handle.storage == undefined ->
    (Handle#t_handle.endf)(Handle#t_handle.data);
write_end(Ctx, Handle) ->
    if Handle#t_handle.max_size =:= 0;
       Handle#t_handle.size == Handle#t_handle.max_size ->
	    try co_codec:decode(Handle#t_handle.data, 
				Handle#t_handle.type) of
		{Value,_} ->
		    Index = Handle#t_handle.index,
		    SubInd = Handle#t_handle.subind,
						  
		    case Handle#t_handle.storage of
			Pid when is_pid(Pid) ->
			    %% An application is responsible for the data
			    ?dbg("~p: write_to_app: ~.16B:~.8B, Value = ~p\n", 
				 [?MODULE, Index, SubInd, Value]),
			    %% Check if streaming to application
			    case Handle#t_handle.transfer_mode of
				{streamed, Ref} ->
				    app_call(Pid, {write_end, Ref});
				{streamed, Mod, Ref} ->
				    Mod:write_end(Pid, Ref);
				atomic ->
				    app_call(Pid, {set, {Index, SubInd}, Value});
				{atomic, Module} ->
				    Module:set(Pid, {Index, SubInd}, Value)
			    end;

			Dict ->
			    ?dbg("~p: write_to_dict: Index = ~p, SubInd = ~p, Value = ~p\n", 
				 [?MODULE, Index, SubInd, Value]),
			    Res = co_dict:direct_set(Dict, Index, SubInd, Value),
			    inform_subscribers(Index, Ctx),
			    Res
		    end
	    catch
		error:_ ->
		    {error, ?abort_internal_error}
	    end;
       true ->
	    {error, ?abort_data_length_too_low}
    end.
       
inform_subscribers(I, Ctx) ->
    ?dbg("~s: inform_subscribers: Searching for subscribers for ~p\n", [?MODULE, I]),
    lists:foreach(
      fun(Pid) ->
	      ?dbg("~s: inform_subscribers: Sending object changed to ~p\n", 
		   [?MODULE, Pid]),
	      gen_server:cast(Pid, {object_changed, I}) 
      end,
      co_node:subscribers(Ctx#sdo_ctx.sub_table, I)).

%%
%% Start a read operation 
%% return
%%     {error, AbortCcode}
%%  |  {ok, Handle, MaxSize}
%%
%%

read_begin(Ctx, Index, SubInd) ->
    case co_node:reserver_with_module(Ctx#sdo_ctx.res_table, Index) of
	[] ->
	    ?dbg("~p: read_begin: No reserver for index ~7.16.0#\n", [?MODULE,Index]),
	    central_read_begin(Ctx, Index, SubInd);
	{Pid, Mod} when is_pid(Pid)->
	    ?dbg("~p: read_begin: Process ~p subscribes to index ~7.16.0#\n", 
		 [?MODULE, Pid, Index]),
	    app_read_begin(Index, SubInd, Pid, Mod);
	{dead, _Mod} ->
	    ?dbg("~p: read_begin: Reserver process dead.\n", [?MODULE]),
	    {error, ?abort_internal_error}; %% ???
	Other ->
	    ?dbg("~p: read_begin: Other case = ~p\n", [?MODULE,Other]),
	    {error, ?abort_internal_error}
    end.

central_read_begin(Ctx, Index, SubInd) ->
    Dict = Ctx#sdo_ctx.dict,
    case co_dict:lookup_entry(Dict, {Index,SubInd}) of
	Err = {error,_} ->
	    Err;
	{ok,E=#dict_entry{type=Type,value=Value}} ->
	    if E#dict_entry.access =:= ?ACCESS_WO ->
		    {error, ?abort_read_not_allowed};
	       true ->
		    ?dbg("~p: central_read_begin: Read access ok\n", [?MODULE]),
		    Data = co_codec:encode(Value, Type),
		    MaxSize = byte_size(Data),
		    TH = #t_handle { storage = Dict, type=Type,
				     index=Index, subind=SubInd,
				     data=Data, size=MaxSize,
				     max_size=MaxSize },

		    {ok, TH, MaxSize}
	    end
    end.

app_read_begin(Index, SubInd, Pid, Mod) ->
    case Mod:get_entry(Pid, {Index, SubInd}) of
	{entry, Entry} ->
	    if (Entry#app_entry.access band ?ACCESS_RO) =:= ?ACCESS_RO ->
		    ?dbg("~p: app_read_begin: Read access ok\n", [?MODULE]),
		    app_call(Pid, {get, {Index, SubInd}});
	       true ->
		    {entry, ?abort_read_not_allowed}
	    end
    end.
	
app_t_handle(Data, Index, SubInd) when is_binary(Data) ->
    MaxSize = byte_size(Data),
    TH = #t_handle { storage = application,
		     index=Index, subind=SubInd,
		     data=Data, size=MaxSize,
		     max_size=MaxSize
		   },
    {ok, TH, MaxSize}.
%% 
%%  Start a read operation with just a value no dcitionary 
%% 
read_data_begin(Data, Index, SubInd, EndF) when is_binary(Data) ->
    MaxSize = byte_size(Data),
    TH = #t_handle { index=Index, subind=SubInd,
		     data=Data, size=MaxSize,
		     max_size=MaxSize,
		     endf = EndF
		   },
    {ok, TH, MaxSize}.

%%
%% Read at most NBytes from store
%% return:
%%    {error,AbortCode}
%% |  {ok,Handle',Data}
%%
read(Handle, NBytes) ->
    if NBytes =< Handle#t_handle.size ->
	    <<Data:NBytes/binary, NewData/binary>> = Handle#t_handle.data,
	    NewSize = Handle#t_handle.size - NBytes,
	    {ok, Handle#t_handle { data=NewData, size=NewSize }, Data};
       true ->
	    Data = Handle#t_handle.data,
	    {ok, Handle#t_handle { data=(<<>>), size=0 }, Data }
    end.


read_end(Handle) when Handle#t_handle.storage == undefined ->
    (Handle#t_handle.endf)(Handle#t_handle.data);
read_end(_Handle) ->
    ok.


%% Return the last received sequence number
get_block_seqno(Handle) ->
    case Handle#t_handle.block of
	[{Seq,_}|_] -> Seq;
	_ -> 0
    end.

get_max_size(Handle) ->
    Handle#t_handle.max_size.
    
%% Return bytes remain to be read
get_size(Handle) ->
    Handle#t_handle.size.


app_call(Pid, Msg) ->
    case catch do_call(Pid, Msg) of 
	{'EXIT', Reason} ->
	    io:format("app_call: catch error ~p\n",[Reason]), 
	    {error, ?ABORT_INTERNAL_ERROR};
	Mref ->
	    {ok, Mref}
    end.


do_call(Process, Request) ->
    Mref = erlang:monitor(process, Process),

    erlang:send(Process, {'$gen_call', {self(), Mref}, Request}, [noconnect]),
    Mref.
