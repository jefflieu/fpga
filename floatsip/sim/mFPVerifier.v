`timescale 1ns/100ps

module mFPVerifier;

parameter pPrecision=1;
parameter pManW = 23;
parameter pExpW = 8;
parameter pPipeline=8;

parameter pDouble1 		= 64'h3FF_0_0000_0000_0000;
parameter pDouble1p5 	= 64'h3FF_8_0000_0000_0000;
parameter pSingle1 		= 32'h3F80_0000;
parameter pSingle1p5	= 32'h3FC0_0000;
parameter pSingle2		= 32'h4000_0000;

reg 	[pExpW+pManW:0] rv_A;
reg 	[pExpW+pManW:0] rv_B;
wire 	[pExpW+pManW:0] wv_C;
wire	[31:0] wv_FltID;
wire 	[pExpW+pManW:0] wv_FltA;
wire 	[pExpW+pManW:0] wv_FltB;
wire 	[pExpW+pManW:0] wv_FltC;

reg [pExpW+pManW:0] rv_FltC_D[0:pPipeline-1];

reg r_Clk;
reg r_ARst;
reg r_Dv,r_GenEn;
wire [2:0] w3_OutputID;
wire w_Uf, w_Of;
wire w_Inf,w_NaN;

	initial 
	begin
		r_Clk <= 1'b1;
		r_ARst <= 1'b1;
		r_GenEn <= 1'b0;
		#100;
		r_ARst <= 1'b0;
		rv_A <= 0;
		rv_B <= 0;
		#1000;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b1;
	end

	always@(*)
		begin
		#5;
		r_Clk <= ~r_Clk;
		end
	integer I;
	
	always@(posedge r_Clk)
		begin
			r_Dv <= r_GenEn;
			rv_FltC_D[0] <= wv_FltC;
			for(I=1;I<10;I=I+1)
				rv_FltC_D[I]<=rv_FltC_D[I-1];
		end
	
	mFloatLoader #(.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),
			.pDataCol(3),
			.pDataFile("AddSub32DataCorner.txt")) u0FPGen
	(
	.i_Clk(r_Clk),
	.i_ClkEn(r_GenEn),
	.oEoF(w_EoF),
	.ov_FltID(wv_FltID),
	.ov_FltOutA(wv_FltA),
	.ov_FltOutB(wv_FltB),
	.ov_FltOutC(wv_FltC));
			
	/*mFPMult #(.pTechnology("ALTERA"), 
			.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),				
			.pPipeline(pPipeline)
		) u0DUT (
	.iv_InputA	(wv_FltA),		//Input A following IEEE754 binary format of single or double precision
	.iv_InputB	(wv_FltB),		//Input B following IEEE754 binary format of single or double precision
	.o3_InputID	(),				//Input ID, only valid from 1 to 7, a 0 means Not valid input, to keep track of input and output
	.i_Dv(r_Dv),
	.ov_Result		(wv_C),				//Product of A and B
	.o3_OuputID		(w3_OutputID),		//Output ID, to track which operation is valid at the output
	.o_Overflow		(w_Of),
	.o_Underflow	(w_Uf),
	.o_NAN			(),
	.o_PINF			(),
	.o_NINF			(),	
	.i_ClkEn		(1'b1),
	.i_Clk			(r_Clk),			//Clock	
	.i_ARst			(r_ARst)			//Async reset
);	*/
	mFPAddSub #(.pTechnology("ALTERA"), 
			.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),				
			.pPipelineBarrelShifter(1),
			.pPipelineNormalizer(2)
		) u0DUT (
	.iv_InputA	(wv_FltA),		//Input A following IEEE754 binary format of single or double precision
	.iv_InputB	(wv_FltB),		//Input B following IEEE754 binary format of single or double precision
	.o3_InputID	(),				//Input ID, only valid from 1 to 7, a 0 means Not valid input, to keep track of input and output
	.i_Dv(r_Dv),
	.i_SubNotAdd(wv_FltID[31]),
	.ov_Result		(wv_C),				//Product of A and B
	.o3_OuputID		(w3_OutputID),		//Output ID, to track which operation is valid at the output
	.o_Overflow		(w_Of),
	.o_Underflow	(w_Uf),
	.o_NAN			(),
	.o_PINF			(),
	.o_NINF			(),	
	.i_ClkEn		(1'b1),
	.i_Clk			(r_Clk),			//Clock	
	.i_ARst			(r_ARst)			//Async reset
	);

	//Checker
	assign w_Inf = (rv_FltC_D[pPipeline-1][pManW+pExpW-1:pManW]=={pExpW{1'b1}} && rv_FltC_D[pPipeline-1][pManW-1:0]=={pManW{1'b0}})?1'b1:1'b0;
	assign w_NaN = (rv_FltC_D[pPipeline-1][pManW+pExpW-1:pManW]=={pExpW{1'b1}} && rv_FltC_D[pPipeline-1][pManW-1:0]!={pManW{1'b0}})?1'b1:1'b0;
	always@(posedge r_Clk)
	begin
		if(w_EoF) 
			begin
			$display("End of data"); 
			$stop; 
			end
		if(w3_OutputID!=3'b000)
			begin
				if(w_Inf) 
				begin
					if(w_Of) 
						$display("PASSED");
					else 
						begin
							$display("INFINITY CHECK FAILED");	
							//$stop;		
						end
				end
				else if (w_NaN)
				begin
					if(w_NaN) 
							$display("PASSED");
					else 
						begin
							$display("NAN CHECK FAILED");	
							$stop;		
						end						
				end
				else				
				if(wv_C==rv_FltC_D[pPipeline-1]) $display("PASSED"); else 
					begin
						if((wv_C-rv_FltC_D[pPipeline-1])==1||(rv_FltC_D[pPipeline-1]-wv_C)==1)
							begin
							$display("WRN@%d: LSB not match",$time);
							$stop;
							end
						else if(wv_C[pExpW+pManW-1:0]==0 && rv_FltC_D[pPipeline-1][pExpW+pManW-1:0]==0)
							begin 
							$display("WRN@%d: Sign of Zero not match",$time);
							
							end
						else
							begin 
							$display("FAILED");	
							$stop;		
							end
					end
			end
	end

endmodule
