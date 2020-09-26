/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module will pull data from host memory to local device

Remarks		:
				This could be dangerous if the rootport returns the completions not in the order of requests 
Revision	:
	Date	Author	Description

*/
`define dTLP_TYPE_MEMRD		5'b0_0000
`define dTLP_TYPE_MEMWR		5'b0_0000
`define dTLP_TYPE_IORD		5'b0_0010
`define	dTLP_TYPE_IOWR		5'b0_0010
`define	dTLP_TYPE_CMPL		5'b0_1010

module mCmplHandler64 #(parameter pFIFO_MODE=1,	pMEM_BUFFER_NUM	= 8)(			

	//Avalon Stream RX
	input i_AstRxSop,
	input i_AstRxEop,
	input i_AstRxEmpty,//NotUsed
	input i_AstRxDv,
	input 	[63:0] 	iv_AstRxData,
	output 	o_AstRxReady,
	output 	o_AstRxMask,
	input 	[6:0]	i7_BARSelect,
		
	input 	[15:0]	i16_RequestorID,	//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
	input 	[15:0]	i16_CmplInfo,		//This is meant to do some extra processing for each completion
	
	output 	o_TagPush,
	output 	[07:0]	o8_TagNum,
	input 	[31:0]	iv_XactnInfo,
	output 	[31:0]	ov_XactnInfo,
	output 	o_XactnInfoWrite,
	output 	o_CplRcved,
	output	[7:0]	o8_RcvedCplCH	,//
	output 	[11:0]	o12_RcvedCplCD	,//
		
	
	//Local Buffer 
	output	o_LclSof,				//	Local Data valid, not used
	output	o_LclEof,				//	Local Data valid, not used
	output	o_LclDv,				//	Local Data valid	
	output 	[63:0]	ov_LclData,
	
	//Local Memory interface
	output 	o_MemWr,	
	output 	[pMEM_BUFFER_NUM-1:0]	ov_MemWrSel,	
	output 	[63:0]	ov_MemWrData,		
	output 	[31:0]	o32_MemWrAddr,
	output 	[07:0]	ov_MemWrByteEn,	
	output 	[pMEM_BUFFER_NUM-1:0]	ov_MemWrReq,	
	input 	i_MemWrGranted,
	
	output 	[07:0]	o8_CmplError,
	
	input 	i_Clk,
	input 	i_ARst);
	
	function integer log2;
		input integer I;
		integer logval;
		begin 
			logval = 0;
			while(I>1)
				begin 
				logval=logval+1;
				I=I>>1;
				end
			log2=logval;
		end
	endfunction 
	localparam pMEM_ID_WIDTH=log2(pMEM_BUFFER_NUM);
	
	
	wire [1:0] 	w2_Fmt			;	//Header Format
	wire [4:0]	w5_Type			;	//Header Type
	wire [2:0]	w3_TrfcCls		;	//Trafic Class
	wire [1:0]	w2_Attr			;	//Attribute		
	wire 		w_TLPDigest		;	//Digest Present
	wire 		w_EP			;	//Poissoned
	wire [9:0]	w10_Length		;	//Length in Double Word
	wire [63:0]	w64_Addr		;	//Address

	wire [15:0]	w16_ReqID	;		//Requester ID
	wire [07:0]	w8_Tag		;		//Tag	
	wire [03:0]	w4_LastDWBE	;		//Last Double Word Byte Enable
	wire [03:0]	w4_FrstDWBE	;		//First Double Word Byte Enable
	wire [11:0]	w12_CmplByteCnt	;	//Remaining data including in the current completion		
	wire [7:0]	w8_LowAddr;	
	wire 	w_CmplValid;
	
	mAltPcieAst64Dec uTLPDecode(
	.i_AstRxSop		(i_AstRxSop),
	.i_AstRxEop		(i_AstRxEop),
	.i_AstRxEmpty	(i_AstRxEmpty),//NotUsed
	.i_AstRxDv		(i_AstRxDv),
	.iv_AstRxData	(iv_AstRxData),
	
	.o2_Fmt			(w2_Fmt		),	//Header Format
	.o5_Type		(w5_Type	),	//Header Type
	.o3_TrfcCls		(w3_TrfcCls	),	//Trafic Class
	.o2_Attr		(w2_Attr	),	//Attribute		
	.o_TLPDigest	(w_TLPDigest),	//Digest Present
	.o_EP			(w_EP		),	//Poissoned
	.o10_Length		(w10_Length	),	//Length in Double Word
	.o64_Addr		(w64_Addr	),	//Address
	.o16_DescCplID	(),
	.o16_DescReqID	(w16_ReqID	),	//Requester ID
	.o8_DescTag		(w8_Tag		),	//Tag	
	.o4_DescLastDWBE(w4_LastDWBE),	//Last Double Word Byte Enable
	.o4_DescFrstDWBE(w4_FrstDWBE),	//First Double Word Byte Enable
	.o12_CmplByteCnt(w12_CmplByteCnt),
	.o64_TLPData	(			),	//PacketData, the handler has to know the data format and boundary
	.o10_WordCnt	(),	
	
	.i_Clk			(i_Clk		),
	.i_ARst			(i_ARst		));

	assign w8_LowAddr = w64_Addr[7:0];


generate 
if(pFIFO_MODE==1)
	begin:FIFO_MODE
	reg [11:00]	r12_RcvedCplCD;	
	reg [07:00]	rv_CmplError;	
	reg r_StartRecv,r_SecondWord,r_DataPhase;
	reg r_LclDv,r_LastCmpl;
	wire w_CplReqChk;
	assign w_CplReqChk = (i16_RequestorID==w16_ReqID)?1'b1:1'b0;
	assign w_CmplValid = ((w2_Fmt==2'b10)&&(w5_Type==`dTLP_TYPE_CMPL))?1'b1:1'b0;
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			rv_CmplError 	<= 8'h0;		
			r_StartRecv		<= 1'b0;
			r_SecondWord	<= 1'b0;
			r_LclDv			<= 1'b0;
			r_DataPhase		<= 1'b0;
			r12_RcvedCplCD	<= 12'h0;
		end 
	else 
		begin 			
						
			if(i_AstRxDv)	r_SecondWord <= i_AstRxSop;
			
			if(r_SecondWord & i_AstRxDv & (iv_AstRxData[2:0]!=3'b000))	rv_CmplError[0] <= pFIFO_MODE;
			r12_RcvedCplCD <= {3'h0,w10_Length[9:1]}+(w10_Length[0]?12'h1:12'h0);
			if(pFIFO_MODE)
				begin 
					if(r_SecondWord&i_AstRxDv&w_CmplValid) r_DataPhase <= 1'b1; 
					else if(i_AstRxDv&i_AstRxEop&w_CmplValid) r_DataPhase <= 1'b0; 						
					r_LastCmpl <= ({w10_Length,2'b00}==w12_CmplByteCnt)?w_CmplValid:1'b0;
				end 
			else 
				begin 
				
				
				end
		
		end
	
	assign o_LclDv 			= pFIFO_MODE?(r_DataPhase&i_AstRxDv&w_CplReqChk):1'b0;
	assign ov_LclData 		= iv_AstRxData;
	assign o8_TagNum		= w8_Tag;
	assign o_TagPush		= r_LastCmpl & i_AstRxEop & i_AstRxDv & w_CplReqChk;
	assign o_AstRxReady		= 1'b1;
	assign o8_RcvedCplCH	= 8'h1;
	assign o12_RcvedCplCD	= r12_RcvedCplCD; 
	assign o_CplRcved		= i_AstRxEop & i_AstRxDv & w_CplReqChk;
	assign o8_CmplError		= rv_CmplError;
	end
else 
	begin 
	localparam pIDLE		= 5'b0_0001;
	localparam pGET_INFO	= 5'b0_0010;
	localparam pREQ_MEM_ACC	= 5'b0_0100;
	localparam pWRITE_MEM	= 5'b0_1000;
	localparam pDONE		= 5'b1_0000;
	
	integer I;
	reg [pMEM_BUFFER_NUM-1:0]	rv_LclMemSel;
	reg [31:0] 	rv_LclMemAddr;
	reg	[04:00]	r5_CmplState;	
	reg [11:00]	r12_RcvedCplCD;
	reg r_MemWr;
	
	reg [07:00]	rv_CmplError;
	wire[07:00] w8_ByteEn;
	wire[03:00] w4_FrstBE,w4_LastBE;
	wire[03:00] w4_ByteEn7654,w4_ByteEn3210;
	reg r_StartRecv,r_SecondWord,r_DataPhase,r_FifoRd,r_TagPush;
	reg r_LclDv,r_DataPhase_D1,r_XactnInfoWrite;
	wire w_CplReqChk,w_DLastOne,w_1st8ByteData,w_LastCmpl;
	wire w_FifoWr,w_FifoRd,w_FifoEmpty,w_WrNotQWAligned,w_FifoFull;
	wire [72:0]	wv_CmplDin,wv_CmplDout;
	
	assign w_CplReqChk 		= 1'b1;
	assign w_CmplValid 		= ((w2_Fmt==2'b10)&&(w5_Type==`dTLP_TYPE_CMPL))?1'b1:1'b0;
	assign w_LastCmpl		= ({w10_Length,2'b00}==w12_CmplByteCnt)?w_CmplValid:1'b0;
	
	assign w_WrNotQWAligned	= (r_SecondWord & iv_AstRxData[2])?1'b1:1'b0;
	assign w_FifoWr			= (r_DataPhase&i_AstRxDv&w_CplReqChk)|(w_WrNotQWAligned);
	assign w4_FrstBE		= (w8_LowAddr[1:0]==2'b00)?4'b1111:((w8_LowAddr[1:0]==2'b01)?4'b1110:((w8_LowAddr[1:0]==2'b10)?4'b1100:4'b1000));
	assign w4_LastBE		= (w12_CmplByteCnt[1:0]==2'b00)?4'b1111:((w12_CmplByteCnt[1:0]==2'b01)?4'b0001:((w12_CmplByteCnt[1:0]==2'b10)?4'b0011:4'b0111));
	assign w4_ByteEn7654	= w_WrNotQWAligned?4'hF:((w_DLastOne&(w12_CmplByteCnt[2]^w8_LowAddr[2]))?4'h0:4'hF);
	assign w4_ByteEn3210	= w_WrNotQWAligned?4'h0:4'hF;
	assign w8_ByteEn		= {w4_ByteEn7654,w4_ByteEn3210};	
	assign w_DLastOne		= w_LastCmpl & i_AstRxEop & i_AstRxDv & w_CplReqChk;
	assign wv_CmplDin 		= {w_DLastOne,w8_ByteEn,iv_AstRxData};
	//Cmpl FIFO
	mSyncFifo #(
		.pWIDTH(73),
		.pDEPTH(32),
		.pALMOSTFULL(30),
		.pALMOSTEMPTY(2),
		.pLOOKAHEAD("ON"))
	uCplDataBuffer(
		.i_Clk	(i_Clk	),
		.i_Rd	(w_FifoRd),
		.i_Wr	(w_FifoWr),
		.iv_Din	(wv_CmplDin),	
	
		.ov_Qout(wv_CmplDout),
	//Flags
		.o_Full			(),
		.o_Empty		(w_FifoEmpty),
		.o_AlmostFull	(w_FifoFull),
		.o_AlmostEmpty	(),
	
		.i_ARst		(i_ARst)//Reset pointer
	); 	
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			rv_CmplError 	<= 8'h0;		
			r_StartRecv		<= 1'b0;
			r_SecondWord	<= 1'b0;
			r_DataPhase		<= 1'b0;
			r12_RcvedCplCD	<= 12'h0;
			r5_CmplState	<= pIDLE;
			r_DataPhase_D1	<= 1'b0;
			r_FifoRd		<= 1'b0;
			r_XactnInfoWrite<= 1'b0;
			r_TagPush 		<= 1'b0;
		end 
	else 
		begin

			r_DataPhase_D1<= r_DataPhase&i_AstRxDv;
						
			if(i_AstRxDv)	r_SecondWord <= i_AstRxSop;
			
			if(r_SecondWord & i_AstRxDv & (iv_AstRxData[2:0]!=3'b000))	
				rv_CmplError[0] <= pFIFO_MODE;
			r12_RcvedCplCD <= {3'h0,w10_Length[9:1]}+(w10_Length[0]?12'h1:12'h0);
			
			if(i_AstRxDv&i_AstRxEop&w_CmplValid) 
				r_DataPhase <= 1'b0;
			else if(r_SecondWord&i_AstRxDv&w_CmplValid) 
				r_DataPhase <= 1'b1; 
			 						
			r_TagPush 	<= 	w_LastCmpl & i_AstRxEop & i_AstRxDv & w_CplReqChk;
			
			
			if(w_FifoRd & (~w_FifoEmpty))
				begin 
					case(wv_CmplDout[71:64])
					8'h01,8'h80:rv_LclMemAddr<=rv_LclMemAddr+32'h1;
					8'h03,8'hC0:rv_LclMemAddr<=rv_LclMemAddr+32'h2;
					8'h07,8'hE0:rv_LclMemAddr<=rv_LclMemAddr+32'h3;
					8'h0F,8'hF0:rv_LclMemAddr<=rv_LclMemAddr+32'h4;
					8'h1F,8'hF8:rv_LclMemAddr<=rv_LclMemAddr+32'h5;
					8'h3F,8'hFC:rv_LclMemAddr<=rv_LclMemAddr+32'h6;
					8'h7F,8'hFE:rv_LclMemAddr<=rv_LclMemAddr+32'h7;
					8'hFF		: rv_LclMemAddr<=rv_LclMemAddr+8;
					default 	: rv_LclMemAddr<=rv_LclMemAddr;
					endcase
				end
			
			case(r5_CmplState)
			pIDLE		:	begin 
								if(!w_FifoEmpty) r5_CmplState <= pGET_INFO;
							end 
			pGET_INFO	:	begin 
								rv_LclMemAddr	<=iv_XactnInfo[31:0];
								for(I=0;I<pMEM_BUFFER_NUM;I=I+1)
										rv_LclMemSel[I]<=(iv_XactnInfo[31-:pMEM_ID_WIDTH]==I)?1'b1:1'b0;
																
								r5_CmplState	<= pREQ_MEM_ACC;								
							end
			pREQ_MEM_ACC:	if(i_MemWrGranted)  
							begin 
								r_FifoRd	<= 1'b1;	
								r5_CmplState<= pWRITE_MEM;							
							end 
			pWRITE_MEM	:	if(wv_CmplDout[72]&w_FifoRd & (~w_FifoEmpty))
							begin 								
								r_FifoRd	<= 1'b0;
								r_XactnInfoWrite <= 1'b1;	//Update the Xaction Info so that it can continue next cmpletion 
								r5_CmplState<= pDONE;
							end
			pDONE		:	begin 								
								rv_LclMemSel		<=0;
								r_XactnInfoWrite 	<= 1'b1;	
								r5_CmplState		<=pIDLE;
							end
			default		:	r5_CmplState <=pIDLE;
			endcase 			
		end
	
	
	
	assign o8_TagNum		= w8_Tag;
	assign o_TagPush		= r_TagPush;
	assign o_AstRxReady		= ~w_FifoFull;
	assign o8_RcvedCplCH	= 8'h1;
	assign o12_RcvedCplCD	= r12_RcvedCplCD; 
	assign o_CplRcved		= i_AstRxEop & i_AstRxDv & w_CplReqChk;
	assign o8_CmplError		= rv_CmplError;
	
	//////////////////////////////////////////////////
	//	Memory Interface 
	//////////////////////////////////////////////////
	assign w_FifoRd			= r_FifoRd;
	assign o_MemWr			= w_FifoRd & (~w_FifoEmpty);
	assign ov_MemWrSel		= rv_LclMemSel&{pMEM_BUFFER_NUM{o_MemWr}};
	assign ov_MemWrReq		= rv_LclMemSel;	
	assign ov_MemWrByteEn	= wv_CmplDout[71:64];
	assign ov_MemWrData		= wv_CmplDout[63:00];
	assign o32_MemWrAddr	= rv_LclMemAddr;
	assign ov_XactnInfo		= rv_LclMemAddr;
	assign o_XactnInfoWrite	= 1'b0;//(r5_CmplState==pDONE)?1'b1:1'b0;
	end 
endgenerate
	
endmodule 