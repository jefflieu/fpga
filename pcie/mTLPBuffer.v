/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: 	This module is used to buffer TLP packets to have some kind of "look-ahead"
				what kind of packet is about to be received
				
Remarks		:

Revision	:
	Date	Author	Description

*/

`define TLP_MEMREQ	5'b0_0000
`define TLP_CMPL	5'b0_1010
`define TLP_IOREQ	5'b0_0010


module mTLPBuffer #(
	parameter pWIDTH=64, 
	parameter pDEPTH=16)(
	
	input 					i_InRxDv	,
	input 					i_InRxSop	,
	input 					i_InRxEop	,
	input 	[pWIDTH-1:0]	iv_InRxData	,
	input 					i_InRxErr	,
	input 					i_InRxEmpty	,
	output					o_InRxReady	,
	input 	[7:0]			i8_BarHit	,//Bar
	input 	[2:0]			i3_Function	,//Function


	output 					o_OutRxDv	,
	output 					o_OutRxSop	,
	output 					o_OutRxEop	,
	output 	[pWIDTH-1:0]	ov_OutRxData	,
	output 					o_OutRxErr	,
	output 					o_OutRxEmpty,
	input					i_OutRxReady,
	
	output 		o_NxtPktMemWr	,
	output 		o_NxtPktMemRd	,
	output 		o_NxtPktIOWr	,
	output 		o_NxtPktIORd	,
	output 		o_NxtPktCmplD	,	//Completion With Data
	output 		o_NxtPktCmpl	,	//Completion Without Data
	output 		o_NxtPktOthers	,
	output 	[7:0]	o8_NxtPktBarHit	,//Bar
	output 	[2:0]	o3_NxtPktFuncHit,//Function	
	output	[9:0]	o10_NxtPktPayldLen,
	
	input 	i_Clk,
	input 	i_ARst);
	
	
	reg [7:0] r8_BarHit;
	reg [2:0] r3_Function;
	reg r_Sop_D;
	wire 	w_MemWrReq,w_MemRdReq,w_IOWrReq,w_IORdReq,w_CmplD,w_Cmpl;
	wire 	[1:0]	w2_Fmt;
	wire 	[4:0]	w5_Type;
	wire 	w_Empty,w_AlmostFull;
	wire 	[31:0]	w32_FlagsIn,w32_FlagsOut;
	wire 	w_FlagsFifoRd,w_FlagsFifoWr,w_TLPFifoRd,w_FlagsFifoEmpty;
	wire 	[9:0]	w10_Length;
	
	//PARSER	
	mAltPcieAst64Dec u0Ast64Decode(
	.i_AstRxSop		(i_InRxSop		),
	.i_AstRxEop		(i_InRxEop		),
	.i_AstRxEmpty	(i_InRxEmpty	),//NotUsed
	.i_AstRxDv		(i_InRxDv		),
	.iv_AstRxData	(iv_InRxData	),
	
	.o2_Fmt			(w2_Fmt		),	//Header Format
	.o5_Type		(w5_Type	),	//Header Type
	.o3_TrfcCls		(),	//Trafic Class
	.o2_Attr		(),	//Attribute		
	.o_TLPDigest	(),	//Digest Present
	.o_EP			(),	//Poissoned
	.o10_Length		(w10_Length	),	//Length in Double Word
	.o64_Addr		(),	//Address
	
	.o16_DescReqID	(),	//Requester ID
	.o8_DescTag		(),	//Tag	
	.o4_DescLastDWBE(),	//Last Double Word Byte Enable
	.o4_DescFrstDWBE(),	//First Double Word Byte Enable
	
	.o64_TLPData		(),	//PacketData, the handler has to know the data format and boundary
	.o10_WordCnt		(),
	
	.i_Clk		(i_Clk	),
	.i_ARst		(i_ARst	));
	

	//TLP FIFO	
	mSyncFifo #(
		.pWIDTH(pWIDTH+4),
		.pDEPTH(pDEPTH),
		.pALMOSTFULL(pDEPTH-4),
		.pALMOSTEMPTY(4),
		.pLOOKAHEAD("ON"))
		u0TLPFifo(
	.i_Clk	(i_Clk			),
	.i_Rd	(w_TLPFifoRd	),
	.i_Wr	(i_InRxDv		),
	.iv_Din	({i_InRxEmpty,i_InRxErr,i_InRxSop,i_InRxEop,iv_InRxData}),	
	
	.ov_Qout({o_OutRxEmpty,o_OutRxErr,o_OutRxSop,o_OutRxEop,ov_OutRxData}),
	
	//Flags
	.o_Full			(),
	.o_Empty		(w_Empty),
	.o_AlmostFull	(w_AlmostFull),
	.o_AlmostEmpty	(),
	
	.i_ARst		(i_ARst)//Reset pointer
	);
	assign o_OutRxDv 	= (~w_Empty)&w_TLPFifoRd;
	assign w_TLPFifoRd 	= i_OutRxReady;
	assign o_InRxReady 	= ~w_AlmostFull;
	
	
	
	assign w_MemWrReq 		= ( w2_Fmt[1]) & (w5_Type==`TLP_MEMREQ);
	assign w_MemRdReq 		= (~w2_Fmt[1]) & (w5_Type==`TLP_MEMREQ);
	assign w_IOWrReq		= ( w2_Fmt[1]) & (w5_Type==`TLP_IOREQ);
	assign w_IORdReq		= (~w2_Fmt[1]) & (w5_Type==`TLP_IOREQ);
	assign w_CmplD			= ( w2_Fmt[1]) & (w5_Type==`TLP_CMPL);
	assign w_Cmpl			= (~w2_Fmt[1]) & (w5_Type==`TLP_CMPL);
	assign w32_FlagsIn 		= {5'h0,w_MemWrReq,w_MemRdReq,w_IOWrReq,w_IORdReq,w_CmplD,w_Cmpl,w10_Length,r8_BarHit,r3_Function};
	assign w_FlagsFifoRd 	= o_OutRxEop & o_OutRxDv;
	assign w_FlagsFifoWr	= r_Sop_D;
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst) begin 
		r_Sop_D <= 1'b0;
		r8_BarHit <= 7'h0;
		r3_Function <= 3'h0;
		end
	else
		begin 
		r_Sop_D 		<= i_InRxSop & i_InRxDv;
		r8_BarHit 		<= i8_BarHit;
		r3_Function 	<= i3_Function;
		end
	
	mSyncFifo #(
		.pWIDTH(32),
		.pDEPTH(pDEPTH),
		.pALMOSTFULL(pDEPTH-4),
		.pALMOSTEMPTY(4),
		.pLOOKAHEAD("ON"))
	u0FlagsFifo(
		.i_Clk	(i_Clk			),
		.i_Rd	(w_FlagsFifoRd	),
		.i_Wr	(w_FlagsFifoWr	),
		.iv_Din	(w32_FlagsIn	),	
	
		.ov_Qout(w32_FlagsOut	),
	//Flags
		.o_Full			(),
		.o_Empty		(w_FlagsFifoEmpty),
		.o_AlmostFull	(),
		.o_AlmostEmpty	(),
	
		.i_ARst		(i_ARst)//Reset pointer
	); 	
	//Output 
	assign 	o_NxtPktMemWr	= w32_FlagsOut[26] & (~w_FlagsFifoEmpty);
	assign 	o_NxtPktMemRd	= w32_FlagsOut[25] & (~w_FlagsFifoEmpty);
	assign 	o_NxtPktIOWr	= w32_FlagsOut[24] & (~w_FlagsFifoEmpty);
	assign  o_NxtPktIORd	= w32_FlagsOut[23] & (~w_FlagsFifoEmpty);
	assign  o_NxtPktCmplD	= w32_FlagsOut[22] & (~w_FlagsFifoEmpty);
	assign 	o_NxtPktCmpl	= w32_FlagsOut[21] & (~w_FlagsFifoEmpty);
	assign 	o10_NxtPktPayldLen	= w32_FlagsOut[20:11];
	assign 	o8_NxtPktBarHit	= w32_FlagsOut[10:3];
	assign 	o3_NxtPktFuncHit= w32_FlagsOut[2:0];
    assign 	o_NxtPktOthers	= (~w_FlagsFifoEmpty)&(~(|w32_FlagsOut[26:21]));
endmodule 

