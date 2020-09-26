/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: 	This module is used to moderate Incoming packets, It looks at the some preliminary info and deliver it to the engine 
				if the engine is ready		
				
Remarks		:

Revision	:
	Date	Author	Description

*/


module mTLPRxModerator #(parameter pENGINENUM=4)(
	input 		[pENGINENUM-1:0]	iv_EngineReady,
	output 	reg	[pENGINENUM-1:0]	ov_EngineEn,
	output 							o_TLPBuffRead	,

	input 	i_RxSop,
	input 	i_RxEop,
	input 	i_RxDv,
	
	input 	i_NxtPktMemWr	,
	input	i_NxtPktMemRd	,
	input	i_NxtPktIOWr	,
	input 	i_NxtPktIORd	,
	input 	i_NxtPktCmplD	,	//Completion With Data
	input 	i_NxtPktCmpl	,	//Completion Without Data
	input 	i_NxtPktOthers	,
	input 	[7:0]	i8_NxtPktBarHit	,//Bar
	input 	[2:0]	i3_NxtPktFuncHit,//Function	
	input 	[9:0]	i10_NxtPktPayldLen,
	input 	[7:0]	i8_NxtPktTag,
	
	input 	i_Clk,
	input 	i_ARst);


	
	reg r_TLPBufferRead;
	
	assign o_TLPBuffRead = r_TLPBufferRead;
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			r_TLPBufferRead <= 1'b0;
			ov_EngineEn 	<= 4'h0;
		end
	else 
		begin 
			//Searching and making decision who's going to recieve the packet 
			//This loop is very application specific
			if(~r_TLPBufferRead)
				begin 
				if((i_NxtPktMemWr|i_NxtPktMemRd|i_NxtPktIOWr|i_NxtPktIORd)&&(iv_EngineReady[0]))
					begin 
					ov_EngineEn <= 4'h1;
					r_TLPBufferRead <= 1'b1;
					end
				else if(i_NxtPktCmplD&iv_EngineReady[1])
					begin 
					ov_EngineEn <= 4'b0010;
					r_TLPBufferRead <= 1'b1;
					end
				else if(i_NxtPktOthers)
					begin 
						r_TLPBufferRead <= 1'b1;
					end
				end
			else 
				begin 
				if(i_RxEop & i_RxDv) //Stop Reading begin 
					begin 
					r_TLPBufferRead <= 1'b0;
					ov_EngineEn 	<= 4'h0;//Stop Everyone
					end
				end
		end
		


endmodule 