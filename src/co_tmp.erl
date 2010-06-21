

%% Calculate number of segments per block we want to receive
next_blksize(S) ->
    if S#co_session.blkbytes > 0 ->
	    %% calculate number of blocks based on blkbytes and current
	    %% bitoffs. Number of segments should be so that we fill a
	    %% buffer specified by blkbytes. extra bytes must be taken into
	    %% account (by bitoffs) for next round.

	    %% next position to be filled in the "buffer"
	    Pos = (S#co_session.bitoffs bsr 3) rem 
		S#co_session.blkbytes,
	    %% bytes remain to fill in the "buffer"
	    Bytes = S#co_session.blkbytes - Pos,
	    BlkSize1 = (Bytes + 7 - 1) rem 7,
	    if BlkSize1 =:= 0 -> 
		    1;
	       BlkSize1 > (S#co_session.ctx)#sdo_ctx.max_blksize ->
		    (S#co_session.ctx)#sdo_ctx.max_blksize;
	       true ->
		    BlkSize1
	    end;
       S#co_session.blksize =:= 0 ->
	    (S#co_session.ctx)#sdo_ctx.max_blksize;
       true ->
	    S#co_session.blksize
    end.

flush_timer(S) ->
    Th = S#co_session.th,
    receive {timeout,Th,_Name} -> ok after 0 -> ok end,
    S#co_session { th=undefined }.
	
cancel_timer(S) ->
    Th = S#co_session.th,
    if Th == undefined -> S;
       true ->
	    case erlang:cancel_timer(Th) of
		false -> flush_timer(S);
		Remain when is_integer(Remain) ->
		    S#co_session { th=undefined }
	    end
    end.

set_timer(S,Name) ->
    cancel_timer(S),
    Timeout = (S#co_session.ctx)#sdo_ctx.timeout,
    Th = erlang:start_timer(Timeout, self(), Name),
    S#co_session { th = Th }.

enter_block_mode(S) ->
    S1 = set_timer(S,s_block_timeout),
    S1#co_session { block = true }.

leave_block_mode(S) ->
    S1 = set_timer(S,s_timeout),
    BlkErr = if S1#co_session.blkerr > 0 ->
		     S1#co_session.blkerr-1;
		true -> 0
	     end,
    S1#co_session { block=false, blkerr = BlkErr }.

%% Create a SDO session
new(Ctx, Client, Src, Dst, Index, Subind, Arg) ->
    #co_session {
     cs       = Client,   %% client side
     src      = Src,
     dst      = Dst,
     index    = Index,
     subind   = Subind,
     blksize  = 0,
     blkseq   = 0,
     blkpst   = Ctx#sdo_ctx.pst,
     blkerr   = 0,
     blkbytes = 0,
     bitlen   = 0,
     bitoffs  = 0,
     skipcrc  = 0,
     arg     = Arg,
     status  = 0
    }.

delete(S, Reason) ->
    cancel_timer(S),
    throw({abort, Reason}).

send_abort(_Ctx,Dst,Index,SubInd,Reason) ->
    PDU = #sdo_abort { index=Index, subind=SubInd, code=Reason },
    send_dst(Dst, PDU).

abort(Ctx,S,Reason) ->
    send_abort(Ctx, S#co_session.dst, S#co_session.index, 
	       S#co_session.subind, Reason),
    delete(S, Reason).


%% Test and set new block size from other party
%%  -> session() || exception
set_blksize(Ctx,S, BlkSize) when BlkSize =:= 0; BlkSize > ?MAX_BLKSIZE ->
    abort(Ctx,S, ?ABORT_INVALID_BLOCK_SIZE);
set_blksize(_Ctx,S, BlkSize) ->
    S#co_session { blksize = BlkSize }.



%% Generic send segment or block
%%
%% SEND an upload segment (server => client)
%% return false if session is abort or deleted
%% D = upload|download
%%
send_segment(Ctx,S,D,Block) ->
    Rlen = S#co_session.bitlen-S#co_session.bitoffs,
    NBits = if Rlen > 56 -> 56; true -> Rlen end,
    {S1,Data,NBits1} = transfer_read(Ctx,S, NBits),
    Last = NBits1<56 orelse ((S1#co_session.bitlen > 0) andalso
			     (S1#co_session.bitoffs >= 
				  S1#co_session.bitlen)),
    if Block ->
	    NRemain = 56-NBits1,
	    Data1 = <<Data/binary, 0:NRemain>>,
	    Skip = if S1#co_session.skipcrc > 0 ->
			   S1#co_session.skipcrc - 1;
		      true ->
			   0
		   end,
	    BlkCrc = if S1#co_session.skipcrc =:= 0,
			S1#co_session.gencrc ->
			     co_crc:update(S1#co_session.blkcrc,Data1);
			true ->
			     S1#co_session.blkcrc
		     end,
	    PDU = #sdo_block_segment { last = ?UINT1(Last),
				       seqno = S1#co_session.blkseq,
				       d = Data1
				     },
	    S2 = S1#co_session { 
		   skipcrc = Skip,
		   last = ?UINT1(Last),
		   blkseq = S1#co_session.blkseq+1,
		   blkcrc = BlkCrc
		  },
	    send(Ctx,S2, PDU);

       D =:= upload ->
	    PDU = #sdo_scs_upload_segment_response {
	      n  = 7 - ?NBYTES(NBits1),
	      c  = ?UINT1(Last),
	      t  = S#co_session.t,
	      d  = Data 
	     },
	    S2 = S1#co_session { last = Last },
	    S3 = send(Ctx, S2, PDU),
	    if Last -> delete(S3, 0); true -> S3 end;
       D =:= download ->
	    PDU = #sdo_ccs_download_segment_request {
	      n  = 7 - ?NBYTES(NBits1),
	      c  = ?UINT1(Last),
	      t  = S#co_session.t,
	      d  = Data 
	     },
	    S2 = S1#co_session { last = Last },
	    S3 = send(Ctx, S2, PDU),
	    if Last -> delete(S3, 0); true -> S3 end
    end.

%% send a complete block
send_block(C, S, D, I) when I < S#co_session.blksize, not S#co_session.last ->
    S1 = send_segment(C, S, D, true),
    send_block(C, S1, D, I+1);
send_block(_C, S, _D, _I) ->
    S.
