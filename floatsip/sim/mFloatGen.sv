

module mFloatGenerator #(parameter
			pPrecision=2,
			pWidthExp=8,
			pWidthMan=23,	
			pExpW = (pPrecision==1)?08:((pPrecision==2)?11:pWidthExp),
			pManW = (pPrecision==1)?23:((pPrecision==2)?52:pWidthMan),
			pPipeline =5
		) (
	input i_Clk,
	input i_ClkEn,
	output [pExpW+pManW:0] ov_FltOut
);
	localparam pW = ((pManW%32)==0)?pManW/32:(pManW/32)+1;
	reg r_Sign;
	reg [pExpW-1:0] rv_Exp;
	reg [pManW-1:0] rv_Man;
	
	integer I;
	integer W;

	always@(posedge i_Clk)
	begin
		if(i_ClkEn)
			begin
				r_Sign = $random()&1'b1;
				rv_Exp = $random()& {pExpW{1'b1}};
				for(I=0;I<(pW-1);I=I+1)
					rv_Man[I*32+31-:32] = $random();
				rv_Man[pManW-1:(pW-1)*32]=$random();		
			end
	end	
	assign ov_FltOut = {r_Sign,rv_Exp,rv_Man};
endmodule
