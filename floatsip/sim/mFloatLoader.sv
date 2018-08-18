module mFloatLoader #(parameter
			pPrecision=2,
			pWidthExp=8,
			pWidthMan=23,	
			pExpW = (pPrecision==1)?08:((pPrecision==2)?11:pWidthExp),
			pManW = (pPrecision==1)?23:((pPrecision==2)?52:pWidthMan),
			pDataCol=3,
			pDataFile="Input.txt"
		) (
	input i_Clk,
	input i_ClkEn,
	output reg oEoF,
	output reg [31:0] ov_FltID,
	output reg [pExpW+pManW:0] ov_FltOutA,
	output reg [pExpW+pManW:0] ov_FltOutB,
	output reg [pExpW+pManW:0] ov_FltOutC,
	output reg [pExpW+pManW:0] ov_FltOutD
);
	localparam pW = ((pManW%32)==0)?pManW/32:(pManW/32)+1;
	reg r_Sign;
	reg [pExpW-1:0] rv_Exp;
	reg [pManW-1:0] rv_Man;
	integer I;
	integer W;
	integer File;
	initial
		begin
			oEoF = 1'b0;
			$display("Opening file %s",pDataFile);
			File=$fopen(pDataFile,"r");			
		end
	
	always@(posedge i_Clk)
	begin
		if(i_ClkEn)
			begin
				if(!$feof(File)) 
					oEoF=1'b0;
				else
					oEoF=1'b1;
				case(pDataCol)
				1: $fscanf(File,"%x %x ",ov_FltID,ov_FltOutA);
				2: $fscanf(File,"%x %x %x",ov_FltID,ov_FltOutA,ov_FltOutB);
				3: $fscanf(File,"%x %x %x %x",ov_FltID,ov_FltOutA,ov_FltOutB,ov_FltOutC);
				4: $fscanf(File,"%x %x %x %x %x",ov_FltID,ov_FltOutA,ov_FltOutB,ov_FltOutC,ov_FltOutD);
				endcase
			end
	end	
	assign ov_FltOut = {r_Sign,rv_Exp,rv_Man};
endmodule