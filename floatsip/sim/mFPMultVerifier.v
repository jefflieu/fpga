`timescale 1ns/100ps

module mFPMultVerifier;

parameter pPrecision=0;
parameter pManW = (pPrecision==2)?52:(pPrecision==1?23:10);
parameter pExpW = (pPrecision==2)?11:(pPrecision==1?8:5);
parameter pPipeline=5;
parameter pTestVector = (pPrecision==2)?"Mult64Data.txt":(pPrecision==1?"Mult32Data.txt":"Mult16Data.txt");

reg 	[pExpW+pManW:0] rv_A;
reg 	[pExpW+pManW:0] rv_B;
wire 	[pExpW+pManW:0] wv_C;
wire	[31:0] wv_FltID;
wire 	[pExpW+pManW:0] wv_FltA;
wire 	[pExpW+pManW:0] wv_FltB;
wire 	[pExpW+pManW:0] wv_FltC;

reg [pExpW+pManW:0] rv_FltC_D[0:pPipeline-1];
reg [pExpW+pManW:0] ref_data;

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
		#1000;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b0;
		#100;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b1;
		#10000;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b0;
		#1000;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b1;
		#100000;
		@(posedge r_Clk) #1;
		r_GenEn <= 1'b0;
		#10000;
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
			//ModelMultiplier(wv_FltA,wv_FltB,rv_FltC_D[0]);		
			ModelMultiplier(wv_FltA,wv_FltB,ref_data);		
		end
	
	mFloatLoader #(.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),
			.pDataCol(3),
			.pDataFile(pTestVector)) u0FPGen
	(
	.i_Clk(r_Clk),
	.i_ClkEn(r_GenEn),
	.oEoF(w_EoF),
	.ov_FltID(wv_FltID),
	.ov_FltOutA(wv_FltA),
	.ov_FltOutB(wv_FltB),
	.ov_FltOutC(wv_FltC));
			
	mFPMult #(.pTechnology("ALTERA"), 
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
							$stop;		
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
	
	task ModelMultiplier;
		input [pManW+pExpW+1-1:0] inA;
		input [pManW+pExpW+1-1:0] inB;
		output [pManW+pExpW+1-1:0] ouC;
	
	reg [1+pManW-1:0] rvSigniA;
	reg [1+pManW-1:0] rvSigniB;
	reg [pExpW+2-1:0] rvExpA;
	reg [pExpW+2-1:0] rvExpB;	
	reg rSignA, rSignB,rFinalSign;
	reg [1+pManW-1:0] rvSigniP;
	reg rOp;
	reg [pExpW+2-1:0] rvExpOut;	
	reg [(1+pManW)*2-1:0] rvProd;
	
	begin
			rvExpA = {2'b0,inA[pManW+pExpW-1:pManW]};
			rvExpB = {2'b0,inB[pManW+pExpW-1:pManW]};
					
			rvSigniA = (rvExpA==0)?0:{1'b1,inA[pManW-1:0]};
			rvSigniB = (rvExpB==0)?0:{1'b1,inB[pManW-1:0]};
			rSignA = inA[pManW+pExpW+1-1];
			rSignB = inB[pManW+pExpW+1-1]; 
	
			#1; 
			rvProd = rvSigniA*rvSigniB;
			
			if(rvExpA==0||rvExpB==0)
				rvExpOut = 0;
			else if(rvExpA==(2**pExpW-1)||rvExpB==(2**pExpW-1))
				rvExpOut = (2**pExpW-1);
			else 
				begin 
				rvExpOut = rvExpA+rvExpB-(2**(pExpW-1)-1);
				#1;
				if(rvProd[(1+pManW)*2-1]) //Most MSB = 1
					begin 
						rvSigniP = 	rvProd[(1+pManW)*2-1-:(pManW+1)];
						//Round to the nearest ties to even
						if(rvProd[(1+pManW)*2-1-(pManW+1)] & (rvProd[(1+pManW)*2-1-(pManW+1)+1]|(|rvProd[(1+pManW)*2-1-(pManW+1)-1:0]))) 
							begin 
							#1; 
							rvSigniP = rvSigniP+1;
							end
						rvExpOut = rvExpOut+1;
					end
				else 
					begin 
						rvSigniP = 	rvProd[(1+pManW)*2-2-:(pManW+1)];
						//Round to the nearest ties to even
						if(rvProd[(1+pManW)*2-2-(pManW+1)] & (rvProd[(1+pManW)*2-2-(pManW+1)+1]|(|rvProd[(1+pManW)*2-2-(pManW+1)-1:0]))) 
							begin 
							#1; 
							rvSigniP = rvSigniP+1;
							end					
					end
				end
			#1;
			ouC[pManW+pExpW+1-1] = rSignA^rSignB;
			if(rvExpOut[pExpW+1]||rvExpOut==0)//Underflow
				ouC[pManW+pExpW-1:0] = 0;
			else if(rvExpOut[pExpW]||rvExpOut==(2**pExpW-1)) //Overflow 
				begin 
				ouC[pManW-1:0] = 0;
				ouC[pManW+pExpW-1:pManW] = 2**pExpW-1;
				end
			else begin 
				ouC[pManW-1:0] = rvSigniP[pManW-1:0];
				ouC[pManW+pExpW-1:pManW] = rvExpOut[pExpW-1:0];
				end 	
	end
	endtask

endmodule
