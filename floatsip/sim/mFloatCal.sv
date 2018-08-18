module mFloatCal #(parameter
			pPrecision=2,
			pWidthExp=8,
			pWidthMan=23,	
			pExpW = (pPrecision==1)?08:((pPrecision==2)?11:pWidthExp),
			pManW = (pPrecision==1)?23:((pPrecision==2)?52:pWidthMan),
			pPipeline =5
		) (
	input i_Clk,
	input i_ClkEn,
	input 	[pExpW+pManW:0] iv_InputA,		//Input A following IEEE754 binary format of single or double precision
	input 	[pExpW+pManW:0] iv_InputB,		//Input B following IEEE754 binary format of single or double precision
	input 	[2:0] i3_Opcode,
	input	i_Dv,
	
	output 	[pExpW+pManW:0] ov_AB,	//Product of A and B
	output	o_Overflow,
	output	o_Underflow,
	output	o_NAN,
	output	o_PINF,
	output	o_NINF	
);
	localparam pBias = (2**(pExpW-1))-1;
	int exA,exB;
	real fltA,fltB,fltAB;
	always@(*)
		begin
			exA = $signed(iv_InputA[pManW+pExpW-1:pManW])-pBias-pManW;
			fltA = {1'b1,iv_InputA[pManW-1:0]}*(2**exA);						
			if(iv_InputA[pManW+pExpW]) fltA = -fltA;
			
			exB = $signed(iv_InputB[pManW+pExpW-1:pManW])-pBias-pManW;
			fltB = {1'b1,iv_InputB[pManW-1:0]}*(2**exB);
			if(iv_InputB[pManW+pExpW]) fltB = -fltB;
			fltAB = fltA*fltB;
			$display("A: %d %d %x %1.20e",iv_InputA[pExpW+pManW],exA,iv_InputA[pManW-1:0],fltA);		
			$display("B: %d %d %x %1.20e",iv_InputB[pExpW+pManW],exB,iv_InputB[pManW-1:0],fltB);		
		end
	
	
	assign ov_AB = fltAB;

	function [pExpW+pManW:0] fFltToBin(real fltIn);
		begin
			int E;
			reg rS;
			E=0;
			if(fltIn>=0.0) rS=1'b0;else rS=1'b1;					
		end	
	endfunction
endmodule