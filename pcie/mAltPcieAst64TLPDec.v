/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	:

Remarks		:

Revision	:
	Date	Author	Description

*/
`define 	dBYTE0			31
`define 	dBYTE1			`dBYTE0-8
`define 	dBYTE2			`dBYTE1-8
`define 	dBYTE3			`dBYTE2-8
`define 	dBYTE4			63
`define 	dBYTE5			`dBYTE4-8
`define 	dBYTE6			`dBYTE5-8
`define 	dBYTE7			`dBYTE6-8

`define 	dBYTE8		31
`define 	dBYTE9		`dBYTE8-8
`define 	dBYTE10		`dBYTE9-8
`define 	dBYTE11		`dBYTE10-8
`define 	dBYTE12		63
`define 	dBYTE13		`dBYTE12-8
`define 	dBYTE14		`dBYTE13-8
`define 	dBYTE15		`dBYTE14-8


`define 	dTLP_FORMAT		`dBYTE0-1-:2
`define		dTLP_TYPE		`dBYTE0-3-:5
`define 	dTLP_TC			`dBYTE1-1-:3
`define 	dTLP_TD			`dBYTE2-0-:1
`define 	dTLP_EP			`dBYTE2-1-:1
`define 	dTLP_ATTR		`dBYTE2-2-:2
`define 	dTLP_LENGTH		`dBYTE2-6-:10
`define 	dTLP_REQID		`dBYTE4-0-:16
`define 	dTLP_TAG		`dBYTE6-0-:8
`define 	dTLP_LASTBE		`dBYTE7-0-:4
`define 	dTLP_FRSTBE		`dBYTE7-4-:4
`define 	dTLP_CMPLBC		`dBYTE6-4-:12
`define 	dTLP_CPLTAG		`dBYTE10-:8

module mAltPcieAst64Dec(
	input i_AstRxSop,
	input i_AstRxEop,
	input i_AstRxEmpty,//NotUsed
	input i_AstRxDv,
	input 	[63:0] 	iv_AstRxData,
	
	output 	reg [1:0] 	o2_Fmt			,	//Header Format
	output 	reg [4:0]	o5_Type			,	//Header Type
	output 	reg [2:0]	o3_TrfcCls		,	//Trafic Class
	output 	reg [1:0]	o2_Attr			,	//Attribute		
	output 	reg 		o_TLPDigest		,	//Digest Present
	output 	reg 		o_EP			,	//Poissoned
	output 	reg	[9:0]	o10_Length		,	//Length in Double Word
	output 	reg	[63:0]	o64_Addr		,	//Address
	output 	reg	[15:0]	o16_DescCplID	,	//Requester ID
	output 	reg	[15:0]	o16_DescReqID	,	//Requester ID
	output 	reg	[07:0]	o8_DescTag		,	//Tag	
	output 	reg [03:0]	o4_DescLastDWBE	,	//Last Double Word Byte Enable
	output 	reg [03:0]	o4_DescFrstDWBE	,	//First Double Word Byte Enable
	output 	reg [11:0]	o12_CmplByteCnt	,	//The remaining data in byte 
	output 	[63:0]		o64_TLPData		,	//PacketData, the handler has to know the data format and boundary
	output 	reg	[09:0]	o10_WordCnt		,
	
	input i_Clk,
	input i_ARst
);



	reg	r_SecondWord;
	wire w_TLPFmt4n3DW;		//4 DW, not 3DW
	wire w_TLPFmtWithData;	//With Data
	
	assign w_TLPFmt4n3DW 	= o2_Fmt[0];
	assign w_TLPFmtWithData	= o2_Fmt[1];
	assign o64_TLPData		= iv_AstRxData;
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)	
		begin 
			o10_WordCnt 	<= 10'h0;
			r_SecondWord 	<= 1'b0;
			o2_Fmt			<= 2'b0;
			o5_Type			<= 5'b0;
			o3_TrfcCls		<= 3'b0;	
			o2_Attr			<= 2'b0;
			o_TLPDigest		<= 1'b0;	
			o_EP			<= 1'b0;	
			o10_Length		<= 10'b0;	
			o16_DescReqID	<= 16'b0;	
			o16_DescCplID	<= 16'b0;
			o8_DescTag		<= 8'h0;	
			o4_DescLastDWBE	<= 4'b0;
			o4_DescFrstDWBE	<= 4'b0;	
			o12_CmplByteCnt	<= 12'h0;
		end 
	else 
		begin
			if(i_AstRxDv)	o10_WordCnt <= (i_AstRxEop)?10'h0:(o10_WordCnt+10'h1);				
			
			if(i_AstRxDv&i_AstRxSop)
				begin 
					o2_Fmt			<= 	iv_AstRxData[`dTLP_FORMAT];
					o5_Type			<= 	iv_AstRxData[`dTLP_TYPE];
					o3_TrfcCls		<= 	iv_AstRxData[`dTLP_TC];
					o2_Attr			<= 	iv_AstRxData[`dTLP_ATTR];
					o_TLPDigest		<= 	iv_AstRxData[`dTLP_TD];
					o_EP			<= 	iv_AstRxData[`dTLP_EP];
					o10_Length		<= 	iv_AstRxData[`dTLP_LENGTH];					
					o16_DescReqID	<= 	iv_AstRxData[`dTLP_REQID];
					o16_DescCplID	<= 	iv_AstRxData[`dTLP_REQID];
					o8_DescTag		<= 	iv_AstRxData[`dTLP_TAG];
					o4_DescLastDWBE	<= 	iv_AstRxData[`dTLP_LASTBE];
					o4_DescFrstDWBE	<= 	iv_AstRxData[`dTLP_FRSTBE];
					o12_CmplByteCnt	<= 	iv_AstRxData[`dTLP_CMPLBC];
				end
			
			if(i_AstRxDv)
				r_SecondWord 	<= i_AstRxSop;//Second word			
			
			//Only valid with AST64
			if(r_SecondWord&i_AstRxDv) begin 
				if(o2_Fmt[0])	//4 Double Word
					o64_Addr 	<= 	{iv_AstRxData[`dBYTE8-:32],iv_AstRxData[`dBYTE12-:30],2'b00};
				else			//3 Double Word
					o64_Addr 	<= 	{32'h0,iv_AstRxData[`dBYTE8-:30],2'b00};
				if(o5_Type==5'b0_1010)
					begin 
					o16_DescReqID	<=	iv_AstRxData[`dBYTE8-:16];
					o8_DescTag		<= 	iv_AstRxData[`dBYTE10-:8];
					end 
			end
		end
endmodule
