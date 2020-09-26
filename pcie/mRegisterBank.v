/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module handles
				IORead/Write
				MemRead/Write with Data Length not greater than 2DWs
			This module is suitable for status/configuration data 
Remarks		:

Revision	:
	Date	Author	Description

*/

module mRegisterBank #(parameter pADDRW=5)(
	input 	i_WbCyc,
	input 	i_WbStb,
	input 	i_WbWnR,
	output	reg o_WbAck,
	input 	[31:0]	i32_WbWrData,
	output	reg [31:0]	o32_WbRdData,
	input 	[pADDRW-1:0]	iv_WbAddr,
	input 	[3:0]	i4_ByteEn,
	input 	i_Clk,
	input 	i_ARst);
	
	
	localparam pREGNUM=2**pADDRW;
	
	reg 	[31:0]	r32v_REGS[0:pREGNUM-1];
	
	integer I;
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst) begin 
		for(I=0;I<pREGNUM;I=I+1)
			r32v_REGS[I] <= 32'h0;	
	end else begin 
		if(i_WbCyc&i_WbStb&i_WbWnR) begin 
				for(I=0;I<4;I=I+1)
				begin
					if(i4_ByteEn[I])	
						r32v_REGS[iv_WbAddr][I*8+7-:8] <= i32_WbWrData[I*8+7-:8];				
				end
			end
		if(i_WbCyc&i_WbStb&(~i_WbWnR)) 
			begin
				for(I=0;I<4;I=I+1)
				begin
					if(i4_ByteEn[I])	
						o32_WbRdData[I*8+7-:8] <= r32v_REGS[iv_WbAddr][I*8+7-:8];						
					else 
						o32_WbRdData[I*8+7-:8] <= 8'h0;						
				end				
			end
		o_WbAck <= 	(i_WbCyc&i_WbStb)&(~o_WbAck);
	end
endmodule 