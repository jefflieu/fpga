/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: This module will execute a transfer from local memory to host memory
				- Support 64-bit addressing
				- Support Byte Level Transfer 
				- Not support 4096-Byte Payload system
				- Local Memory Upto 4 Gigabyte
				- Local Memory must support pipeline mode 

Remarks		:

Revision	:
	Date	Author	Description

*/

`timescale 1ns/10ps

module mMemCopyWr64 #(parameter 	
	pMEM_BUFFER_NUM		=16,
	pMEM_READ_LATENCY	=4,	
	pREQ_TAG_LENGTH		=8,
	pTAG_PREFIX			=1'b0
	)(

	//Local Memory interface	
	output 	o_MemRd,								//Read Enable 
	input 	i_MemDv,								//Read Data valid
	input 	i_MemReady,								//Memory ready
	output 	[pMEM_BUFFER_NUM-1:0]	ov_MemRdSel,	//Memory select during read
	input 	[63:0]	iv_MemRdData,					//Read Data 
	output 	[31:0]	o32_MemRdAddr,					//The top bits are used to address the buffers
	output 	[pMEM_BUFFER_NUM-1:0]	ov_MemRdReq,	//Read Access Request 
	input 	i_MemRdGranted,							//Read Access Granted, the controller will hog the memory until 
													//All data have been transferred 
	
	
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
	input 	[11:0]	i12_MaxPload,	//Payload Size in Bytes, not support 4096bytes
	
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
	
	/////////////////////////////////////////////////////////////
	// Configuration address layout
	//	0: Config Register
	//	1: Status register 
	//	2: Reserved
	//	3: Reserved 
	//	4: [31:00] Host Address for the transfer 
	//	5: [63:32] Host address for the transfer 
	//	6: 32-bit Local Memory Offset, Bit 31:28 is address region codes to address 16 buffers, 
	//			Note that the last 4 bit offset must match the last 4 bit of post address
	//			More sophisticated memory layout can be implemented
	//	7: Number of bytes to transfer
	//		The first transaction, the controller will post from the address to and address of 128 byte boundary
	//		Subsequent transactions, the controller will post Max Payload which is always 128-byte boundary aligned
	//		The last transactions, the controller will post the remaining data. 
	//		To have best efficiency, always use 128-byte aligned transaction 
	/////////////////////////////////////////////////////////////
	
	reg [63:0]	r64_BufferBaseAddr;
	reg [08:0]	rv_Config;
	reg [31:4]	r32_LclMemOffset;	
	reg [31:0]	r32_CfgRdData;	
	reg [31:0]	r32_XferLenInByte,r32_IrqLevel;	
	wire[31:0]	wv_Status;	
	reg [31:0]	r32_RemainBytes;
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
		end 		
	else 
		begin 
			if(i_CfgCyc & i_CfgStb & i_CfgWnR)
				begin 
					case(i4_CfgAddr)
					4'h0	:	rv_Config <= i32_CfgWrData[8:0];					
					//4'h2	:	
					4'h3	:	r32_IrqLevel				<= 	i32_CfgWrData;
					4'h4	: 	r64_BufferBaseAddr[31:00] 	<= 	i32_CfgWrData;
					4'h5	: 	r64_BufferBaseAddr[63:32] 	<= 	i32_CfgWrData;
					4'h6	:	r32_LclMemOffset			<=	i32_CfgWrData[31:4];
					4'h7	:	r32_XferLenInByte			<=  i32_CfgWrData;
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
			//4'h2	:	
			//4'h3	:	
			4'h4:	r32_CfgRdData <= r64_BufferBaseAddr[31:00];
			4'h5:	r32_CfgRdData <= r64_BufferBaseAddr[63:32];			
			4'h6:	r32_CfgRdData <= {r32_LclMemOffset[31:4],r64_BufferBaseAddr[3:0]};
			4'h7:	r32_CfgRdData <= r32_RemainBytes;
			default: r32_CfgRdData <= 32'h0;
			endcase 			
		end 
	
	assign o_CfgAck = r_CfgAck;
	assign o32_CfgRdData = r32_CfgRdData;
	////////////////////////////////////////////////////
	// Controller 
	// - When register 7 is written, the number of bytes for transfer is updated 
	// - Then the controller proceeds to calculate various stuff based on the Address and the Transfer Size 
	// - The controller will generate multiple request until all the bytes have been transferred
	///////////////////////////////////////////////////
	
	
	/*
	Generate memory post request 	
	*/
	localparam pIDLE_STOP	= 5'b00001;	
	localparam pREQTOSEND	= 5'b00010;
	localparam pCALC_CRED	= 5'b00100;
	localparam pSEND_REQ	= 5'b01000;
	localparam pSEND_DONE	= 5'b10000;
	
	reg [31:0] rv_LclMemAddr;
	reg [pMEM_BUFFER_NUM-1:0] rv_LclMemSel;
	reg r_Enable,r_EnableD1;
	reg r_RstEngine,r_RstEngineD1;
	reg [31:0]	r32_PostAddr;	
	reg [04:0]	r5_ReqtorState;
	reg [07:0]	r8_RqdPHCred;		//Cummulative Required Completion Header Credit
	reg [11:0]	r12_RqdPDCred;		//Cummulative Required Completion Data Credit
	reg [07:0]	r8_IncPHCred;		//Incremental Header Credit Required
	reg [11:0]	r12_IncPDCred;		//Incremental Data Credit Required 
	
	
	reg	[9:0]	r10_Length,r10_LineToSend_1,r10_LineSent,r10_LineToRead_1;		
	reg [63:0]	r64_TxData;
	reg	r_TxSop, r_TxEop, r_TxDv;
	reg  [3:0]	w4_FrstBE;
	wire [7:0]	w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3;
	wire [7:0]	w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7;
	wire [7:0]	w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB;
	wire [7:0]	w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF;
	wire [1:0]	w2_ReqFmt;
	wire [4:0]	w5_ReqType;
	wire [2:0]	w3_ReqStatus;
	wire [7:0]	w8_Tag;
	wire [2:0]	w3_TrfcCls;
	wire 	w_4DWHdr,w_DataReady,w_GenerateMSI;	
	reg 	[pREQ_TAG_LENGTH-1:0]	rv_TagNum;
	reg		r_EnoughPHCred,r_EnoughPDCred,r_ReqToTx,r_WaitLineToSend,r_Done1stCycle,r_Done2ndCycle;
	reg		r_MsiReq,r_ReqDone,r_New,r_MemRdReq,r_MemBurstRd,r_LclFifoRd,r_MemRdDone,r_MsiDone;		
	reg 	r_UpdXferLenD1,r_UpdXferLenD2,r_UpdXferLenD3;	
	reg 	[11:0]	r12_Dist4KBBndry,r12_Dist128BBndry;
	reg 	[11:0]	r12_NextPktPload,r12_Smaller1,r12_Smaller2,r12_Smaller2_D1;
	reg 	[02:0]	r3_EndAddr;
	wire 	[63:0]	wv_LclData;
	wire 	w_LclFifoRd,w_LclFifoWr;	
	integer I;	
			
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
	
	///////////////////////////////////////////////////
	// Encoding of First BE for the case of 1 DW transfer
	///////////////////////////////////////////////////
	always@(*)
		case({r32_PostAddr[1:0],r12_NextPktPload[1:0]})
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
							((r32_PostAddr[1:0]==2'b00)?4'b1111:((r32_PostAddr[1:0]==2'b01)?4'b1110:((r32_PostAddr[1:0]==2'b10)?4'b1100:4'b1000)))};
		
	assign 	w8_ReqByte8 = w_4DWHdr?r64_BufferBaseAddr[63:56]:r32_PostAddr[31:24];
	assign 	w8_ReqByte9 = w_4DWHdr?r64_BufferBaseAddr[55:48]:r32_PostAddr[23:16];
	assign 	w8_ReqByteA = w_4DWHdr?r64_BufferBaseAddr[47:40]:r32_PostAddr[15:08];
	assign 	w8_ReqByteB = w_4DWHdr?r64_BufferBaseAddr[39:32]:{r32_PostAddr[07:02],2'b00};
	assign 	w8_ReqByteC = w_4DWHdr?r32_PostAddr[31:24]:8'h0;
	assign 	w8_ReqByteD = w_4DWHdr?r32_PostAddr[23:16]:8'h0;
	assign 	w8_ReqByteE = w_4DWHdr?r32_PostAddr[15:08]:8'h0;
	assign 	w8_ReqByteF = w_4DWHdr?{r32_PostAddr[07:02],2'b00}:8'h0;
	
	assign 	w_DataReady = (r12_NextPktPload!=0)?1'b1:1'b0;							//Note that 4096 byte transfer is not supported
	assign 	wv_Status 	= {12'h0,i12_MaxPload,1'b0,r_ReqDone,1'b0,r5_ReqtorState};
	assign 	w_GenerateMSI = (r32_RemainBytes<=r32_IrqLevel)?1'b1:1'b0;
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
			r10_LineToSend_1<= 10'h0;
			r10_LineToRead_1<= 10'h0;
			r32_PostAddr	<= 32'h0;		
			r_UpdXferLenD1	<= 1'b0;
			r_UpdXferLenD2	<= 1'b0;
			r_UpdXferLenD3	<= 1'b0;
			r12_Dist4KBBndry<= 12'h0;
			r12_NextPktPload<= 12'h0;
			r12_Dist128BBndry<=12'h0;
			r_Enable		<= 1'b0;
			r_EnableD1 		<= 1'b0;
			r_Done1stCycle 	<= 1'b0;
			r_Done2ndCycle 	<= 1'b0;			
			rv_TagNum		<= 0;
			r_MsiReq		<= 1'b0;
			r_MsiDone		<= 1'b0;
			r32_RemainBytes	<= 0;
			r_RstEngine		<= 1'b0;
			r_RstEngineD1	<= 1'b0;
			r_New			<= 1'b0;
			r_ReqDone		<= 1'b1;			
			r_MemRdReq		<= 1'b0;
			r_MemBurstRd	<= 1'b0;
			r_LclFifoRd		<= 1'b0;
			r12_Smaller1	<= 12'h0;
			r12_Smaller2	<= 12'h0;
			r12_Smaller2_D1	<= 12'h0;
			r3_EndAddr		<= 3'b0;
			r_WaitLineToSend<= 1'b0;
			r_MemRdDone		<= 1'b1;
		end
	else 
		begin 
		
		//Clock domain synchronize
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
			r_MsiDone		<= 1'b0;
			r32_PostAddr 	<= r64_BufferBaseAddr[31:0];
			r32_RemainBytes	<= r32_XferLenInByte;
			rv_LclMemAddr	<= {r32_LclMemOffset[31:4],r64_BufferBaseAddr[3:0]};
				for(I=0;I<pMEM_BUFFER_NUM;I=I+1)
					rv_LclMemSel[I]<=(r32_LclMemOffset[31-:pMEM_ID_WIDTH]==I)?1'b1:1'b0;
			end
			
		//Calculate the next data packet 
		//Takes 3 clock to calculate these thing
		r12_Dist4KBBndry <= 12'h000-r32_PostAddr[11:0];			
		r12_Dist128BBndry<= 12'h080-{5'h0,r32_PostAddr[6:0]};
		r12_Smaller1	 <= (r12_Dist128BBndry==12'h080)?r12_Dist4KBBndry:r12_Dist128BBndry;		
		r12_Smaller2	 <= (r32_RemainBytes>{20'h0,i12_MaxPload})?i12_MaxPload:r32_RemainBytes[11:0];
		r12_Smaller2_D1	 <= r12_Smaller2;
		r12_NextPktPload <= ((r12_Smaller1>r12_Smaller2_D1)||(r12_Smaller1==12'h0))?r12_Smaller2_D1:r12_Smaller1;	 
		
		//To control memory read 
		if(~r_MemRdDone)
		begin
			if(r_MemBurstRd&i_MemReady)
			begin 
			rv_LclMemAddr	<= rv_LclMemAddr+32'h8;
			r10_LineToRead_1<= r10_LineToRead_1-10'h1;
			if(r10_LineToRead_1==0)	
				begin 
				r_MemBurstRd 	<= 1'b0;
				r_MemRdDone		<= 1'b1;
				end
			end			
		end 
		
		case(r5_ReqtorState)
		pIDLE_STOP:	begin 
						r_WaitLineToSend <= 1'b0;
						if(r_RstEngine)
							begin 							
								r32_RemainBytes	<= 32'h0;						//Reset Count
								r32_PostAddr 	<= r64_BufferBaseAddr[31:0];	//Reset Write address 
							end
						else if(w_DataReady&r_Enable) 							
							begin 
													
								r8_RqdPHCred <= (i8_CredConPH + 8'h1);			//Always Consume 1 ReqHdr										
								r8_IncPHCred <= 8'h1;
								if(w_DataReady) begin 								
									r12_RqdPDCred 	<= (i12_CredConPD + {4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
									r12_IncPDCred 	<= ({4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
								end
								//Calculate how many DW to send
								r10_Length 	<= r12_NextPktPload[11:2]+((r12_NextPktPload[1:0]==2'b00)?10'h0:10'h1);
								r_ReqDone 	<= 1'b0;
								r3_EndAddr 	<= r32_PostAddr[2:0]+r12_NextPktPload[2:0];
								
								r_WaitLineToSend <= 1'b1;			
								//Calculate Line to Send Minus 1
								case({w_4DWHdr,r32_PostAddr[2]})								
								2'b00: r10_LineToSend_1 <= r10_Length[9:1]+((r10_Length[0])?10'h2:10'h1);
								2'b01: r10_LineToSend_1 <= r10_Length[9:1]+10'h1;							
								2'b10: r10_LineToSend_1 <= r10_Length[9:1]+((r10_Length[0])?10'h2:10'h1);								
								2'b11: r10_LineToSend_1 <= r10_Length[9:1]+10'h2;
								endcase
								
								//Calculate Line to Send Minus 1								
								case({w_4DWHdr,r32_PostAddr[2]})
								2'b00: r10_LineToRead_1 <= r10_Length[9:1]-((r10_Length[0])?10'h0:10'h1);								
								2'b01: r10_LineToRead_1 <= r10_Length[9:1];								
								3'b10: r10_LineToRead_1 <= r10_Length[9:1]-((r10_Length[0])?10'h2:10'h1);								
								3'b11: r10_LineToRead_1 <= r10_Length[9:1];								
								endcase
								if(r_WaitLineToSend) 
								begin 
									r5_ReqtorState 		<= pREQTOSEND;
									r_WaitLineToSend 	<= 1'b0;									
								end
							end
					
					r_EnoughPHCred <= 1'b0;
					r_EnoughPDCred <= 1'b0;
					end
		pREQTOSEND:	begin 					
						r_MemRdReq	<= 1'b1;						
						r_ReqToTx 	<= r_MemRdReq&i_MemRdGranted;						
						if(i_ReqGranted)
							begin
							r_MemBurstRd	<= 1'b1;
							r_MemRdDone		<= 1'b0;
							r5_ReqtorState <= pCALC_CRED;
							end 
					end		
		pCALC_CRED:	begin 
						r_EnoughPHCred <= ((i8_CredLimPH-r8_RqdPHCred)<8'h80)?1'b1:1'b0;
						r_EnoughPDCred <= ((i12_CredLimPD-r12_RqdPDCred)<12'h800)?1'b1:1'b0;
						if((r_EnoughPHCred|i_InfinitePH)&(r_EnoughPDCred|i_InfinitePD))
							r5_ReqtorState <= pSEND_REQ;
						
					end		
		pSEND_REQ:	begin
					//This is split into 2 substates
					//When r_LclFifoRd=0, header phase  
					//When r_LclFifoRd=1, data phase 
					if((i_AstTxHIPReady&(~r_LclFifoRd))|w_LclFifoRd)							
						begin
							r10_LineSent<= r10_LineSent+10'd1;
							r_TxDv 		<= 1'b1;
							r_TxSop 	<= 1'b0;
							r_TxEop 	<= 1'b0;							
							if(r10_LineSent==10'd0)				//First line 							
								begin 
									r_TxSop 	<= 1'b1;
									r64_TxData 	<= {w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7,
													w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3};					
									//Turn on read when 
									//3DW and the first DW is not Quadword Aligned									
									r_LclFifoRd	<= (~w_4DWHdr)&r32_PostAddr[2];			
									rv_TagNum	<= rv_TagNum + 8'h1;
								end					
							else 
							if(r10_LineSent==10'd1)				//Second line 
								begin 																
									r64_TxData	<= {wv_LclData[63:32],
													w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB};					
									r_TxEop		<= (r10_LineToSend_1==10'h1)?1'b1:1'b0;
									r_LclFifoRd	<= (r10_LineToSend_1==10'h1)?1'b0:1'b1;			
								end						
							else 
								begin 														
									r64_TxData	<= wv_LclData;
									r_TxEop		<= (r10_LineToSend_1==r10_LineSent)?1'b1:1'b0;
									r_LclFifoRd	<= (r10_LineToSend_1==r10_LineSent)?1'b0:1'b1;									
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
								r_LclFifoRd 	<= 1'b0;
								r_TxDv 			<= 1'b0;
								r10_LineSent	<= 10'h0;
								r_ReqToTx 		<= 1'b0;
								r32_PostAddr	<= (r32_PostAddr+{20'h0,r12_NextPktPload});
								r_Done1stCycle 	<= 1'b0;
								r_Done2ndCycle 	<= 1'b0;
								r32_RemainBytes	<= r32_RemainBytes-{20'h0,r12_NextPktPload};
								
								r5_ReqtorState <= pSEND_DONE;
							end
					end
		pSEND_DONE:	begin 						
						r_Done1stCycle 	<= 1'b1; 			//1 cycle: Calculating r12_Dist4KBBndry
						r_Done2ndCycle 	<= r_Done1stCycle;	//2 cycle: Calculating r12_Smaller1
						r_MsiReq 		<= rv_Config[2]&(~r_MsiDone)&r_Done1stCycle&w_GenerateMSI;
						r_ReqDone 		<= (r32_RemainBytes==0)?1'b1:1'b0;
						r_MemRdReq		<= (r32_RemainBytes==0)?1'b0:1'b1;
						
						if(r_Done2ndCycle & ((~r_MsiReq)|(r_MsiReq&i_IrqMsiAck)))
							begin 
							r5_ReqtorState 	<= pIDLE_STOP;	
							if(r_MsiReq)
								r_MsiReq	<= 1'b0;
								r_MsiDone	<= 1'b1;
							end
						
					end
		endcase			
		end
		
		
	//Temporary Buffer 
	assign w_LclFifoWr = i_MemDv;
	mSyncFifo #(
		.pWIDTH(64),
		.pDEPTH(32),
		.pALMOSTFULL(30),
		.pALMOSTEMPTY(2),
		.pLOOKAHEAD("ON"))
	u0LclFifo(
		.i_Clk	(i_Clk		),
		.i_Rd	(w_LclFifoRd),
		.i_Wr	(w_LclFifoWr),
		.iv_Din	(iv_MemRdData),	
	
		.ov_Qout(wv_LclData),
	//Flags
		.o_Full			(),
		.o_Empty		(w_LclEmpty),
		.o_AlmostFull	(),
		.o_AlmostEmpty	(),
	
		.i_ARst		(i_ARst)//Reset pointer
	); 	
		assign w_LclFifoRd 	= r_LclFifoRd & i_AstTxHIPReady & (~w_LclEmpty);	//Stop reading immediately, that cycle may still have valid data 
	
		assign ov_MemRdReq 	= {pMEM_BUFFER_NUM{r_MemRdReq}}&rv_LclMemSel;
		assign o32_MemRdAddr= rv_LclMemAddr;
		assign o_MemRd		= r_MemBurstRd;
		assign ov_MemRdSel	= {pMEM_BUFFER_NUM{r_MemBurstRd}}&rv_LclMemSel;
		
		assign o_ReqToTx 	= r_ReqToTx;
		assign o_AstTxDv 	= r_TxDv;
		assign o_AstTxEop	= r_TxEop;
		assign o_AstTxSop	= r_TxSop;
		assign ov_AstTxData = r64_TxData;		
		
		assign o_UpdPHCred	= r_TxSop & r_TxDv;
		assign o_UpdPDCred	= r_TxEop & r_TxDv;
		assign o8_IncPHCred = r8_IncPHCred;
		assign o12_IncPDCred= r12_IncPDCred;
		
		
		assign o_IrqMsiReq	= r_MsiReq;
		assign o5_IrqMsiNum	= rv_Config[8:4];

endmodule 