/*
Copyright � 2013 lieumychuong@gmail.com

File    :
Description : This module will stream data from local device to host memory
        - Support 64-bit addressing
        - Not Support Byte Level Transfer, only support even number of DW transfer
        - Only support 64-bit aligned address 
        - Not suport 4096-Byte Payload system, max payload the code can support is 2048 byte 
        - Pingpong buffer style, data written into buffer must be multiple of transfers .. if packet/frame is not multiple of transfer,
        - it has to be stuffed at the end
        
Remarks   :

Revision  :
  Date  Author  Description

*/

`timescale 1ns/10ps

module mPingPongMemPost64 #(parameter  
  pBUFFER_TAGWIDTH  =16,
  pREQ_TAG_LENGTH   =8,
  pTAG_PREFIX       =1'b0,
  pBURST_SIZE       =64 //Words
  )(

  //Buffer interface  
  output  o_Enable,
  input   i_LclDv,        //  Local Data valid, can be 0 or 1 cycle delay of LclReq
  input   [63:0]  iv_LclData,   //  Local Data
  output  o_LclReq,       //  Local Data Read Request
  input   [15:0]  iv_UsedWords, //  Local Daa Available 
  input   i_LclEmpty,
  
  input   i_Start, //Start of Transfer Start of frame, start of packet ..
  
  
  //Configuration bus interface 
  input   i_CfgCyc,
  input   i_CfgStb,
  input   i_CfgWnR, 
  input   [03:0]  i4_CfgAddr,
  input   [31:0]  i32_CfgWrData,
  output  [31:0]  o32_CfgRdData,
  output  o_CfgAck,
  input   i_CfgClk,
    
  //Avalon Stream TX
  output  o_AstTxSop,
  output  o_AstTxEop,
  output  o_AstTxEmpty,//NotUsed
  output  o_AstTxDv,
  output  [63:0]  ov_AstTxData,
  input   i_AstTxHIPReady,  
  
  //Credit interface  
  input [ 7:0] i8_CredLimPH,   //Posted Header
  input [ 7:0] i8_CredLimCH,   //Completion Header
  input [ 7:0] i8_CredLimNH,   //Non Posted Header 
  input [11:0] i12_CredLimPD, //Posted Data
  input [11:0] i12_CredLimCD, //Completion Data
  input [11:0] i12_CredLimND, //Nonposted Ddata
  
  input [ 7:0] i8_CredConPH,   //Posted Header
  input [ 7:0] i8_CredConCH,   //Completion Header
  input [ 7:0] i8_CredConNH,   //Non Posted Header 
  input [11:0] i12_CredConPD, //Posted Data
  input [11:0] i12_CredConCD, //Completion Data
  input [11:0] i12_CredConND, //Nonposted Ddata
  
  input   i_InfinitePH,
  input   i_InfiniteCH,
  input   i_InfiniteNH,
  input   i_InfinitePD,
  input   i_InfiniteCD,
  input   i_InfiniteND,
  
  output  o_UpdPHCred,
  output  o_UpdPDCred,
  output  [07:0]  o8_IncPHCred,
  output  [11:0]  o12_IncPDCred,
  
  
  input   [15:0]  i16_RequestorID,//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
  input   [11:0]  i12_MaxPload, //Payload Size in Bytes
  
  //Arbitration Interface
  output  o_ReqToTx,
  input i_ReqGranted,

  output  o_IrqMsiReq,
  input   i_IrqMsiAck,
  output  [4:0] o5_IrqMsiNum,
  output  [2:0] o3_IrqMsiTfc,
  
  //Rx Credit Interface 
  input [7:0] i8_AvailCredCH  ,//Not used for Memory Post Write Requestor   
  input   [11:0]  i12_AvailCredCD ,//Not used for Memory Post Write Requestor

  input   i_Clk,
  input   i_ARst,
  
  output  [255:0] o256_Dbg);

  
  localparam pWORD_SIZE_BYTES = 8;
  
  /////////////////////////////////////////////////////////////
  // Configuration address layout
  //  0: Config Register
  //  1: Status register 
  //  2: 32-bit LSB of 64 bit address -- PINGPONG0
  //  3: 32-bit MSB of 64 bit address -- PINGPONG0 
  //  4: 32-bit LSB of 64 bit address -- PINGPONG1
  //  5: 32-bit MSB of 64 bit address -- PINGPONG1 
  //  6: 32-bit buffer size for safety check make sure no segmentation
  
  
  /////////////////////////////////////////////////////////////
  reg [31:0]  r32_BufferSize;
  reg [63:0]  r64_BufferBaseAddr0;
  reg [63:0]  r64_BufferBaseAddr1;
  reg [08:0]  rv_Config;
  reg [31:0]  rv_IrqThreshold;
  reg [ 7:0]  r8_WordsPerTransfer;
  reg [15:0]  r16_TransfersIrq;
  
  reg r_CfgAck;   
  wire w_Use32bitAddr;
  reg [31:0]  r32_CfgRdData;
  reg r_UpdBaseAddr;
  wire  [31:0]  wv_Status;
  wire w_InvalidSetting;
  wire w_LclEmpty;
  
  
  
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
      r64_BufferBaseAddr0 <= 64'h0;
      r64_BufferBaseAddr1 <= 64'h0;
      rv_Config           <= 0;      
      r_CfgAck            <= 1'b0;
      r32_BufferSize      <= 32'h0;            
      r8_WordsPerTransfer <= 8;        //8 words = 64 bytes
      r16_TransfersIrq    <= 65535;    //64*65535 = 4MB
    end     
  else 
    begin 
      if(i_CfgCyc & i_CfgStb & i_CfgWnR)
        begin 
          case(i4_CfgAddr)
          4'h0  : rv_Config <= i32_CfgWrData[8:0];          
          4'h2  : r64_BufferBaseAddr0[31:00]   <= i32_CfgWrData;
          4'h3  : r64_BufferBaseAddr0[63:32]   <= i32_CfgWrData;
          4'h4  : r64_BufferBaseAddr1[31:00]   <= i32_CfgWrData;
          4'h5  : r64_BufferBaseAddr1[63:32]   <= i32_CfgWrData;
          4'h6  : r32_BufferSize               <= i32_CfgWrData;
          4'h7  : r8_WordsPerTransfer          <= i32_CfgWrData[ 7:0];
          4'h8  : r16_TransfersIrq             <= i32_CfgWrData[15:0];        
          default: ;
          endcase       
        end
              
      r_CfgAck  <= i_CfgCyc & i_CfgStb & (~r_CfgAck);
      
    end
  assign w_InvalidSetting = (r64_BufferBaseAddr0[5:0]!=6'h0 || r64_BufferBaseAddr1[5:0]!=6'h0);
  always@(*)
    begin 
      case(i4_CfgAddr)
      4'h0: r32_CfgRdData <= rv_Config;
      4'h1: r32_CfgRdData <= wv_Status;
      4'h2: r32_CfgRdData <= r64_BufferBaseAddr0[31:00];
      4'h3: r32_CfgRdData <= r64_BufferBaseAddr0[63:32];
      4'h4: r32_CfgRdData <= r64_BufferBaseAddr1[31:00];
      4'h5: r32_CfgRdData <= r64_BufferBaseAddr1[63:32];
      4'h6: r32_CfgRdData <= 32'h0;
      default: r32_CfgRdData <= 32'h0;
      endcase       
    end 
  
  assign o_CfgAck = r_CfgAck;
  assign o32_CfgRdData = r32_CfgRdData;
  
  assign o_Enable = r_Enable;
  
  ////////////////////////////////////////////////////
  // Controller 
  // - Start a transmission if available data is more than payload or a time-out 
  //  
  ///////////////////////////////////////////////////
  
  
  /*
  Generate memory post request  
  */
  localparam pIDLE_STOP = 5'b00001; 
  localparam pREQTOSEND = 5'b00010;
  localparam pCALC_CRED = 5'b00100;
  localparam pSEND_REQ  = 5'b01000;
  localparam pSEND_DONE = 5'b10000;
  
  reg r_Enable,r_EnableD1,r_EnableD2;

  reg [31:0]  r32_PostAddr; 
  reg [04:0]  r5_ReqtorState;
  reg [07:0]  r8_RqdPHCred;   //Cummulative Required Completion Header Credit
  reg [11:0]  r12_RqdPDCred;    //Cummulative Required Completion Data Credit
  reg [07:0]  r8_IncPHCred;   //Incremental Header Credit Required
  reg [11:0]  r12_IncPDCred;    //Incremental Data Credit Required 
  reg r_EnoughPHCred;
  reg r_EnoughPDCred;
  reg r_ReqToTx;
  reg [9:0] r10_LineToSend_1,r10_LineSent;
  reg [9:0] r10_Length;
  reg [63:0]  r64_TxData;
  reg r_TxSop, r_TxEop, r_TxDv;
  wire [7:0]  w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3;
  wire [7:0]  w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7;
  wire [7:0]  w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB;
  wire [7:0]  w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF;
  wire [1:0]  w2_ReqFmt;
  wire [4:0]  w5_ReqType;
  wire [7:0]  w8_Tag;
  wire [2:0]  w3_TrfcCls;
  wire  w_4DWHdr,w_DataReady; 
  reg   [pREQ_TAG_LENGTH-1:0] rv_TagNum;
  reg   r_LclReq,r_MsiReq; 
  reg   r_UpdBaseAddrD1,r_UpdBaseAddrD2,r_UpdBaseAddrD3;
  reg   [11:0]  r12_DistanceTo4KBBoundary;
  reg   [11:0]  r12_NextPktPload;  
  wire  w_TimeOut,w_GenerateMSI;
  reg   r_Done1stCycle,r_Done2ndCycle;
  reg   [15:0]  r16_TransfersCnt;
  reg   r_BufferPtr;
  wire  w_ErrPayld;
  reg   r_4kSplit;
  wire  w_4kSplit;
  reg   [11:0] r12Remain;
    
  assign w3_TrfcCls   = 3'h0;
  
  assign  w_4DWHdr    = ((r64_BufferBaseAddr0[63:32]==32'h0)?1'b0:1'b1);
  assign  w2_ReqFmt     = {1'b1,w_4DWHdr};
  assign  w5_ReqType    = 5'b0_0000;
  assign  w8_ReqByte0   = {1'b0,w2_ReqFmt,w5_ReqType};
  assign  w8_ReqByte1   = {1'b0,w3_TrfcCls,4'b000};
  assign  w8_ReqByte2   = {1'b0,1'b0,2'b00,2'b00,r10_Length[9:8]};
  assign  w8_ReqByte3   = {r10_Length[7:0]};
  
  assign  w3_ReqStatus  = 3'b000;
  
  //This can be assigned multi-cyle path if necessary
  assign  w8_Tag    = {pTAG_PREFIX,rv_TagNum};  
  assign  w8_ReqByte4 = i16_RequestorID[15:8];
  assign  w8_ReqByte5 = i16_RequestorID[07:0];  
  assign  w8_ReqByte6 = w8_Tag;
  assign  w8_ReqByte7 = 8'hFF;
    
  assign  w8_ReqByte8 = w_4DWHdr?r64_BufferBaseAddr0[63:56]:r32_PostAddr[31:24];
  assign  w8_ReqByte9 = w_4DWHdr?r64_BufferBaseAddr0[56:48]:r32_PostAddr[23:16];
  assign  w8_ReqByteA = w_4DWHdr?r64_BufferBaseAddr0[47:40]:r32_PostAddr[15:08];
  assign  w8_ReqByteB = w_4DWHdr?r64_BufferBaseAddr0[39:32]:r32_PostAddr[07:00];
  assign  w8_ReqByteC = w_4DWHdr?r32_PostAddr[31:24]:8'h0;
  assign  w8_ReqByteD = w_4DWHdr?r32_PostAddr[23:16]:8'h0;
  assign  w8_ReqByteE = w_4DWHdr?r32_PostAddr[15:08]:8'h0;
  assign  w8_ReqByteF = w_4DWHdr?r32_PostAddr[07:00]:8'h0;
  
  assign w_GenerateMSI= r16_TransfersCnt==0?1'b1:1'b0; //TODO
  assign w_DataReady  = ({iv_UsedWords[8:0],3'b0}>={r8_WordsPerTransfer,3'b000})?1'b1:1'b0;
    
  assign wv_Status  = {w_InvalidSetting,w_ErrPayld,10'h0,i12_MaxPload,3'b000,r5_ReqtorState};
  assign w_ErrPayld = i12_MaxPload<pBURST_SIZE*pWORD_SIZE_BYTES?1'b1:1'b0;
  
  assign w_4kSplit  = (r12_DistanceTo4KBBoundary>={1'b0,r8_WordsPerTransfer,3'h0})?1'b0:(|r12_DistanceTo4KBBoundary);
  
  always@(posedge i_Clk or posedge i_ARst)
  if(i_ARst)
    begin 
      r5_ReqtorState              <= pIDLE_STOP;   
      r_ReqToTx                   <= 1'b0;
      r_EnoughPHCred              <= 1'b0;
      r_EnoughPDCred              <= 1'b0;
      r12_RqdPDCred               <= 12'h0;
      r8_RqdPHCred                <= 8'h0;
      r10_LineSent                <= 2'b00;
      r8_IncPHCred                <= 8'h0;
      r12_IncPDCred               <= 12'h0;
      r10_LineToSend_1            <= 2'b00;
      r_LclReq                    <= 1'b0;
      r32_PostAddr                <= 32'h0;
      r_UpdBaseAddrD1             <= 1'b0;
      r_UpdBaseAddrD2             <= 1'b0;
      r_UpdBaseAddrD3             <= 1'b0;
      r12_DistanceTo4KBBoundary   <= 12'h0;
      r12_NextPktPload            <= 12'h0;
      r_Enable      <= 1'b0;
      r_EnableD1    <= 1'b0;
      r_Done1stCycle<= 1'b0;
      r_Done2ndCycle<= 1'b0;      
      rv_TagNum     <= 0;
      r_MsiReq      <= 1'b0;      
      r_BufferPtr   <= 1'b0;
      r_4kSplit     <= 1'b0;
      r_EnableD2    <= 1'b0;
    end
  else 
    begin 
    
    //Clock domain synchronize  
    r_EnableD1  <= rv_Config[0];
    r_EnableD2  <= r_EnableD1;
    
    if(i_Start) r_Enable  <= r_EnableD2;
    
    //Calculate the next data packet 
    r12_DistanceTo4KBBoundary <= 12'h0-r32_PostAddr[11:0];
    
    
    r12_NextPktPload <= r_4kSplit?r12Remain:((w_4kSplit==1'b0)?{r8_WordsPerTransfer,3'h0}:r12_DistanceTo4KBBoundary);
           
    case(r5_ReqtorState)
    pIDLE_STOP: begin             
            if((w_DataReady|r_4kSplit)&r_Enable&(~w_InvalidSetting))  //Only start when enabled and not full
              begin 
                r5_ReqtorState <= pREQTOSEND;
                r8_RqdPHCred <= (i8_CredConPH + 8'h1);                  //Always Consume 1 ReqHdr                   
                r8_IncPHCred <= 8'h1;
                                
                r12_RqdPDCred   <= (i12_CredConPD + {4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
                r12_IncPDCred   <= ({4'b0,r12_NextPktPload[11:4]})+((r12_NextPktPload[3:0]==0)?12'h0:12'h1);
                
                           
                //Calculate how many DW to send
                r10_Length <= r12_NextPktPload[11:2];
                
                //Calculate Line to Send Minus 1
                //Ignore the case of bits 2:0 being nonzero
                r10_LineToSend_1  <= {1'b0,r12_NextPktPload[11:3]}+10'h1;
                  
                
                r_4kSplit <= w_4kSplit;
                
                r12Remain <= {r8_WordsPerTransfer,3'b000}-r12_NextPktPload;
                                
              end          
          r_EnoughPHCred <= 1'b0;
          r_EnoughPDCred <= 1'b0;
          end
    pREQTOSEND: begin 
            r_ReqToTx <= 1'b1;
            if(i_ReqGranted)              
              r5_ReqtorState <= pCALC_CRED;
          end   
    pCALC_CRED: begin 
            r_EnoughPHCred <= ((i8_CredLimPH-r8_RqdPHCred)<8'h80)?1'b1:1'b0;
            r_EnoughPDCred <= ((i12_CredLimPD-r12_RqdPDCred)<12'h800)?1'b1:1'b0;
            if((r_EnoughPHCred|i_InfinitePH)&(r_EnoughPDCred|i_InfinitePD))
              r5_ReqtorState <= pSEND_REQ;
            
          end   
    pSEND_REQ:  begin
          if(i_AstTxHIPReady|i_LclDv)             
            begin
              r10_LineSent<= r10_LineSent+10'd1;
              r_TxDv    <= 1'b1;
              r_TxSop   <= 1'b0;
              r_TxEop   <= 1'b0;
              r_LclReq  <= 1'b0;        
              if(r10_LineSent==10'd0)       //First line              
                begin 
                  r_TxSop   <= 1'b1;
                  r64_TxData  <= {w8_ReqByte4,w8_ReqByte5,w8_ReqByte6,w8_ReqByte7,
                          w8_ReqByte0,w8_ReqByte1,w8_ReqByte2,w8_ReqByte3};         
                  //We may need to turn on the Request when 
                  //3DW and the first DW is not Quadword Aligned
                  //Currently this is not supported
                  r_LclReq  <= 1'b0;      
                  rv_TagNum <= rv_TagNum + 8'h1;
                end         
              else 
              if(r10_LineSent==10'd1)       //Second line 
                begin                                 
                  r64_TxData  <= {w8_ReqByteC,w8_ReqByteD,w8_ReqByteE,w8_ReqByteF,
                          w8_ReqByte8,w8_ReqByte9,w8_ReqByteA,w8_ReqByteB};         
                  r_LclReq  <= 1'b1;      
                end           
              else 
                begin                             
                  r64_TxData  <= iv_LclData;
                  r_TxEop   <= (r10_LineToSend_1==r10_LineSent)?1'b1:1'b0;
                  r_LclReq  <= (r10_LineToSend_1==r10_LineSent)?1'b0:1'b1;                  
                end
            end
          else          
            begin 
              r_TxDv  <= 1'b0;
              r_TxSop <= 1'b0;
              r_TxEop <= 1'b0;            
            end         
          
          if(r_TxEop)
              begin 
                r5_ReqtorState <= pSEND_DONE;
                r_LclReq  <= 1'b0;
                r_TxDv    <= 1'b0;
                r10_LineSent<= 10'h0;
                r_ReqToTx   <= 1'b0;
                r32_PostAddr<= (r32_PostAddr+{20'h0,r10_Length,2'b00});
                r_Done1stCycle <= 1'b0;
                r_Done2ndCycle <= 1'b0;                
                r16_TransfersCnt <= r16_TransfersCnt-1;
              end
          end
    pSEND_DONE: begin             
            r_Done1stCycle <= 1'b1;           //1 cycle: Calculating r12_DistanceTo4KBBoundary
            r_Done2ndCycle <= r_Done1stCycle; //2 cycle: Calculating r12_NextPktPload
            r_MsiReq    <= rv_Config[2] & r_Done1stCycle & w_GenerateMSI;
            if(r_Done2ndCycle & ((~r_MsiReq)|(r_MsiReq&i_IrqMsiAck)))
              begin 
              r5_ReqtorState  <= pIDLE_STOP;  
              if(r_MsiReq)
                begin                                                 
                r_MsiReq    <= 1'b0;
                end               
              end
          end
    endcase     
    
    
    
    
    if(i_Start & r_Enable)
      begin                               
        r_BufferPtr     <= ~ r_BufferPtr;
        r32_PostAddr    <= r_BufferPtr?r64_BufferBaseAddr0[31:0]:r64_BufferBaseAddr1[31:0];              //Reset Write address 
        r5_ReqtorState  <= pIDLE_STOP;
        r16_TransfersCnt<= r16_TransfersIrq;
      end
  end
    
    
    
    assign o_ReqToTx  = r_ReqToTx;
    assign o_AstTxDv  = r_TxDv;
    assign o_AstTxEop = r_TxEop;
    assign o_AstTxSop = r_TxSop;
    assign ov_AstTxData = r64_TxData;   
    assign o_LclReq   = r_LclReq & i_AstTxHIPReady & (~i_LclEmpty); //Stop reading immediately, that cycle may still have valid data 

    assign o_UpdPHCred  = r_TxSop & r_TxDv;
    assign o_UpdPDCred  = r_TxEop & r_TxDv;
    assign o8_IncPHCred = r8_IncPHCred;
    assign o12_IncPDCred= r12_IncPDCred;
    
    
    assign o_IrqMsiReq  = r_MsiReq;
    assign o5_IrqMsiNum = rv_Config[8:4];
  
  
  assign o256_Dbg[0] = i_Start;
  assign o256_Dbg[1] = i_LclDv;  
  assign o256_Dbg[2] = r_LclReq;  
  assign o256_Dbg[3] = w_4kSplit;
  assign o256_Dbg[19: 4] = iv_UsedWords;
  assign o256_Dbg[20]    = w_DataReady;
  assign o256_Dbg[21]    = r_Enable;
  assign o256_Dbg[22]    = r_TxSop;
  assign o256_Dbg[23]    = r_TxEop;
  assign o256_Dbg[24]    = r_TxDv;
  assign o256_Dbg[29:25] = r5_ReqtorState;
  assign o256_Dbg[41:30] = r12_NextPktPload;
  assign o256_Dbg[51:42] = r10_Length;
  assign o256_Dbg[52]    = r_BufferPtr;
  assign o256_Dbg[53]    = w_4DWHdr;
  assign o256_Dbg[69:54] = r32_PostAddr[21:6];
  assign o256_Dbg[79:70] = r10_LineSent;
  assign o256_Dbg[91:80] = r12Remain;
  assign o256_Dbg[104:92] = r12_DistanceTo4KBBoundary;
  assign o256_Dbg[114:105] = r10_LineToSend_1;
  assign o256_Dbg[192:128]= r64_TxData[63:0];

endmodule 
