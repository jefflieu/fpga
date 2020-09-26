/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module will pull data from host memory to local device
				- Support 64-bit addressing
				- Not Support Byte Level Transfer, only support even number of DW transfer, it is recommended to transfer in multiple of 64 bytes to avoid tough
					cases of 1-DW packets 
				- Only support 64-bit aligned address 
				- Support 4096-Byte Payload system if Max read request allows
				- Completion timeout is not supported yet, completion time-out can be implemented in the Tag Keeper
				
Remarks		:

Revision	:
	Date	Author	Description

*/

`timescale 1ns/10ps

module mMemPullRequestor64 #(parameter 	
	pBUFFER_TAGWIDTH	=16,
	pREQ_TAG_LENGTH		=8,
	pTAG_PREFIX			=1'b0
	)(

	//Buffer interface
	output	o_LclSof,				//	Local Data valid, not used
	output	o_LclEof,				//	Local Data valid, not used
	output	o_LclDv,				//	Local Data valid, 
	output	[63:0]	ov_LclData,		//  Local Data	
	input 	[15:0]	iv_UnusedWords,	// 	Local Daa Available 
	
	
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
	reg 		r_CfgAck;			
	reg [31:0]	r32_CfgRdData;
	
	reg [31:0]	r32_BufferSize;
	reg [63:0]	r64_BufferBaseAddr;
	reg [08:0]	rv_Config;
	reg [31:0]	rv_IrqThreshold;
	reg [31:0]	rv_DWToPull;
	reg [10:0]	r11_CfgDWPerReq;
	reg 		r_UpdAddr,r_UpdDWToPull;
	wire[31:0]	wv_Status;		
	reg [31:0]	r32_RemDWToPull;
	wire[07:0]	w8_CmplError;
	wire 		w_InvalidSetting;
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
			rv_Config 			<= 0;
			rv_IrqThreshold		<= 0;
			r_CfgAck 			<= 1'b0;
			r_UpdAddr			<= 1'b0;
			r32_BufferSize		<= 0;			
			rv_DWToPull			<= 0;
			r11_CfgDWPerReq		<= 10'h0;
			r_UpdDWToPull		<= 1'b0;
		end 		
	else 
		begin 
			//Cap this value to max read request and have to be multiple of 64 byte
			r11_CfgDWPerReq <= ({1'b0,i12_MaxReadReq[11:2]}<r11_CfgDWPerReq)?{1'b0,i12_MaxReadReq[11:2]}:r11_CfgDWPerReq;
			
			if(i_CfgCyc & i_CfgStb & i_CfgWnR)
				begin 
					case(i4_CfgAddr)
					4'h0	:	rv_Config <= i32_CfgWrData[8:0];					
					4'h2	:	if(~rv_Config [0])r64_BufferBaseAddr[31:00] <= i32_CfgWrData;				
					4'h3	:	if(~rv_Config [0])r64_BufferBaseAddr[63:32] <= i32_CfgWrData;
					4'h4	: 	if(~rv_Config [0])r32_BufferSize	<= i32_CfgWrData;				
					4'h5	: 	if(~rv_Config [0])r11_CfgDWPerReq	<= i32_CfgWrData[12:2];							
					4'h6	:	if(~rv_Config [0])rv_IrqThreshold	<= {2'b0,i32_CfgWrData[31:3],1'b0};					
					4'h7	:	rv_DWToPull							<= {2'b0,i32_CfgWrData[31:3],1'b0};							//Even Number of DWs
					endcase				
				end
			
			if(i_CfgCyc & i_CfgStb & i_CfgWnR & r_CfgAck & (i4_CfgAddr==4'h3))
				r_UpdAddr <= ~r_UpdAddr;
			if(i_CfgCyc & i_CfgStb & i_CfgWnR & r_CfgAck & (i4_CfgAddr==4'h7))
				r_UpdDWToPull <= ~r_UpdDWToPull;
			r_CfgAck  <= i_CfgCyc & i_CfgStb & (~r_CfgAck);			
		end	
	assign w_InvalidSetting = (r64_BufferBaseAddr[5:0]!=6'h0)||(|((r32_BufferSize-32'h1)&r64_BufferBaseAddr[31:0]))||(r11_CfgDWPerReq[3:0]!=4'h0);
	always@(*)
		begin 
			case(i4_CfgAddr)
			4'h0:	r32_CfgRdData <= rv_Config;
			4'h1:	r32_CfgRdData <= wv_Status;
			4'h2:	r32_CfgRdData <= r64_BufferBaseAddr[31:00];
			4'h3:	r32_CfgRdData <= r64_BufferBaseAddr[63:32];
			4'h4:	r32_CfgRdData <= r32_BufferSize;
			4'h5:	r32_CfgRdData <= {19'h0,r11_CfgDWPerReq,2'b00};
			4'h6:	r32_CfgRdData <= {rv_IrqThreshold[29:0],2'b00};
			4'h7:	r32_CfgRdData <= {r32_RemDWToPull[29:0],2'b00};
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
	reg [31:0]	r32_PullAddr;	
	reg [04:0]	r5_ReqtorState;
	reg [07:0]	r8_RqdNHCred;		//Cummulative Required Header Credit
	reg [07:0]	r8_IncNHCred;		//Incremental Header Credit Required	
	reg [07:0]	r8_RqdCHCred;		//Required Completion Header Credit
	reg [011:0]	r12_RqdCDCred;		//Required Completion Data Credit
	reg	r_EnoughNHCred;	
	reg	r_EnoughCHCred;
	reg	r_EnoughCDCred;	
	reg	r_ReqToTx;					//Arbitrate to transmit
	reg	r_TxLine;					//0: first line, 1 second line
	reg	[9:0]	r10_Length;			//Length of Read Request in DW
	reg [63:0]	r64_TxData;			//Transmit data
	reg	r_TxSop, r_TxEop, r_TxDv;	//Avalon Stream Signally
	wire [7:0]	w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3;
	wire [7:0]	w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7;
	wire [7:0]	w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB;
	wire [7:0]	w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF;
	wire [1:0]	w2_ReqFmt;			//2 bit format
	wire [4:0]	w5_ReqType;			//5 bit type
	wire [2:0]	w3_ReqStatus;		//Status	
	wire [2:0]	w3_TrfcCls;
	wire 	w_4DWHdr,w_DataReady;		
	reg		r_MsiReq,r_MsiDone;		//Send MSI request, after acknowledge MSI done is raised,
	reg 	r_ReqDone,r_New;		//When there's nothing to pull, the ReqDone is raised
	reg 	r_UpdAddrD1,r_UpdAddrD2,r_UpdAddrD3;
	reg 	r_UpdDWToPullD1,r_UpdDWToPullD2,r_UpdDWToPullD3;
	
	reg 	[12:0]	r13_DistanceTo4KBBoundary;
	reg 	[12:0]	r13_NextReqLenByte;
	reg 	[10:0]	r11_NextReqLenDW;
	wire 	[31:0]	w32_BufferEndAddr;
	reg		[10:0]	r11_DWPerReq;
	wire 	w_GenerateMSI;
	reg 	r_Done1stCycle,r_Done2ndCycle;
	
	
	assign w32_BufferEndAddr= r64_BufferBaseAddr[31:0]+r32_BufferSize;
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
	assign 	w8_ReqByte7	= 8'hFF;
		
	assign 	w8_ReqByte8 = w_4DWHdr?r64_BufferBaseAddr[63:56]:r32_PullAddr[31:24];
	assign 	w8_ReqByte9 = w_4DWHdr?r64_BufferBaseAddr[56:48]:r32_PullAddr[23:16];
	assign 	w8_ReqByteA = w_4DWHdr?r64_BufferBaseAddr[47:40]:r32_PullAddr[15:08];
	assign 	w8_ReqByteB = w_4DWHdr?r64_BufferBaseAddr[39:32]:r32_PullAddr[07:00];
	assign 	w8_ReqByteC = w_4DWHdr?r32_PullAddr[31:24]:8'h0;
	assign 	w8_ReqByteD = w_4DWHdr?r32_PullAddr[23:16]:8'h0;
	assign 	w8_ReqByteE = w_4DWHdr?r32_PullAddr[15:08]:8'h0;
	assign 	w8_ReqByteF = w_4DWHdr?r32_PullAddr[07:00]:8'h0;
	
	assign w_GenerateMSI= (r32_RemDWToPull<=rv_IrqThreshold)?1'b1:1'b0;
	//////////////////////////////////////////////////////////
	// Data ready when there are space to accommodate the completion
	// And the number requested bytes is not zero
	//////////////////////////////////////////////////////////
	assign w_DataReady 	= (((|iv_UnusedWords[15:10])||{iv_UnusedWords[9:0],3'b0}>=r13_NextReqLenByte) && r13_NextReqLenByte!=0)?1'b1:1'b0;
	assign wv_Status 	= {w_InvalidSetting,3'h0,w8_CmplError,i12_MaxPload,2'b00,i_TagAvail,r5_ReqtorState};
	
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
			r13_DistanceTo4KBBoundary 	<= 13'h0;
			r13_NextReqLenByte 			<= 13'h0;
			r_Enable					<= 1'b0;
			r_EnableD1 					<= 1'b0;
			r_Done1stCycle 				<= 1'b0;
			r_Done2ndCycle 				<= 1'b0;		
			r_MsiReq					<= 1'b0;			
			r32_RemDWToPull				<= 0;
			r_RstEngine					<= 1'b0;
			r_RstEngineD1				<= 1'b0;			
			r11_NextReqLenDW			<= 11'h0;
			r8_RqdCHCred				<= 8'h0;
			r12_RqdCDCred				<= 12'h0;
			r_TxLine					<= 1'b0;
			r_UpdAddrD1					<= 1'b0;
			r_UpdAddrD2					<= 1'b0;
			r_UpdAddrD3					<= 1'b0;			
			r_UpdDWToPullD1	<= 1'b0;
			r_UpdDWToPullD2	<= 1'b0;
			r_UpdDWToPullD3	<= 1'b0;	
			r_ReqDone		<= 1'b1;
			r_MsiDone		<= 1'b0;
			r_TxDv			<= 1'b0;
			r_TxEop			<= 1'b0;
			r_TxSop 		<= 1'b0;
			r10_Length		<= 10'h0;
			r64_TxData		<= 64'h0;
			r_New			<= 1'b0;
		end
	else 
		begin 
		
		r_UpdDWToPullD1<=r_UpdDWToPull;
		r_UpdDWToPullD2<=r_UpdDWToPullD1;
		r_UpdDWToPullD3<=r_UpdDWToPullD2;
		
		r_UpdAddrD1<=r_UpdAddr;
		r_UpdAddrD2<=r_UpdAddrD1;
		r_UpdAddrD3<=r_UpdAddrD2;
	
		r_EnableD1 		<= rv_Config[0];
		r_Enable		<= r_EnableD1;
		r_RstEngineD1	<= rv_Config[1];
		r_RstEngine		<= r_RstEngineD1;
		r11_DWPerReq	<= (r11_CfgDWPerReq==0)?{1'b0,i12_MaxReadReq[11:2]}:(r11_CfgDWPerReq[10]?11'd1024:r11_CfgDWPerReq);		
		
		if((r_UpdAddrD2^r_UpdAddrD3)||(w32_BufferEndAddr==r32_PullAddr))//Reset the address  
			r32_PullAddr <= r64_BufferBaseAddr[31:0];		
				
		if(r_UpdDWToPullD2^r_UpdDWToPullD3)
			r_New	<= 1'b1;
		else if(r_New&r_ReqDone)
			r_New	<= 1'b0;
		
		if(r_New&r_ReqDone)			
			r32_RemDWToPull 	<= rv_DWToPull;
		
		
		//Calculate the next data packet 
		r13_DistanceTo4KBBoundary <= 13'h1000-{1'b0,r32_PullAddr[11:0]};
		r11_NextReqLenDW	<= (r32_RemDWToPull>={21'h0,r11_DWPerReq})?r11_DWPerReq:{r32_RemDWToPull[10:0]};
		r13_NextReqLenByte 	<= (r13_DistanceTo4KBBoundary>{r11_NextReqLenDW,2'b00})?{r11_NextReqLenDW,2'b00}:r13_DistanceTo4KBBoundary;
				
		case(r5_ReqtorState)
		pIDLE_STOP:	begin 
						if(r_RstEngine)
							begin 
								r_New				<= 1'b0;
								r32_RemDWToPull 	<= 0;					
								r32_PullAddr 		<= r64_BufferBaseAddr[31:0];	
							end
						else if(w_DataReady&i_TagAvail&r_Enable&(~w_InvalidSetting)) 	
							begin 
								r5_ReqtorState <= pREQTOSEND;
								r8_RqdNHCred <= (i8_CredConNH + 8'h1);			//Always Consume 1 ReqHdr										
								r8_IncNHCred <= 8'h1;											
																
								//Calculate how many DW to request
								r10_Length 	<= 	r13_NextReqLenByte[11:2];		//=0; when r13_NextReqLenByte=4096							
								r_TxLine	<= 	1'b0;																
								r_ReqDone	<=  1'b0;
								r_MsiDone	<= 	r_MsiDone&w_GenerateMSI;
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
										r32_PullAddr<= (r32_PullAddr+{19'h0,~(|r10_Length),r10_Length,2'b00});
										r32_RemDWToPull <= r32_RemDWToPull-{21'h0,~(|r10_Length),r10_Length};
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
						r_Done1stCycle <= 1'b1; 			//1 cycle: Calculating r13_DistanceTo4KBBoundary
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
							r_ReqDone <= (r32_RemDWToPull==0)?1'b1:1'b0;
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

		
	

	//Completion Handling
	mCmplHandler64 #(.pFIFO_MODE(1)) uCmplHandler(			

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
	
	.o_CplRcved			(o_CplRcved		),
	.o8_RcvedCplCH		(o8_RcvedCplCH	),//
	.o12_RcvedCplCD		(o12_RcvedCplCD	),//
	
	//Local Buffer 
	.o_LclSof	(o_LclSof	),				//	Local Data valid, not used
	.o_LclEof	(o_LclEof	),				//	Local Data valid, not used
	.o_LclDv	(o_LclDv	),				//	Local Data valid	
	.ov_LclData	(ov_LclData	),
	
	//Wishbone Bus master
//	output 	[6:0]	o7_BARSelect,
//	output	o_WbCyc,
//	output	o_WbStb,	
//	output 	o_WbWnR,
//	output 	[pBUS_ADDR_WIDTH-1:0]	ov_WbAddr,
//	output 	[64:0]	o64_WbWrData,
//	input 	[64:0]	i64_WbRdData,
//	input 	i_WbAck,
//	output 	[07:0]	o8_ByteEn,
	
	.o8_CmplError	(w8_CmplError),
	
	.i_Clk	(i_Clk),
	.i_ARst	(i_ARst));
		
endmodule 
