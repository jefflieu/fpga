/*
Copyright � 2013 lieumychuong@gmail.com

File    :
Description : This module handles
        IORead/Write
        MemRead/Write with Data Length not greater than 2DWs
      This module is suitable for status/configuration data 
Remarks   :

Revision  :
  Date  Author  Description

*/

`define dTLP_TYPE_MEMRD   5'b0_0000
`define dTLP_TYPE_MEMWR   5'b0_0000
`define dTLP_TYPE_IORD    5'b0_0010
`define dTLP_TYPE_IOWR    5'b0_0010



module mAltPcieAst64LBus #(
  parameter pBUS_ADDR_WIDTH=12)(  
  //Avalon Stream TX
  output  o_AstTxSop,
  output  o_AstTxEop,
  output  o_AstTxEmpty,//NotUsed
  output  o_AstTxDv,
  output  [63:0]  ov_AstTxData,
  input   i_AstTxHIPReady,
  
  //Avalon Stream RX
  input i_AstRxSop,
  input i_AstRxEop,
  input i_AstRxEmpty,//NotUsed
  input i_AstRxDv,
  input   [63:0]  iv_AstRxData,
  output  o_AstRxReady,
  output  o_AstRxMask,
  input   [6:0] i7_BARSelect,
  
  //Credit interface  
  input   [7:0] i8_CredLimPH,   //Posted Header
  input [7:0] i8_CredLimCH,   //Completion Header
  input [7:0] i8_CredLimNH,   //Non Posted Header 
  input [11:0] i12_CredLimPD, //Posted Data
  input [11:0] i12_CredLimCD, //Completion Data
  input [11:0] i12_CredLimND, //Nonposted Ddata
  
  input   [7:0] i8_CredConPH,   //Posted Header
  input [7:0] i8_CredConCH,   //Completion Header
  input [7:0] i8_CredConNH,   //Non Posted Header 
  input [11:0] i12_CredConPD, //Posted Data
  input [11:0] i12_CredConCD, //Completion Data
  input [11:0] i12_CredConND, //Nonposted Ddata
  
  input   i_InfinitePH,
  input   i_InfiniteCH,
  input   i_InfiniteNH,
  input   i_InfinitePD,
  input   i_InfiniteCD,
  input   i_InfiniteND,
  
  input   [15:0]  i16_CompletorID,//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
  
  //Arbitration Interface
  output  o_ReqToTx,
  input i_ReqGranted,
  output  o_SupportedMsg,     //Raise this flag when the Msg is supported
                  //This must be raised no later than 2 cycle after EOP 
  
  
  //Wishbone Bus master
  output  [6:0] o7_BARSelect,
  output  o_WbCyc,
  output  o_WbStb,  
  output  o_WbWnR,
  output  [pBUS_ADDR_WIDTH-1:0] ov_WbAddr,
  output  [31:0]  o32_WbWrData,
  input   [31:0]  i32_WbRdData,
  input   i_WbAck,
  output  [3:0] o4_ByteEn,

  
  input   i_Clk,
  input   i_ARst);

  wire [1:0]  w2_Fmt      ; //Header Format
  wire [4:0]  w5_Type     ; //Header Type
  wire [2:0]  w3_TrfcCls    ; //Trafic Class
  wire [1:0]  w2_Attr     ; //Attribute   
  wire    w_TLPDigest   ; //Digest Present
  wire    w_EP      ; //Poissoned
  wire [9:0]  w10_Length    ; //Length in Double Word
  wire [63:0] w64_Addr    ; //Address

  wire [15:0] w16_ReqID ; //Requester ID
  wire [07:0] w8_Tag    ; //Tag 
  wire [03:0] w4_LastDWBE ; //Last Double Word Byte Enable
  wire [03:0] w4_FrstDWBE ; //First Double Word Byte Enable
  
  wire [63:0] w64_TLPData   ; //PacketData, the handler has to know the data format and boundary
  wire [09:0] w10_WordCnt   ;
  
  reg [31:0]  r32_FirstDW,r32_SecondDW;
  
  wire  [9:0] w10_LineCnt;  
  reg   r_Sop_D,r_Eop_D;
  reg   r_Read, r_Write,r_Ready;
  wire  w_TwoDW;
  wire  w_CmplRequired;
  wire  w_MemReq,w_IOReq;
  reg [6:0] r7_BARSelect;
  wire w_TimeOut;
  
  mAltPcieAst64Dec uTLPDecode(
  .i_AstRxSop   (i_AstRxSop),
  .i_AstRxEop   (i_AstRxEop),
  .i_AstRxEmpty (i_AstRxEmpty),//NotUsed
  .i_AstRxDv    (i_AstRxDv),
  .iv_AstRxData (iv_AstRxData),
  
  .o2_Fmt         (w2_Fmt   ),  //Header Format
  .o5_Type        (w5_Type  ),  //Header Type
  .o3_TrfcCls     (w3_TrfcCls ),//Trafic Class
  .o2_Attr        (w2_Attr  ),  //Attribute   
  .o_TLPDigest    (w_TLPDigest),//Digest Present
  .o_EP           (w_EP   ),    //Poissoned
  .o10_Length     (w10_Length ),//Length in Double Word
  .o64_Addr       (w64_Addr ),  //Address
  
  .o16_DescReqID  (w16_ReqID  ),//Requester ID
  .o8_DescTag     (w8_Tag   ),  //Tag 
  .o4_DescLastDWBE(w4_LastDWBE),//Last Double Word Byte Enable
  .o4_DescFrstDWBE(w4_FrstDWBE),//First Double Word Byte Enable
  
  .o64_TLPData  (     ),        //PacketData, the handler has to know the data format and boundary
  .o10_WordCnt  (w10_LineCnt),  
  
  .i_Clk      (i_Clk    ),
  .i_ARst     (i_ARst   ));

  assign  w_MemReq    = ((w5_Type==`dTLP_TYPE_MEMWR)||(w5_Type==`dTLP_TYPE_MEMRD))?1'b1:1'b0;
  assign  w_IOReq     = ((w5_Type==`dTLP_TYPE_IORD)||(w5_Type==`dTLP_TYPE_IOWR))?1'b1:1'b0;
  assign  o_SupportedMsg  = ((w_MemReq && w10_Length<=2)||w_IOReq)?1'b1:1'b0;

  assign  w_CmplRequired  =   ((w5_Type==`dTLP_TYPE_MEMRD&&(~w2_Fmt[1]))||w_IOReq)?1'b1:1'b0;//MemRead or IO Read/Write
  assign  w_TwoDW     =   (w10_Length==10'h2)?1'b1:1'b0;
  
  /*  
  TLP Receiver
  This portion handles extraction of relevant data and generate signals and flag to the bus controller  
  This receiver only supports maximum of 2 DW write
  */
  always@(posedge i_Clk or posedge i_ARst)
    if(i_ARst)
      begin 
        r_Sop_D     <= 1'b0;
        r_Eop_D     <= 1'b0;
        r32_FirstDW   <= 32'h0;
        r32_SecondDW  <= 32'h0;
        r_Read      <= 1'b0;
        r_Write     <= 1'b0;
        r7_BARSelect  <= 7'h0;
      end
    else 
      begin
        r_Sop_D <= i_AstRxSop;
        r_Eop_D <= i_AstRxEop;
        
        //Extract Data
        if(w2_Fmt[1])     //Write
          begin 
            //4 cases, 4DW or 3DW, Address is QWORD Aligned or NOT                    
            if(w2_Fmt[0]) //4 DW
              begin               
                if(~w64_Addr[2])
                  begin
                    if(w10_LineCnt==10'h2) r32_FirstDW  <= iv_AstRxData[31:00];
                    if(w10_LineCnt==10'h2) r32_SecondDW <= iv_AstRxData[63:32];
                  end               
                else 
                  begin 
                    if(w10_LineCnt==10'h2) r32_FirstDW  <= iv_AstRxData[63:32];
                    if(w10_LineCnt==10'h3) r32_SecondDW <= iv_AstRxData[31:00];
                  end           
              end
            else      //3 DW
              begin 
                //Capture First DW                
                if  ( iv_AstRxData[2] &&  w10_LineCnt==10'h1) //Not QW Aligned                  
                    r32_FirstDW <= iv_AstRxData[63:32];                                     
                else if ((~w64_Addr[2]) &&  w10_LineCnt==10'h2) //QW Aligned                  
                    r32_FirstDW <= iv_AstRxData[31:00];                                       
                //Capture Second DW
                if    ((w64_Addr[2])  && w10_LineCnt==10'h2)  //Not QW Aligned
                    r32_SecondDW <= iv_AstRxData[31:00];
                else if ((~w64_Addr[2]) && w10_LineCnt==10'h2)  //QW Aligned                                        
                    r32_SecondDW <= iv_AstRxData[63:32];  
              end     
          end
        
        if(i_AstRxEop & i_AstRxDv & o_SupportedMsg & (~w2_Fmt[1]))  //Read
          r_Read <= 1'b1;
        else 
          r_Read <= 1'b0;
          
        if(i_AstRxEop & i_AstRxDv & o_SupportedMsg & w2_Fmt[1])   //Write
          r_Write <= 1'b1;
        else 
          r_Write <= 1'b0;
        
        if(i_AstRxEop & i_AstRxDv)
          r7_BARSelect <= i7_BARSelect;
      end
  
  assign o_AstRxReady =  r_Ready;
  
  /*Wishbone Controller
  You can replace this block to generate appropriate master signals for your system
  This controller will split a posted write of 2 DWORDS to 2 bus transactions
  When the Other block initiate r_Read or r_Write
    - Capture how many double words to be transfer
    - Capture the start address
    - Initiate a bus cycle if there are non-zero DW to transfer
  */
  reg r_BusCycle; 
  reg [pBUS_ADDR_WIDTH-1:0] rv_Addr;
  reg [1:0] r2_DWComplete;
  reg [1:0] r2_DWToXfer;
  wire w_BusComplete;
  reg [31:0] r32_WrData;
  reg [31:0] r32_RdDataLo ,r32_RdDataHi;  
  reg [2:0] r3_TmrWait;
  always@(posedge i_Clk or posedge i_ARst)
    if(i_ARst)
      begin 
        r_BusCycle    <= 1'b0;  
        rv_Addr     <= 32'h0;
        r2_DWComplete <= 2'b00;
        r2_DWToXfer   <= 2'b00;
        r_BusCycle    <= 1'b0;
        r32_RdDataLo  <= 32'h0;
        r32_RdDataHi  <= 32'h0; 
        r3_TmrWait    <= 3'h0;
      end
    else 
      begin 
        
        if(r_Read|r_Write)
          r2_DWToXfer <= (w10_Length[1:0]);
        
        if(r_Read|r_Write) 
          rv_Addr <= w64_Addr[pBUS_ADDR_WIDTH-1:0];
        else if(r_BusCycle&i_WbAck) 
          rv_Addr <= rv_Addr+32'h4;
        
        if(r_Read|r_Write) //Initialize DW Complete
          r2_DWComplete <= 2'b01;
        else if(r_BusCycle&(i_WbAck|w_TimeOut))
          r2_DWComplete <= r2_DWComplete+2'b1;
        
        //Start a bus cycle when 
        //There are more DW to transfer than the completed
        //DW to Transfer is not zero
        if(r_BusCycle==1'b0 && (r2_DWToXfer>=r2_DWComplete) && r2_DWToXfer!=2'b00)
          r_BusCycle <= 1'b1;
        else if(r_BusCycle==1'b1 &&(i_WbAck||w_TimeOut))
          r_BusCycle  <= 1'b0;      
        
        if(r_BusCycle & (i_WbAck|w_TimeOut) & (~w2_Fmt[1]) & r2_DWComplete==2'b01)
          r32_RdDataLo <= i_WbAck?i32_WbRdData:32'hFFFFFFFF;
        if(r_BusCycle & (i_WbAck|w_TimeOut) & (~w2_Fmt[1]) & r2_DWComplete==2'b10) 
          r32_RdDataHi <= i_WbAck?i32_WbRdData:32'hFFFFFFFF; 
        
        if(r_BusCycle)
          r3_TmrWait<=r3_TmrWait+1;
        else 
          r3_TmrWait<=3'h0;
      end 
  assign w_Timeout  = (r3_TmrWait==3'b111)?1'b1:1'b0;   
  assign o_WbCyc    = r_BusCycle;
  assign o_WbStb    = r_BusCycle;
  assign o_WbWnR    = r_BusCycle&w2_Fmt[1];//Write  
  assign o32_WbWrData = (r2_DWComplete==2'b01)?r32_FirstDW:r32_SecondDW;
  assign o7_BARSelect = r7_BARSelect;
  assign ov_WbAddr  = rv_Addr;
  assign o4_ByteEn  = (r2_DWComplete==2'b01)?w4_FrstDWBE:w4_LastDWBE;
  
  
  //Pulse the w_BusComplete to start a compltion cycle if necessary
  assign w_BusComplete= (r2_DWComplete==r2_DWToXfer&&r_BusCycle&&(i_WbAck||w_TimeOut))?1'b1:1'b0; 
  
  
  /*
  Completor handles generating of Completion TLP  
  */
  localparam pIDLE_STOP = 5'b00001; 
  localparam pREQTOSEND = 5'b00010;
  localparam pCALC_CRED = 5'b00100;
  localparam pSEND_CPL  = 5'b01000;
  localparam pSEND_DONE = 5'b10000;
  
  reg [4:0] r5_CmpltorState;
  reg [7:0] r8_RqdCHCred;   //Cummulative Required Completion Header Credit
  reg [11:0]  r12_RqdCDCred;    //Cummulative Required Completion Data Credit
  reg r_EnoughCHCred;
  reg r_EnoughCDCred;
  reg r_ReqToTx;
  reg [1:0] r2_LineToSend,r2_LineSent;
  reg [63:0]  r64_TxData;
  reg r_TxSop, r_TxEop, r_TxDv;
  wire [7:0]  w8_CmplByte0,w8_CmplByte1,w8_CmplByte2,w8_CmplByte3;
  wire [7:0]  w8_CmplByte4,w8_CmplByte5,w8_CmplByte6,w8_CmplByte7;
  wire [7:0]  w8_CmplByte8,w8_CmplByte9,w8_CmplByteA,w8_CmplByteB;
  wire [7:0]  w8_CmplByteC,w8_CmplByteD,w8_CmplByteE,w8_CmplByteF;
  wire [1:0]  w2_CmplFmt;
  wire [4:0]  w5_CmplType;
  wire [2:0]  w3_CmplStatus;
  wire [11:0] w12_CmplByteCnt;
  wire [6:0]  w7_CmplLowerAddr;
  
  assign o_ReqToTx = r_ReqToTx;
  
  assign  w2_CmplFmt    = {((w_MemReq|w_IOReq)&(~w2_Fmt[1])),1'b0};
  assign  w5_CmplType   = 5'b0_1010;
  assign  w8_CmplByte0  = {1'b0,w2_CmplFmt,w5_CmplType};
  assign  w8_CmplByte1  = {1'b0,w3_TrfcCls,4'b000};
  assign  w8_CmplByte2  = {1'b0,1'b0,2'b00,2'b00,w10_Length[9:8]};
  assign  w8_CmplByte3  = {w10_Length[7:0]};
  
  assign  w3_CmplStatus = 3'b000;
  
  //This can be assigned multi-cyle path if necessary
  assign  w12_CmplByteCnt = {8'h0,({3'h0,w4_FrstDWBE[0]}+{3'h0,w4_FrstDWBE[1]}+{3'h0,w4_FrstDWBE[2]}+{3'h0,w4_FrstDWBE[3]}+
                {3'h0,w4_LastDWBE[0]}+{3'h0,w4_LastDWBE[1]}+{3'h0,w4_LastDWBE[2]}+{3'h0,w4_LastDWBE[3]})};
  assign  w8_CmplByte4  = i16_CompletorID[15:8];
  assign  w8_CmplByte5  = i16_CompletorID[07:0];  
  assign  w8_CmplByte6  = {w3_CmplStatus,1'b0,w12_CmplByteCnt[11:8]};
  assign  w8_CmplByte7  = {w12_CmplByteCnt[7:0]};
  
  assign  w7_CmplLowerAddr[6:2] = w64_Addr[6:2];
  assign  w7_CmplLowerAddr[1:0] = w4_FrstDWBE[0]?2'b00:(w4_FrstDWBE[1]?2'b01:(w4_FrstDWBE[2]?2'b10:2'b11));
  
  assign  w8_CmplByte8 = w16_ReqID[15:8];
  assign  w8_CmplByte9 = w16_ReqID[07:0];
  assign  w8_CmplByteA = w8_Tag;
  assign  w8_CmplByteB = {1'b0,w7_CmplLowerAddr};
  always@(posedge i_Clk or posedge i_ARst)
  if(i_ARst)
    begin 
      r5_CmpltorState <= pIDLE_STOP;    
      r_ReqToTx     <= 1'b0;
      r_EnoughCDCred  <= 1'b0;
      r_EnoughCHCred  <= 1'b0;
      r12_RqdCDCred <= 12'h0;
      r8_RqdCHCred  <= 8'h0;
      r2_LineSent   <= 2'b00;
      r2_LineToSend <= 2'b00;
      r_Ready     <= 1'b1;
    end
  else 
    begin 
    
    case(r5_CmpltorState)
    pIDLE_STOP: begin 
            if(w_BusComplete & w_CmplRequired) 
              begin 
                r5_CmpltorState <= pREQTOSEND;
                if((w_MemReq & (~w2_Fmt[1]))||w_IOReq)  //Memory Read Request or IOReq
                  r8_RqdCHCred <= (i8_CredConCH + 8'h1);//Always Consume 1 CmplHdr    
                if((w_MemReq|w_IOReq)&(~w2_Fmt[1]))
                  r12_RqdCDCred <= (i12_CredConCD + 12'h1);//Always Consume 1 CmplData

                //Calculate Line to Send                              
                case({w2_CmplFmt,w64_Addr[2]})
                3'b000 :                  //NoData,3DW,QWAligned
                    r2_LineToSend <= 2'd1;        //2 Lines                    
                3'b001 :                  //NoData,3DW,Not-QWAligned
                    r2_LineToSend <= 2'd1;        //2 Lines                   
                3'b010 :                  //NoData,4DW,QWAligned
                    r2_LineToSend <= 2'd1;        //2 Lines                                   
                3'b011 :                  //NoData,4DW,Not QWAligned
                    r2_LineToSend <= 2'd1;        //2 Lines
                3'b100 :                  //Data,3DW,QWAligned
                    r2_LineToSend <= 2'd2;        //3 Lines
                3'b101 :                  //Data,3DW,Not QWAligned
                    r2_LineToSend <= w_TwoDW?2'd2:2'b1; //3 Lines or 2 Lines
                3'b110 :                  //Data,4DW,QWAligned
                    r2_LineToSend <= 2'd2;        //3 lines
                3'b111 :                  //Data,4DW,Not QWAligned, should not happen
                    r2_LineToSend <= 2'd3;        //4 lines                   
                endcase
                
              end
          
          r_EnoughCHCred <= 1'b0;
          r_EnoughCDCred <= 1'b0;
          end
    pREQTOSEND: begin 
            r_ReqToTx <= 1'b1;
            if(i_ReqGranted)
              r5_CmpltorState <= pCALC_CRED;
          end   
    pCALC_CRED: begin 
            r_EnoughCHCred <= ((i8_CredLimCH-r8_RqdCHCred)<=8'h40)?1'b1:1'b0;
            r_EnoughCDCred <= ((i12_CredLimCD-r12_RqdCDCred)<=12'h400)?1'b1:1'b0;
            if((r_EnoughCHCred|i_InfiniteCH)&(r_EnoughCDCred|i_InfiniteCD))
              r5_CmpltorState <= pSEND_CPL;
            
          end   
    pSEND_CPL:  begin 
          if(i_AstTxHIPReady)
            begin 
              r2_LineSent <= r2_LineSent+2'b01;
              r_TxDv <= 1'b1;
              case(r2_LineSent)
              2'b00:  begin             
                  r_TxSop   <= 1'b1;
                  r64_TxData  <= {w8_CmplByte4,w8_CmplByte5,w8_CmplByte6,w8_CmplByte7,
                          w8_CmplByte0,w8_CmplByte1,w8_CmplByte2,w8_CmplByte3};
                  end 
              2'b01:  begin 
                  r_TxSop   <= 1'b0;
                  r64_TxData  <= {(w64_Addr[2])?r32_RdDataLo:32'h0,
                          w8_CmplByte8,w8_CmplByte9,w8_CmplByteA,w8_CmplByteB};
                  r_TxEop   <= (r2_LineToSend==2'd1)?1'b1:1'b0;
                  end
              2'b10:  begin 
                  r_TxSop   <= 1'b0;
                  r64_TxData  <= (w64_Addr[2])?{32'h0,r32_RdDataHi}:{r32_RdDataHi,r32_RdDataLo};
                  r_TxEop   <= (r2_LineToSend==2'd2)?1'b1:1'b0;
                  end
              2'b11:  begin                   
                  r_TxEop   <= (r2_LineToSend==2'd3)?1'b1:1'b0;
                  end
              endcase
              if(r_TxEop) 
                begin 
                  r5_CmpltorState <= pSEND_DONE;
                  r_TxDv <= 1'b0;               
                end
            end
          else 
            begin 
            r_TxDv <= 1'b0;
            r_TxSop<= 1'b0;
            r_TxEop<= 1'b0;
            end
          end
    pSEND_DONE: begin 
            r5_CmpltorState <= pIDLE_STOP;          
            r_Ready <= 1'b1;
            r_ReqToTx <= 1'b0;
          end
    endcase     
    
    if((i_AstRxEop & i_AstRxDv & o_SupportedMsg)) r_Ready <= 1'b0;
    else if(w_BusComplete) r_Ready <= ~w_CmplRequired;
        
    end
    
    assign o_AstTxDv = r_TxDv;
    assign o_AstTxEop= r_TxEop;
    assign o_AstTxSop= r_TxSop;
    assign ov_AstTxData = r64_TxData;
    
  
  
endmodule 
