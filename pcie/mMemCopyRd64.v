/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module will pull data from host memory to local device

Remarks		:

Revision	:
	Date	Author	Description

*/

`timescale 1ns/10ps

module mMemCopyRd64 #(parameter 		
	pMEM_BUFFER_NUM		= 16
	)(

	//Local Memory interface
	output 	o_MemWr,	
	output 	[pMEM_BUFFER_NUM-1:0]	ov_MemWrSel,	
	output 	[63:0]	ov_MemWrData,		
	output 	[31:0]	o32_MemWrAddr,
	output 	[07:0]	ov_MemWrByteEn,
	//Arbitration Interface
	output	[pMEM_BUFFER_NUM-1:0]	ov_MemWrReq,
	input	i_MemWrGranted,
	
//	//Command Q Interface 
//	output 	o_CmdPop,
//	input 	[63:0]	iv_CmdData,
//	input 	i_CmdValid,
	
	//Configuration bus interface 
	input 	i_CfgCyc,
	input 	i_CfgStb,
	input 	i_CfgWnR,	
	input 	[03:0]	i4_CfgAddr,
	input 	[31:0]	i32_CfgWrData,
	output 	[31:0]	o32_CfgRdData,
	output 	o_CfgAck,
	input 	i_CfgClk,
	
	//Avalon Stream RX
	input i_AstRxSop,
	input i_AstRxEop,
	input i_AstRxEmpty,//NotUsed
	input i_AstRxDv,
	input 	[63:0] 	iv_AstRxData,
	output 	o_AstRxReady,
	output 	o_AstRxMask,
	input 	[6:0]	i7_BARSelect,
	
	//Avalon Stream TX
	output 	o_AstTxSop,
	output 	o_AstTxEop,
	output 	o_AstTxEmpty,//NotUsed
	output 	o_AstTxDv,
	output 	[63:0] 	ov_AstTxData,
	input 	i_AstTxHIPReady,	
	
	//Credit interface	
	input  	[7:0] i8_CredLimPH,		//Posted Header
	input	[7:0] i8_CredLimCH,		//Completion Header
	input	[7:0] i8_CredLimNH,		//Non Posted Header	
	input	[11:0] i12_CredLimPD,	//Posted Data
	input	[11:0] i12_CredLimCD,	//Completion Data
	input	[11:0] i12_CredLimND,	//Nonposted Ddata
	
	input  	[7:0] i8_CredConPH,		//Posted Header
	input	[7:0] i8_CredConCH,		//Completion Header
	input	[7:0] i8_CredConNH,		//Non Posted Header	
	input	[11:0] i12_CredConPD,	//Posted Data
	input	[11:0] i12_CredConCD,	//Completion Data
	input	[11:0] i12_CredConND,	//Nonposted Ddata
	
	input 	i_InfinitePH,
	input 	i_InfiniteCH,
	input 	i_InfiniteNH,
	input 	i_InfinitePD,
	input 	i_InfiniteCD,
	input 	i_InfiniteND,
	
	output 	o_UpdNHCred,	
	output 	[07:0]	o8_IncNHCred,	
	
	output 	o_UpdRxCCred,
	output 	[07:0]	o8_RxRqdCHCred,	
	output 	[11:0]	o12_RxRqdCDCred,	
	
	
	input 	[15:0]	i16_RequestorID,//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
	input 	[11:0]	i12_MaxPload,	//Payload Size in Bytes
	input 	[11:0]	i12_MaxReadReq,	//Max Read Request Size in Bytes
	
	
	//Arbitration Interface
	output	o_ReqToTx,
	input	i_ReqGranted,
	
	output 	o_IrqMsiReq,
	input 	i_IrqMsiAck,
	output 	[4:0]	o5_IrqMsiNum,
	output 	[2:0]	o3_IrqMsiTfc,
	
	//Tag FIFO Interface 
	input 	i_TagAvail,
	input 	[7:0]	i8_TagNum,
	output 	o_TagPop,
	output 	o_TagPush,
	output 	[7:0]	o8_TagNum,
	
	//Rx Credit Interface 
	input	[7:0]	i8_AvailCredCH	,//
	input 	[11:0]	i12_AvailCredCD	,//
	
	output 	o_CplRcved,
	output	[7:0]	o8_RcvedCplCH	,//
	output 	[11:0]	o12_RcvedCplCD	,//
	
	input 	i_RootportRCB,

	input 	i_Clk,
	input 	i_ARst);


	/////////////////////////////////////////////////////////////
	// Configuration address layout
	//	0: Config Register
	//	1: Status register 
	// 	2: 32-bit LSB of 64 bit address
	//	3: 32-bit MSB of 64 bit address	
	//	4: Transfer Size
	//
	//	7: 32-bit interrupt timeout, interrupt generated when: either timeout or number of bytes is transfered
	/////////////////////////////////////////////////////////////
	reg [63:0]	r64_BufferBaseAddr;
	reg [08:0]	rv_Config;
	reg [31:0]	r32_LclMemOffset;	
	reg [31:0]	r32_CfgRdData;	
	reg [31:0]	r32_XferLenInByte,r32_IrqLevel;	
	wire[31:0]	wv_Status;	
	reg [31:0]	r32_RemainBytes;
	wire[07:0]	w8_CmplError;
	reg [10:0]	r11_CfgDWPerReq;
	reg 	r_CfgAck,r_UpdXferLen;		
	wire 	w_Use32bitAddr;
	//Configuration handling
	//Synchronize the reset first
	reg r_CfgResetD1,r_CfgResetD2;
	always@(posedge i_CfgClk or posedge i_ARst)
		if(i_ARst) begin 
			r_CfgResetD1 <= 1'b1;
			r_CfgResetD2 <= 1'b1;
			end
		else begin 
			r_CfgResetD1 <= 1'b0;
			r_CfgResetD2 <= r_CfgResetD1;					
		end
	always@(posedge i_CfgClk or posedge r_CfgResetD2)
	if(r_CfgResetD2)
		begin 
			rv_Config 			<= 0;
			r64_BufferBaseAddr 	<= 64'h0;						
			r32_LclMemOffset	<= 32'h0;
			r32_XferLenInByte	<= 32'h0;
			r_CfgAck 			<= 1'b0;			
			r_UpdXferLen		<= 1'b0;
			r32_IrqLevel		<= 32'h0100;
			r11_CfgDWPerReq		<= 11'h0;
		end 		
	else 
		begin 
			r11_CfgDWPerReq <= ({1'b0,i12_MaxReadReq[11:2]}<r11_CfgDWPerReq)?{1'b0,i12_MaxReadReq[11:2]}:r11_CfgDWPerReq;			
			if(i_CfgCyc & i_CfgStb & i_CfgWnR)
				begin 
					case(i4_CfgAddr)
					4'h0	:	rv_Config 	<= i32_CfgWrData[8:0];					
					4'h2	:	r11_CfgDWPerReq				<=	i32_CfgWrData[10:0];
					4'h3	: 	r32_IrqLevel				<= 	i32_CfgWrData;
					4'h4	: 	r64_BufferBaseAddr[31:00] 	<= 	i32_CfgWrData;
					4'h5	: 	r64_BufferBaseAddr[63:32] 	<= 	i32_CfgWrData;
					4'h6	:	r32_LclMemOffset			<=	i32_CfgWrData;
					4'h7	:	r32_XferLenInByte			<=	i32_CfgWrData;			
					endcase				
				end
				
			if(i_CfgCyc & i_CfgStb & i_CfgWnR & r_CfgAck & (i4_CfgAddr==4'h7))
				r_UpdXferLen <= ~r_UpdXferLen;		
			r_CfgAck  <= i_CfgCyc & i_CfgStb & (~r_CfgAck);		
		end
	always@(*)
		begin 
			case(i4_CfgAddr)
			4'h0:	r32_CfgRdData <= rv_Config;
			4'h1:	r32_CfgRdData <= wv_Status;
			//4'h2:	
			4'h3:	r32_CfgRdData <= r11_CfgDWPerReq;
			4'h4:	r32_CfgRdData <= r64_BufferBaseAddr[31:00];
			4'h5:	r32_CfgRdData <= r64_BufferBaseAddr[63:32];
			4'h6:	r32_CfgRdData <= r32_LclMemOffset;
			4'h7:	r32_CfgRdData <= r32_RemainBytes;
			default: r32_CfgRdData <= 32'h0;
			endcase 			
		end 
	
	assign o_CfgAck = r_CfgAck;
	assign o32_CfgRdData = r32_CfgRdData;
	
	
	
	////////////////////////////////////////////////////
	// Controller 
	///////////////////////////////////////////////////
	/*
	Generate memory read request 	
	*/
	localparam pIDLE_STOP	= 5'b00001;	
	localparam pREQTOSEND	= 5'b00010;
	localparam pCALC_CRED	= 5'b00100;
	localparam pSEND_REQ	= 5'b01000;
	localparam pSEND_DONE	= 5'b10000;
	
	reg r_Enable,r_EnableD1;
	reg r_RstEngine,r_RstEngineD1;
	reg [31:0]	r32_PullAddr,r32_TagLclMemAd;	
	reg [04:0]	r5_ReqtorState;
	reg [07:0]	r8_RqdNHCred;		//Cummulative Required Header Credit
	reg [07:0]	r8_IncNHCred;		//Incremental Header Credit Required	
	reg [07:0]	r8_RqdCHCred;		//Required Completion Header Credit
	reg [011:0]	r12_RqdCDCred;		//Required Completion Data Credit
	reg	r_EnoughNHCred;	
	reg	r_EnoughCHCred;
	reg	r_EnoughCDCred;	
	reg	r_ReqToTx;												//Arbitrate to transmit
	reg	r_TxLine;												//0: first line, 1 second line
	reg	[9:0]	r10_Length;										//Length of Read Request in DW
	reg [63:0]	r64_TxData;										//Transmit data
	reg	r_TxSop, r_TxEop, r_TxDv;								//Avalon Stream Signally
	wire [7:0]	w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3;
	wire [7:0]	w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7;
	wire [7:0]	w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB;
	wire [7:0]	w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF;
	reg  [3:0]	w4_FrstBE;
	wire [1:0]	w2_ReqFmt;										//2 bit format
	wire [4:0]	w5_ReqType;										//5 bit type
	wire [2:0]	w3_ReqStatus;									//Status	
	wire [2:0]	w3_TrfcCls;
	wire 	w_4DWHdr,w_DataReady,w_GenerateMSI;		
	reg		r_MsiReq,r_MsiDone,r_ReqDone,r_New;					//Send MSI request, after acknowledge MSI done is raised,	
	reg 	r_UpdBaseAddrD1,r_UpdBaseAddrD2,r_UpdBaseAddrD3;
	reg 	r_UpdXferLenD1,r_UpdXferLenD2,r_UpdXferLenD3;	
	reg 	[12:0]	r13_DistTo4KBBndry;
	reg 	[12:0]	r13_NextReqLenByte,r13_Smaller;			
	reg 	r_Done1stCycle,r_Done2ndCycle;
	reg 	[2:0]	r3_EndAddr;
	reg 	[10:0]	r11_DWPerReq;
	reg 	[07:0]	r8_OstdngReq;								//Outstanding Requests 
		
	
	assign w3_TrfcCls		= 3'h0;	
	assign 	w_4DWHdr		= ((r64_BufferBaseAddr[63:32]==32'h0)?1'b0:1'b1);
	assign 	w2_ReqFmt 		= {1'b0,w_4DWHdr};
	assign 	w5_ReqType		= 5'b0_0000;
	assign 	w8_ReqByte0		= {1'b0,w2_ReqFmt,w5_ReqType};
	assign 	w8_ReqByte1		= {1'b0,w3_TrfcCls,4'b000};
	assign 	w8_ReqByte2		= {1'b0,1'b0,2'b00,2'b00,r10_Length[9:8]};
	assign 	w8_ReqByte3		= {r10_Length[7:0]};
	
	assign 	w3_ReqStatus	= 3'b000;
	
	//This can be assigned multi-cyle path if necessary	
	assign 	w8_ReqByte4	= i16_RequestorID[15:8];
	assign 	w8_ReqByte5	= i16_RequestorID[07:0];	
	assign 	w8_ReqByte6	= i8_TagNum;
	
	///////////////////////////////////////////////////
	// Encoding of First BE for the case of 1 DW transfer
	///////////////////////////////////////////////////
	always@(*)
		case({r32_PullAddr[1:0],r13_NextReqLenByte[1:0]})
		4'b0000: w4_FrstBE<=4'b1111;
		4'b0001: w4_FrstBE<=4'b0001;
		4'b0010: w4_FrstBE<=4'b0011;
		4'b0011: w4_FrstBE<=4'b0111;
		4'b0100: w4_FrstBE<=4'b0010;
		4'b0101: w4_FrstBE<=4'b0010;
		4'b0110: w4_FrstBE<=4'b0110;
		4'b0111: w4_FrstBE<=4'b1110;
		4'b1000: w4_FrstBE<=4'b1110;
		4'b1001: w4_FrstBE<=4'b0100;
		4'b1010: w4_FrstBE<=4'b1100;
		4'b1011: w4_FrstBE<=4'b1100;
		4'b1100: w4_FrstBE<=4'b1100;
		4'b1101: w4_FrstBE<=4'b1000;
		4'b1110: w4_FrstBE<=4'b1000;
		4'b1111: w4_FrstBE<=4'b1000;
		endcase
	assign 	w8_ReqByte7	= (r10_Length==10'h1)?{4'h0,w4_FrstBE}:{((r3_EndAddr[1:0]==2'b00)?4'b1111:((r3_EndAddr[1:0]==2'b01)?4'b0001:((r3_EndAddr[1:0]==2'b10)?4'b0011:4'b0111))),
							((r32_PullAddr[1:0]==2'b00)?4'b1111:((r32_PullAddr[1:0]==2'b01)?4'b1110:((r32_PullAddr[1:0]==2'b10)?4'b1100:4'b1000)))};
		
	assign 	w8_ReqByte8 = w_4DWHdr?r64_BufferBaseAddr[63:56]:r32_PullAddr[31:24];
	assign 	w8_ReqByte9 = w_4DWHdr?r64_BufferBaseAddr[55:48]:r32_PullAddr[23:16];
	assign 	w8_ReqByteA = w_4DWHdr?r64_BufferBaseAddr[47:40]:r32_PullAddr[15:08];
	assign 	w8_ReqByteB = w_4DWHdr?r64_BufferBaseAddr[39:32]:{r32_PullAddr[07:02],2'b00};
	assign 	w8_ReqByteC = w_4DWHdr?r32_PullAddr[31:24]:8'h0;
	assign 	w8_ReqByteD = w_4DWHdr?r32_PullAddr[23:16]:8'h0;
	assign 	w8_ReqByteE = w_4DWHdr?r32_PullAddr[15:08]:8'h0;
	assign 	w8_ReqByteF = w_4DWHdr?{r32_PullAddr[07:02],2'b00}:8'h0;
		
	//////////////////////////////////////////////////////////
	// Data ready when the number requested bytes is not zero
	//////////////////////////////////////////////////////////
	assign w_DataReady 	= (r13_NextReqLenByte!=0)?1'b1:1'b0;
	assign wv_Status 	= {4'h0,w8_CmplError,i12_MaxPload,~(|r8_OstdngReq),r_ReqDone,i_TagAvail,r5_ReqtorState};
	assign w_GenerateMSI= rv_Config[3]?(~(|r8_OstdngReq)):((r32_RemainBytes<=r32_IrqLevel)?1'b1:1'b0);
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			r5_ReqtorState 				<= pIDLE_STOP;		
			r_ReqToTx 					<= 1'b0;
			r_EnoughNHCred 				<= 1'b0;			
			r_EnoughCHCred 				<= 1'b0;
			r_EnoughCDCred				<= 1'b0;			
			r8_RqdNHCred				<= 8'h0;			
			r8_IncNHCred				<= 8'h0;			
			r32_PullAddr				<= 32'h0;			
			r13_DistTo4KBBndry 			<= 13'h0;
			r13_NextReqLenByte 			<= 13'h0;
			r_Enable					<= 1'b0;
			r_EnableD1 					<= 1'b0;
			r_Done1stCycle 				<= 1'b0;
			r_Done2ndCycle 				<= 1'b0;		
			r_MsiReq					<= 1'b0;						
			r_RstEngine					<= 1'b0;
			r_RstEngineD1				<= 1'b0;						
			r8_RqdCHCred				<= 8'h0;
			r12_RqdCDCred				<= 12'h0;
			r_TxLine					<= 1'b0;			
			r_UpdXferLenD1	<= 1'b0;
			r_UpdXferLenD2	<= 1'b0;
			r_UpdXferLenD3	<= 1'b0;	
			r_ReqDone		<= 1'b1;
			r_MsiDone		<= 1'b0;
			r_TxDv			<= 1'b0;
			r_TxEop			<= 1'b0;
			r_TxSop 		<= 1'b0;
			r10_Length		<= 10'h0;
			r64_TxData		<= 64'h0;
			r_New			<= 1'b0;
			r3_EndAddr		<= 3'h0;
			r32_TagLclMemAd <= 3'h0;
		end
	else 
		begin 
		
		r_UpdXferLenD1<=r_UpdXferLen;
		r_UpdXferLenD2<=r_UpdXferLenD1;
		r_UpdXferLenD3<=r_UpdXferLenD2;
		
		r_EnableD1 		<= rv_Config[0];
		r_Enable		<= r_EnableD1;
		r_RstEngineD1	<= rv_Config[1];
		r_RstEngine		<= r_RstEngineD1;
		
						
		if(r_UpdXferLenD2^r_UpdXferLenD3)
			r_New	<= 1'b1;
		else if(r_New&r_ReqDone)
			r_New	<= 1'b0;
		
		if(r_New&r_ReqDone)	
			begin 
			r32_TagLclMemAd	<= r32_LclMemOffset;
			r_MsiDone		<= 1'b0;
			r32_RemainBytes <= r32_XferLenInByte;
			r32_PullAddr 	<= r64_BufferBaseAddr[31:0];		
			r11_DWPerReq	<= (r11_CfgDWPerReq==0)?i12_MaxReadReq[11:2]:(r11_CfgDWPerReq[10]?11'd1024:r11_CfgDWPerReq);
			end
		
		
		//Calculate the next data packet 
		r13_DistTo4KBBndry 	<= 13'h1000-{1'b0,r32_PullAddr[11:0]};
		r13_Smaller			<= (r32_RemainBytes>={21'h0,r11_DWPerReq,2'b00})?{r11_DWPerReq,2'b00}:{r32_RemainBytes[12:0]};
		r13_NextReqLenByte 	<= (r13_DistTo4KBBndry>r13_Smaller)?r13_Smaller:r13_DistTo4KBBndry;
				
		case(r5_ReqtorState)
		pIDLE_STOP:	begin 
						if(r_RstEngine)
							begin 
								r_New				<= 1'b0;
								r32_RemainBytes 	<= 0;					
								r32_PullAddr 		<= r64_BufferBaseAddr[31:0];	
							end
						else if(w_DataReady&i_TagAvail&r_Enable) 	
							begin 
								r5_ReqtorState <= pREQTOSEND;
								r8_RqdNHCred <= (i8_CredConNH + 8'h1);			//Always Consume 1 ReqHdr										
								r8_IncNHCred <= 8'h1;											
																
								//Calculate how many DW to request
								r10_Length 	<= 	r13_NextReqLenByte[11:2]+((r13_NextReqLenByte[1:0]==2'b00)?10'h0:10'h1);
								r_TxLine	<= 	1'b0;																
								r_ReqDone	<=  1'b0;								
								r3_EndAddr 	<= 	r32_PullAddr[2:0]+r13_NextReqLenByte[2:0];
							end
					r_EnoughNHCred <= 1'b0;										
					r_EnoughCHCred <= 1'b0;
					r_EnoughCDCred <= 1'b0;
					end
		pREQTOSEND:	begin 
						//This can be specified to be 2 cycle path
						if(|r10_Length)	
							begin 
								r8_RqdCHCred	<= 	(i_RootportRCB)?({3'h0,r10_Length[9:5]}+(r10_Length[4:0]!=0?8'h1:8'h0)):(
													({3'h0,r10_Length[9:4]}+(r10_Length[3:0]!=0?8'h1:8'h0)));
																								
								r12_RqdCDCred	<= {3'h0,r10_Length[9:1]}+(r10_Length[0]?12'h1:12'h0);
							end
						else 
							begin 
								r8_RqdCHCred	<= 	(i_RootportRCB)?8'd32:8'd64;						
								r12_RqdCDCred	<= 	12'd256;
							end
							
						r_ReqToTx <= 1'b1;
						if(i_ReqGranted)							
							r5_ReqtorState <= pCALC_CRED;
					end		
		pCALC_CRED:	begin 
						r_EnoughNHCred <= ((i8_CredLimNH-r8_RqdNHCred)<8'h80)?1'b1:1'b0;
						r_EnoughCHCred <= (i8_AvailCredCH>=r8_RqdCHCred)?1'b1:1'b0;
						r_EnoughCDCred <= (i12_AvailCredCD>=r12_RqdCDCred)?1'b1:1'b0;
						if(r_EnoughNHCred&r_EnoughCDCred&r_EnoughCHCred)
							r5_ReqtorState <= pSEND_REQ;
					end		
		pSEND_REQ:	begin
						if(i_AstTxHIPReady)
							begin
								r_TxDv 	<= 1'b1;							
								if(r_TxLine==1'b0)
									begin 									
									r_TxSop 	<= 1'b1;
									r_TxEop 	<= 1'b0;
									r64_TxData 	<= {w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7,
													w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3};																							
									end
								else 
									begin 
									r_TxSop 	<= 1'b0;
									r_TxEop 	<= 1'b1;
									r64_TxData	<= {w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF,
													w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB};																							
									end
								r_TxLine <= 1'b1;
								if(r_TxEop)
									begin 
										r_ReqToTx <= 1'b0;
										r_TxDv <= 1'b0;
										r_TxEop<= 1'b0;
										r_TxSop<= 1'b0;										
										r32_PullAddr<= (r32_PullAddr+{19'h0,r13_NextReqLenByte});
										r32_RemainBytes <= r32_RemainBytes-{19'h0,r13_NextReqLenByte};
										r32_TagLclMemAd <= r32_TagLclMemAd+{19'h0,r13_NextReqLenByte};
										r_Done1stCycle <= 1'b0;
										r_Done2ndCycle <= 1'b0;
										r5_ReqtorState <= pSEND_DONE;
									end
									
							end 
						else 
							begin 
								r_TxDv 	<= 1'b0;
								r_TxSop	<= 1'b0;
								r_TxEop	<= 1'b0;
							end
					end
		pSEND_DONE:	begin 						
						r_Done1stCycle <= 1'b1; 			//1 cycle: Calculating r13_DistTo4KBBndry
						r_Done2ndCycle <= r_Done1stCycle;	//2 cycle: Calculating r13_NextReqLenByte
						r_MsiReq 		<= rv_Config[2]&(~r_MsiDone)&r_Done1stCycle&w_GenerateMSI;
						if(r_Done2ndCycle & ((~r_MsiReq)|(r_MsiReq&i_IrqMsiAck)))
							begin 
							r5_ReqtorState 	<= pIDLE_STOP;	
							if(r_MsiReq)
								begin 			
									r_MsiReq		<= 1'b0;							
									r_MsiDone		<= 1'b1;
								end				
							r_ReqDone <= (r32_RemainBytes==0)?1'b1:1'b0;
							end
					end 						
		
		endcase	
		end
		
		
		
		assign o_ReqToTx 	= r_ReqToTx;
		assign o_AstTxDv 	= r_TxDv;
		assign o_AstTxEop	= r_TxEop;
		assign o_AstTxSop	= r_TxSop;
		assign ov_AstTxData = r64_TxData;		
		assign o_TagPop		= r_TxEop&r_TxDv;

		assign o_UpdNHCred	= r_TxSop & r_TxDv;		
		assign o8_IncNHCred = r8_IncNHCred;
		
		assign o_UpdRxCCred		= r_TxSop & r_TxDv;
		assign o8_RxRqdCHCred	= r8_RqdCHCred;
		assign o12_RxRqdCDCred	= r12_RqdCDCred;
		
				
		assign o_IrqMsiReq	= r_MsiReq;
		assign o5_IrqMsiNum	= rv_Config[8:4];
		
		//Keep Track of Oustanding Requests 
		always@(posedge i_Clk or posedge i_ARst)
		if(i_ARst)
			r8_OstdngReq<=8'h0;
		else 
			if(o_TagPop & (~o_TagPush))
				r8_OstdngReq<=r8_OstdngReq+8'h1;
			else if((~o_TagPop )& o_TagPush)
				r8_OstdngReq<=r8_OstdngReq-8'h1;
			
		
		///////////////////////////////////////
		// Tag Info 
		///////////////////////////////////////
		wire [07:0]	w8_CplTag;
		wire [31:0]	w32_InfIn,w32_InfOut;		
		wire w_InfStore	;
		assign w8_CplTag = o8_TagNum;
		m2PortRAMBeh #(.pADDRW(8),.pDATAW(32)) uXactInfoRAM(	
			.iv_AddrA		(i8_TagNum			),	
			.iv_WrDataA		(r32_TagLclMemAd	),
			.ov_RdDataA		(),
			.i_WrEnA		(o_TagPop			),	
			.iv_ByteEnA		(4'hF),
			.iv_AddrB		(w8_CplTag	),	
			.iv_WrDataB		(w32_InfOut	),
			.ov_RdDataB		(w32_InfIn	),
			.i_WrEnB		(w_InfStore	),		
			.iv_ByteEnB		(4'hF),
			.i_Clk			(i_Clk));
		

	//Completion Handling
	mCmplHandler64 #(.pFIFO_MODE(0),.pMEM_BUFFER_NUM(pMEM_BUFFER_NUM)) uCmplHandler(			

	//Avalon Stream RX
	.i_AstRxSop		(i_AstRxSop		),
	.i_AstRxEop		(i_AstRxEop		),
	.i_AstRxEmpty	(i_AstRxEmpty	),//NotUsed
	.i_AstRxDv		(i_AstRxDv		),
	.iv_AstRxData	(iv_AstRxData	),
	.o_AstRxReady	(o_AstRxReady	),
	.o_AstRxMask	(o_AstRxMask	),
	.i7_BARSelect	(i7_BARSelect	),
		
	.i16_RequestorID(i16_RequestorID),	//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
	.i16_CmplInfo	(16'h0),		//This is meant to do some extra processing for each completion
	
	.o_TagPush	(o_TagPush),
	.o8_TagNum	(o8_TagNum),
	.iv_XactnInfo		(w32_InfIn	),
	.ov_XactnInfo		(w32_InfOut	),
	.o_XactnInfoWrite	(w_InfStore	),
	.o_CplRcved			(o_CplRcved		),
	.o8_RcvedCplCH		(o8_RcvedCplCH	),//
	.o12_RcvedCplCD		(o12_RcvedCplCD	),//
	
	//Local Buffer 
	.o_LclSof	(),				//	Local Data valid, not used
	.o_LclEof	(),				//	Local Data valid, not used
	.o_LclDv	(),				//	Local Data valid	
	.ov_LclData	(),
	
	//Local Memory interface
	.o_MemWr		(o_MemWr),	
	.ov_MemWrSel	(ov_MemWrSel),	
	.ov_MemWrData	(ov_MemWrData),		
	.o32_MemWrAddr	(o32_MemWrAddr),
	.ov_MemWrByteEn	(ov_MemWrByteEn),
	//Arbitration Interface
	.ov_MemWrReq	(ov_MemWrReq),
	.i_MemWrGranted	(i_MemWrGranted),
	
	.o8_CmplError	(w8_CmplError),
	
	.i_Clk	(i_Clk),
	.i_ARst	(i_ARst));
		
endmodule 
