/*
Copyright � 2013 lieumychuong@gmail.com

File    :
Description :

Remarks   :

Revision  :
  Date  Author  Description

*/


interface if_AvalonStream_t #(parameter pWIDTH=64);
  
  wire  w_Ready;
  wire  w_Valid;
  wire  w_Eop;
  wire  w_Sop;
  wire  w_Empty;
  wire  w_Error;
  wire  [pWIDTH-1:0]  wv_Data;
  
endinterface

interface if_AvalonBus_t #(parameter pDWIDTH=32, pAWIDTH=10);

  wire  w_Read;
  wire  w_Write;
  wire  w_WaitReq;
  wire  [pDWIDTH-1:0] wv_WriteData;
  wire  [pDWIDTH-1:0] wv_ReadData;
  wire  [pAWIDTH-1:0] wv_Address;


endinterface

interface if_WishboneBus_t #(parameter pDWIDTH=32, pAWIDTH=10);

  wire w_Cyc;
  wire w_Stb;
  wire w_WnR;
  wire w_Ack;
  wire [pDWIDTH-1:0] wv_WriteData;
  wire [pDWIDTH-1:0] wv_ReadData;
  wire [pAWIDTH-1:0] wv_Address;
  wire [3:0]  w4_ByteEn;
  wire w_Clk;
endinterface

interface if_VideoStream;
  
  wire sof;
  wire sav;
  wire eav;
  wire vbk;
  wire sol;
  wire den;
  wire [39:0] pixels;

endinterface
