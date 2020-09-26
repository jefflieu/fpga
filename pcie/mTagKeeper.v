/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: 	This module is used to keep tags and issues to MemRd requesters
				
Remarks		:

Revision	:
	Date	Author	Description

*/


module mTagKeeper(
	
	input i_ExtTag,
	
	input i_TagPop,
	input i_TagPush,	
	
	input 	[7:0]	i8_TagReturned,
	output 	[7:0]	o8_TagIssued,
	
	output 	o_TagAvail,
	
	input i_Clk,
	input i_ARst
);
	reg r_Init;
	reg r_ExtTag;
	reg 	[7:0]	r8_Tag;
	wire 	[7:0]	w8_TagIn;
	reg r_TagInit;
	wire w_TagPush, w_TagPop;
	wire w_TagFlush, w_NoTag;
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			r_ExtTag<= 1'b0;
			r_Init	<= 1'b1;		
			r8_Tag	<= 8'h0;
		end
	else 
		begin 			
			r_ExtTag <= i_ExtTag;
			if(r_Init)
				begin 
					r_TagInit <= 1'b1;
					if(r_TagInit)
						begin 
						r8_Tag	<= r8_Tag+1;
						if((i_ExtTag==1'b1 && r8_Tag==8'hFF)||(i_ExtTag==1'b0 && r8_Tag==8'h1F))
							begin
							r_TagInit <= 1'b0;
							r_Init	<= 1'b0;
							end						
						end 
				end 
			else 
				begin
					r_Init <= (r_ExtTag^i_ExtTag);
				end	
		end

	assign w_TagPush = (r_Init&r_TagInit)|((~r_Init)&i_TagPush);
	assign w_TagFlush= 	((~r_Init)&(r_ExtTag^i_ExtTag))|i_ARst;
	assign w_TagPop	 = (~r_Init)&i_TagPop;
	assign w8_TagIn	 = r_Init?r8_Tag:i8_TagReturned;
	//Tag FIFO
	mSyncFifo #(
		.pWIDTH(8),
		.pDEPTH(256),
		.pALMOSTFULL(255),
		.pALMOSTEMPTY(1),
		.pLOOKAHEAD("ON"))
	u0FlagsFifo(
		.i_Clk	(i_Clk			),
		.i_Rd	(w_TagPop),
		.i_Wr	(w_TagPush),
		.iv_Din	(w8_TagIn),	
	
		.ov_Qout(o8_TagIssued),
	//Flags
		.o_Full			(),
		.o_Empty		(w_NoTag),
		.o_AlmostFull	(),
		.o_AlmostEmpty	(),
	
		.i_ARst		(w_TagFlush)//Reset pointer
	); 	
	assign o_TagAvail = (~w_NoTag)&(~r_Init);
	
endmodule 