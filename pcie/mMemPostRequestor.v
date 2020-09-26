/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module will stream data from local device to host memory
				- Support 64-bit addressing
				- Not Support Byte Level Transfer, only support even number of DW transfer
				- Only support 64-bit aligned address 
				- Not suport 4096-Byte Payload system, max payload the code can support is 2048 byte 
				- Completion timeout is not supported yet, completion time-out can be implemented in the Tag Keeper
				
Remarks		:

Revision	:
	Date	Author	Description

*/

`timescale 1ns/10ps

module mMemPostRequestor64 #(parameter 	
	pBUFFER_TAGWIDTH	=16,
	pREQ_TAG_LENGTH		=8,
	pTAG_PREFIX			=1'b0
	)(

	//Buffer interface
	input 	i_LclSof,				//	Local Data valid, not used
	input 	i_LclEof,				//	Local Data valid, not used
	input 	i_LclDv,				//	Local Data valid, can be 0 or 1 cycle delay of LclReq
	input 	[63:0]	iv_LclData,		//  Local Data
	output 	o_LclReq,				//	Local Data Read Request
	input 	[15:0]	iv_UsedWords,	// 	Local Daa Available 
	input 	i_LclEmpty,
	
	//Configuration bus interface 
	input 	i_CfgCyc,
	input 	i_CfgStb,
	input 	i_CfgWnR,	
	input 	[03:0]	i4_CfgAddr,
	input 	[31:0]	i32_CfgWrData,
	output 	[31:0]	o32_CfgRdData,
	output 	o_CfgAck,
	input 	i_CfgClk,
		
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
	
	output 	o_UpdPHCred,
	output 	o_UpdPDCred,
	output 	[07:0]	o8_IncPHCred,
	output 	[11:0]	o12_IncPDCred,
	
	
	input 	[15:0]	i16_RequestorID,//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
	input 	[11:0]	i12_MaxPload,	//Payload Size in Bytes
	
	//Arbitration Interface
	output	o_ReqToTx,
	input	i_ReqGranted,

	output 	o_IrqMsiReq,
	input 	i_IrqMsiAck,
	output 	[4:0]	o5_IrqMsiNum,
	output 	[2:0]	o3_IrqMsiTfc,
	
	//Rx Credit Interface 
	input	[7:0]	i8_AvailCredCH	,//Not used for Memory Post Write Requestor 	
	input 	[11:0]	i12_AvailCredCD	,//Not used for Memory Post Write Requestor

	input 	i_Clk,
	input 	i_ARst);


	/////////////////////////////////////////////////////////////
	// Configuration address layout
	//	0: Config Register
	//	1: Status register 
	// 	2: 32-bit LSB of 64 bit address
	//	3: 32-bit MSB of 64 bit address	
	//	4: Buffer Size, Buffer of size X must be aligned to X boundaries. E.g, 1MB buffer must be put at address XXX0_0000
	//					Also, the buffer must aligned to 4kB region
	//					Odd buffer size may not be guaranteed to work, e.g 1_000_000 bytes
	//	6 interval in Double Words (32-bit)
	//	7: 32-bit interrupt timeout, interrupt generated when: either timeout or number of bytes is transfered
	/////////////////////////////////////////////////////////////
	reg [31:0]	r32_BufferSize;
	reg [63:0]	r64_BufferBaseAddr;
	reg [08:0]	rv_Config;
	reg [31:0]	rv_IrqThreshold;
	reg [31:0]	rv_IrqTimeOut;//Actual time is equal Count*ClockCycles
	reg r_CfgAck;		
	wire w_Use32bitAddr;
	reg [31:0]	r32_CfgRdData;
	reg r_UpdBaseAddr;
	wire 	[31:0]	wv_Status;
	reg 	[19:0]	rv_IrqTimer;
	
	wire 	[31:0]	w32_DWIrqCount;
	
	wire 	w_DWCntFull,w_DWCntRdReq,w_DWCntWrReq,w_DWCntEmpty,w_DWCntAlmEmpty;
	reg		r_DWCntRdReq,r_DWCntRdReqD0,r_DWCntRdReqD1,r_DWCntRdReqD2;
	wire 	w_InvalidSetting;
	
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
			r64_BufferBaseAddr 	<= 64'h0;
			rv_Config <= 0;
			rv_IrqThreshold		<= 0;
			rv_IrqTimeOut		<= 0;		
			r_CfgAck 			<= 1'b0;
			r_UpdBaseAddr		<= 1'b0;
			r32_BufferSize		<= 0;
			r_DWCntRdReq		<= 1'b0;
		end 		
	else 
		begin 
			if(i_CfgCyc & i_CfgStb & i_CfgWnR)
				begin 
					case(i4_CfgAddr)
					4'h0	:	rv_Config <= i32_CfgWrData[8:0];					
					4'h2	:	if(~rv_Config [0])	r64_BufferBaseAddr[31:00] 	<= i32_CfgWrData;	//Address has to be aligned to be accepted
					4'h3	:	if(~rv_Config [0])	r64_BufferBaseAddr[63:32] 	<= i32_CfgWrData;
					4'h4	: 	if(~rv_Config [0])	r32_BufferSize				<= i32_CfgWrData;	//Size has to be aligned to be accepted 									
					4'h6	:	if(~rv_Config [0])	rv_IrqThreshold				<= {2'b0,i32_CfgWrData[31:2]};
					4'h7	:	if(~rv_Config [0])	rv_IrqTimeOut				<= i32_CfgWrData;
					endcase				
				end
			if(i_CfgCyc & i_CfgStb & i_CfgWnR & r_CfgAck & (i4_CfgAddr==4'h3))		
				r_UpdBaseAddr <= ~r_UpdBaseAddr;
			r_CfgAck  <= i_CfgCyc & i_CfgStb & (~r_CfgAck);
			
			if(r_CfgAck&i_CfgCyc&i_CfgStb && (i4_CfgAddr==4'h6)&(~i_CfgWnR))	
				r_DWCntRdReq <= ~r_DWCntRdReq;
			
		end
	assign w_InvalidSetting = (r64_BufferBaseAddr[5:0]!=6'h0)||(|((r32_BufferSize-32'h1)&r64_BufferBaseAddr[31:0]));
	always@(*)
		begin 
			case(i4_CfgAddr)
			4'h0:	r32_CfgRdData <= rv_Config;
			4'h1:	r32_CfgRdData <= wv_Status;
			4'h2:	r32_CfgRdData <= r64_BufferBaseAddr[31:00];
			4'h3:	r32_CfgRdData <= r64_BufferBaseAddr[63:32];
			4'h4:	r32_CfgRdData <= r32_BufferSize;
			4'h6:	r32_CfgRdData <= w_DWCntEmpty?32'h0:{w_DWCntAlmEmpty,w32_DWIrqCount[28:0],2'b00};						
			4'h7:	r32_CfgRdData <= rv_IrqTimeOut;
			default: r32_CfgRdData <= 32'h0;
			endcase 			
		end 
	
	assign o_CfgAck = r_CfgAck;
	assign o32_CfgRdData = r32_CfgRdData;
	////////////////////////////////////////////////////
	// Controller 
	// - Start a transmission if available data is more than payload or a time-out 
	//	
	///////////////////////////////////////////////////
	
	
	/*
	Generate memory post request 	
	*/
	localparam pIDLE_STOP	= 5'b00001;	
	localparam pREQTOSEND	= 5'b00010;
	localparam pCALC_CRED	= 5'b00100;
	localparam pSEND_REQ	= 5'b01000;
	localparam pSEND_DONE	= 5'b10000;
	
	reg r_Enable,r_EnableD1;
	reg r_RstEngine,r_RstEngineD1;
	reg [31:0]	r32_PostAddr;	
	reg [04:0]	r5_ReqtorState;
	reg [07:0]	r8_RqdPHCred;		//Cummulative Required Completion Header Credit
	reg [11:0]	r12_RqdPDCred;		//Cummulative Required Completion Data Credit
	reg [07:0]	r8_IncPHCred;		//Incremental Header Credit Required
	reg [11:0]	r12_IncPDCred;		//Incremental Data Credit Required 
	reg	r_EnoughPHCred;
	reg	r_EnoughPDCred;
	reg	r_ReqToTx;
	reg	[9:0]	r10_LineToSend_1,r10_LineSent;
	reg	[9:0]	r10_Length;
	reg [63:0]	r64_TxData;
	reg	r_TxSop, r_TxEop, r_TxDv;
	wire [7:0]	w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3;
	wire [7:0]	w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7;
	wire [7:0]	w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB;
	wire [7:0]	w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF;
	wire [1:0]	w2_ReqFmt;
	wire [4:0]	w5_ReqType;
	wire [2:0]	w3_ReqStatus;
	wire [7:0]	w8_Tag;
	wire [2:0]	w3_TrfcCls;
	wire 	w_4DWHdr,w_DataReady;	
	reg 	[pREQ_TAG_LENGTH-1:0]	rv_TagNum;
	reg		r_LclReq,r_MsiReq,r_TimeoutIrq;	
	reg 	r_UpdBaseAddrD1,r_UpdBaseAddrD2,r_UpdBaseAddrD3;
	reg 	[11:0]	r12_DistanceTo4KBBoundary;
	reg 	[11:0]	r12_NextPktPload;
	wire 	[31:0]	w32_BufferEndAddr;
	wire 	w_TimeOut,w_GenerateMSI;
	reg 	r_Done1stCycle,r_Done2ndCycle;
	reg 	[31:0]	r32_DWIrqCount;
	
	assign w32_BufferEndAddr = r64_BufferBaseAddr[31:0]+r32_BufferSize;
	assign w3_TrfcCls		= 3'h0;
	
	assign 	w_4DWHdr		= ((r64_BufferBaseAddr[63:32]==32'h0)?1'b0:1'b1);
	assign 	w2_ReqFmt 		= {1'b1,w_4DWHdr};
	assign 	w5_ReqType		= 5'b0_0000;
	assign 	w8_ReqByte0		= {1'b0,w2_ReqFmt,w5_ReqType};
	assign 	w8_ReqByte1		= {1'b0,w3_TrfcCls,4'b000};
	assign 	w8_ReqByte2		= {1'b0,1'b0,2'b00,2'b00,r10_Length[9:8]};
	assign 	w8_ReqByte3		= {r10_Length[7:0]};
	
	assign 	w3_ReqStatus	= 3'b000;
	
	//This can be assigned multi-cyle path if necessary
	assign 	w8_Tag		= {pTAG_PREFIX,rv_TagNum};	
	assign 	w8_ReqByte4	= i16_RequestorID[15:8];
	assign 	w8_ReqByte5	= i16_RequestorID[07:0];	
	assign 	w8_ReqByte6	= w8_Tag;
	assign 	w8_ReqByte7	= 8'hFF;
		
	assign 	w8_ReqByte8 = w_4DWHdr?r64_BufferBaseAddr[63:56]:r32_PostAddr[31:24];
	assign 	w8_ReqByte9 = w_4DWHdr?r64_BufferBaseAddr[56:48]:r32_PostAddr[23:16];
	assign 	w8_ReqByteA = w_4DWHdr?r64_BufferBaseAddr[47:40]:r32_PostAddr[15:08];
	assign 	w8_ReqByteB = w_4DWHdr?r64_BufferBaseAddr[39:32]:r32_PostAddr[07:00];
	assign 	w8_ReqByteC = w_4DWHdr?r32_PostAddr[31:24]:8'h0;
	assign 	w8_ReqByteD = w_4DWHdr?r32_PostAddr[23:16]:8'h0;
	assign 	w8_ReqByteE = w_4DWHdr?r32_PostAddr[15:08]:8'h0;
	assign 	w8_ReqByteF = w_4DWHdr?r32_PostAddr[07:00]:8'h0;
	
	assign w_GenerateMSI= r32_DWIrqCount>=rv_IrqThreshold||r_TimeoutIrq;
	assign w_TimeOut	= (rv_IrqTimer==1)?1'b1:1'b0;
	assign w_DataReady 	= ({iv_UsedWords[8:0],3'b0}>=r12_NextPktPload)?1'b1:(|iv_UsedWords[15:9]);
	assign wv_Status 	= {w_InvalidSetting,11'h0,i12_MaxPload,2'b00,w_DWCntFull,r5_ReqtorState};
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			r5_ReqtorState <= pIDLE_STOP;		
			r_ReqToTx 		<= 1'b0;
			r_EnoughPHCred 	<= 1'b0;
			r_EnoughPDCred	<= 1'b0;
			r12_RqdPDCred	<= 12'h0;
			r8_RqdPHCred	<= 8'h0;
			r10_LineSent	<= 2'b00;
			r8_IncPHCred	<= 8'h0;
			r12_IncPDCred	<= 12'h0;
			r10_LineToSend_1<= 2'b00;
			r_LclReq		<= 1'b0;
			r32_PostAddr	<= 32'h0;
			r_UpdBaseAddrD1	<= 1'b0;
			r_UpdBaseAddrD2	<= 1'b0;
			r_UpdBaseAddrD3	<= 1'b0;
			r12_DistanceTo4KBBoundary 	<= 12'h0;
			r12_NextPktPload 			<= 12'h0;
			r_Enable		<= 1'b0;
			r_EnableD1 		<= 1'b0;
			r_Done1stCycle 	<= 1'b0;
			r_Done2ndCycle 	<= 1'b0;
			rv_IrqTimer		<= 20'h0;
			rv_TagNum		<= 0;
			r_MsiReq		<= 1'b0;
			r_TimeoutIrq	<= 1'b0;
			r32_DWIrqCount	<= 0;
			r_RstEngine		<= 1'b0;
			r_RstEngineD1	<= 1'b0;
		end
	else 
		begin 
		
		//Clock domain synchronize
		r_UpdBaseAddrD1	<= r_UpdBaseAddr;
		r_UpdBaseAddrD2	<= r_UpdBaseAddrD1;
		r_UpdBaseAddrD3	<= r_UpdBaseAddrD2;		
		r_EnableD1 	<= rv_Config[0];
		r_Enable	<= r_EnableD1;
		r_RstEngineD1	<= rv_Config[1];
		r_RstEngine		<= r_RstEngineD1;
		
		if((r_UpdBaseAddrD3^r_UpdBaseAddrD2)||(w32_BufferEndAddr==r32_PostAddr))	
			r32_PostAddr <= r64_BufferBaseAddr[31:0];
		
		//Calculate the next data packet 
		r12_DistanceTo4KBBoundary <= 12'h0-r32_PostAddr[11:0];
		r12_NextPktPload <= (r12_DistanceTo4KBBoundary==12'h0)?i12_MaxPload:((r12_DistanceTo4KBBoundary>i12_MaxPload)?i12_MaxPload:r12_DistanceTo4KBBoundary);
		
		//Timer
		if(r5_ReqtorState==pIDLE_STOP  && (~i_LclEmpty))
			rv_IrqTimer <= rv_IrqTimer-1;
		else 
			rv_IrqTimer <= rv_IrqTimeOut;
		
		
		
		case(r5_ReqtorState)
		pIDLE_STOP:	begin 
						if(r_RstEngine)
							begin 							
								r32_DWIrqCount 	<= 32'h0;												//Reset Count
								r32_PostAddr 	<= r64_BufferBaseAddr[31:0];							//Reset Write address 
							end
						else if((w_TimeOut|w_DataReady)&r_Enable&(~w_DWCntFull)&(~w_InvalidSetting)) 	//Only start when enabled and not full
							begin 
								r5_ReqtorState <= pREQTOSEND;
								r8_RqdPHCred <= (i8_CredConPH + 8'h1);									//Always Consume 1 ReqHdr										
								r8_IncPHCred <= 8'h1;
								if(w_DataReady) begin 								
									r12_RqdPDCred 	<= (i12_CredConPD + {4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
									r12_IncPDCred 	<= ({4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
									end
								else if(w_TimeOut) begin 
									r12_RqdPDCred <= (i12_CredConPD + {4'b0,iv_UsedWords[8:1]})+(iv_UsedWords[0]?12'h1:12'h0);
									r12_IncPDCred <= ({4'b0,iv_UsedWords[8:1]})+(iv_UsedWords[0]?12'h1:12'h0);
									end
																	
								//Calculate how many DW to send
								if(w_DataReady)
									r10_Length <= r12_NextPktPload[11:2];
								else if(w_TimeOut) 
									r10_Length <= {iv_UsedWords[8:0],1'b0};									
								
								//Calculate Line to Send Minus 1
								//Ignore the case of bits 2:0 being nonzero
								if(w_DataReady)
									r10_LineToSend_1 	<= {1'b0,r12_NextPktPload[11:3]}+10'h1;
								else if(w_TimeOut) 
									r10_LineToSend_1	<= {1'b0,iv_UsedWords[8:0]}+10'h1;									
								
								if(w_TimeOut)	r_TimeoutIrq <= 1'b1;
							end
					
					r_EnoughPHCred <= 1'b0;
					r_EnoughPDCred <= 1'b0;
					end
		pREQTOSEND:	begin 
						r_ReqToTx <= 1'b1;
						if(i_ReqGranted)							
							r5_ReqtorState <= pCALC_CRED;
					end		
		pCALC_CRED:	begin 
						r_EnoughPHCred <= ((i8_CredLimPH-r8_RqdPHCred)<8'h80)?1'b1:1'b0;
						r_EnoughPDCred <= ((i12_CredLimPD-r12_RqdPDCred)<12'h800)?1'b1:1'b0;
						if((r_EnoughPHCred|i_InfinitePH)&(r_EnoughPDCred|i_InfinitePD))
							r5_ReqtorState <= pSEND_REQ;
						
					end		
		pSEND_REQ:	begin
					if(i_AstTxHIPReady|i_LclDv)							
						begin
							r10_LineSent<= r10_LineSent+10'd1;
							r_TxDv 		<= 1'b1;
							r_TxSop 	<= 1'b0;
							r_TxEop 	<= 1'b0;
							r_LclReq	<= 1'b0;				
							if(r10_LineSent==10'd0)				//First line 							
								begin 
									r_TxSop 	<= 1'b1;
									r64_TxData 	<= {w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7,
													w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3};					
									//We may need to turn on the Request when 
									//3DW and the first DW is not Quadword Aligned
									//Currently this is not supported
									r_LclReq	<= 1'b0;			
									rv_TagNum	<= rv_TagNum + 8'h1;
								end					
							else 
							if(r10_LineSent==10'd1)				//Second line 
								begin 																
									r64_TxData	<= {w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF,
													w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB};					
									r_LclReq	<= 1'b1;			
								end						
							else 
								begin 														
									r64_TxData	<= iv_LclData;
									r_TxEop		<= (r10_LineToSend_1==r10_LineSent)?1'b1:1'b0;
									r_LclReq	<= (r10_LineToSend_1==r10_LineSent)?1'b0:1'b1;									
								end
						end
					else 					
						begin 
							r_TxDv 	<= 1'b0;
							r_TxSop <= 1'b0;
							r_TxEop <= 1'b0;						
						end					
					
					if(r_TxEop)
							begin 
								r5_ReqtorState <= pSEND_DONE;
								r_LclReq 	<= 1'b0;
								r_TxDv 		<= 1'b0;
								r10_LineSent<= 10'h0;
								r_ReqToTx 	<= 1'b0;
								r32_PostAddr<= (r32_PostAddr+{20'h0,r10_Length,2'b00});
								r_Done1stCycle <= 1'b0;
								r_Done2ndCycle <= 1'b0;
								r32_DWIrqCount <= r32_DWIrqCount + {22'h0,r10_Length};
							end
					end
		pSEND_DONE:	begin 						
						r_Done1stCycle <= 1'b1; 			//1 cycle: Calculating r12_DistanceTo4KBBoundary
						r_Done2ndCycle <= r_Done1stCycle;	//2 cycle: Calculating r12_NextPktPload
						r_MsiReq 		<= rv_Config[2] & r_Done1stCycle & w_GenerateMSI;
						if(r_Done2ndCycle & ((~r_MsiReq)|(r_MsiReq&i_IrqMsiAck)))
							begin 
							r5_ReqtorState 	<= pIDLE_STOP;	
							if(r_MsiReq)
								begin 								
								r32_DWIrqCount 	<= 0;
								r_TimeoutIrq 	<= 1'b0;
								r_MsiReq		<= 1'b0;
								end 							
							end
					end
		endcase			
		
		
		end
		
		
		
		assign o_ReqToTx 	= r_ReqToTx;
		assign o_AstTxDv 	= r_TxDv;
		assign o_AstTxEop	= r_TxEop;
		assign o_AstTxSop	= r_TxSop;
		assign ov_AstTxData = r64_TxData;		
		assign o_LclReq 	= r_LclReq & i_AstTxHIPReady & (~i_LclEmpty);	//Stop reading immediately, that cycle may still have valid data 

		assign o_UpdPHCred	= r_TxSop & r_TxDv;
		assign o_UpdPDCred	= r_TxEop & r_TxDv;
		assign o8_IncPHCred = r8_IncPHCred;
		assign o12_IncPDCred= r12_IncPDCred;
		
		
		assign o_IrqMsiReq	= r_MsiReq;
		assign o5_IrqMsiNum	= rv_Config[8:4];

	assign w_DWCntWrReq = r_Done2ndCycle & r_MsiReq&i_IrqMsiAck;	//Generate Write Pulse 
	
	always@(posedge i_Clk)
		begin 
			r_DWCntRdReqD0 <= r_DWCntRdReq;
			r_DWCntRdReqD1 <= r_DWCntRdReqD0;
			r_DWCntRdReqD2 <= r_DWCntRdReqD1;
		end 
	
	/*
	Timing 
	set_false_path -from *uDWCntFifo* -to r32_CfgRdData
	*/
	assign w_DWCntRdReq	= r_DWCntRdReqD1^r_DWCntRdReqD2;
	mSyncFifo #(.pWIDTH(31),.pDEPTH(8),.pALMOSTFULL(6),.pALMOSTEMPTY(2),.pLOOKAHEAD("ON")) uDWCntFifo	(
	.iv_Din	(r32_DWIrqCount[30:0]),
	.i_Wr	(w_DWCntWrReq),
	.ov_Qout	(w32_DWIrqCount[30:0]),
	.i_Rd		(w_DWCntRdReq),
	.o_Full		(w_DWCntFull),
	.o_Empty		(w_DWCntEmpty),
	.o_AlmostFull	(),
	.o_AlmostEmpty	(w_DWCntAlmEmpty),
	//.ov_UsedWords	(),	
	.i_Clk			(i_Clk),
	.i_ARst			(i_ARst));
	

endmodule 