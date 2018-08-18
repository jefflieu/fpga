`timescale 1ns/100ps

module mFPAddSubVerifier;

parameter pPrecision=1;
parameter pManW = 23;
parameter pExpW = 8;
parameter pPipeline=8;

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
wire [3:0] w4_OutputID;
wire w_Uf, w_Of;
wire w_Inf,w_NaN;
reg rEOF;


	initial 
	begin
		r_Clk <= 1'b1;
		r_ARst <= 1'b1;
		r_GenEn <= 1'b0;
		rEOF <= 1'b0;
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
			
			//rv_FltC_D[0] <= wv_FltC;			
			for(I=1;I<10;I=I+1)
				rv_FltC_D[I]<=rv_FltC_D[I-1];
			ModelFloatAddSub(wv_FltA,wv_FltB,rv_FltC_D[0],wv_FltID[31]);
		end
	
	mFloatLoader #(.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),
			.pDataCol(3),
			.pDataFile("AddSub32Corner.txt")) u0FPGen
	(
	.i_Clk(r_Clk),
	.i_ClkEn(r_GenEn),
	.oEoF(w_EoF),
	.ov_FltID(wv_FltID),
	.ov_FltOutA(wv_FltA),
	.ov_FltOutB(wv_FltB),
	.ov_FltOutC());
			
	mFPAddSub #(.pTechnology("ALTERA"), 
			.pFamily("ARRIA II GX"),
			.pPrecision(pPrecision),
			.pWidthExp(pExpW),
			.pWidthMan(pManW),				
			.pPipelineBarrelShifter(1),
			.pPipelineNormalizer(2)
		) u0DUT (
	.iv_InputA	(wv_FltA),		//Input A following IEEE754 binary format of single or double precision
	.iv_InputB	(wv_FltB),		//Input B following IEEE754 binary format of single or double precision
	.o4_InputID	(),				//Input ID, only valid from 1 to 7, a 0 means Not valid input, to keep track of input and output
	.i_Dv(r_Dv),
	.i_SubNotAdd(wv_FltID[31]),
	.ov_Result		(wv_C),				//Product of A and B
	.o4_OutputID		(w4_OutputID),		//Output ID, to track which operation is valid at the output
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
			if(!rEOF) begin #1000; $stop; end
			$display("Zero  Count %d",u0DUT.ZeroCnt);
			$display("Oflow Count %d",u0DUT.OfCnt);
			$display("Uflow Count %d",u0DUT.UfCnt);
			for(I=0;I<10;I=I+1) 
				$display("Shift Count I %d ",u0DUT.ShiftCnt[I]);
			
			rEOF=1'b1;
			end
		if(w4_OutputID!=3'b000)
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


task ModelFloatAddSub;
		input [pManW+pExpW+1-1:0] inA;
		input [pManW+pExpW+1-1:0] inB;
		output [pManW+pExpW+1-1:0] ouC;
		input SubNotAdd;
		
		reg [1+(pManW+1+3)*2-1:0] rvSigniA;
		reg [1+(pManW+1+3)*2-1:0] LargerSigni;
		reg [1+(pManW+1+3)*2-1:0] rvSigniB;
		reg [1+(pManW+1+3)*2-1:0] SmallerSigni;
		reg [pExpW+1-1:0] rvExpA;
		reg [pExpW+1-1:0] rvExpB;
		reg [pExpW+1-1:0] rvExpDiff;
		reg rSignA, rSignB,rFinalSign;
		reg [1+(pManW+1+3)*2-1:0] Result;
		reg rOp;
		reg [pExpW+2-1:0] rvExpOut;
		
		begin
			rvExpA = {1'b0,inA[pManW+pExpW-1:pManW]};
			rvExpB = {1'b0,inB[pManW+pExpW-1:pManW]};
					
			rvSigniA = {1'b0,(rvExpA==0)?1'b0:1'b1,inA[pManW-1:0],3'b0,{(pManW+1+3){1'b0}}};
			rvSigniB = {1'b0,(rvExpB==0)?1'b0:1'b1,inB[pManW-1:0],3'b0,{(pManW+1+3){1'b0}}};
			rSignA = inA[pManW+pExpW+1-1];
			rSignB = inB[pManW+pExpW+1-1];
			#1;
			if(rvExpA>rvExpB) begin 
				rvExpDiff = rvExpA-rvExpB; 				
				LargerSigni = rvSigniA;
				SmallerSigni = rvSigniB;
				rFinalSign = rSignA;
				rOp = rFinalSign^(SubNotAdd^rSignB);
				rvExpOut = rvExpA;
				end
			else if(rvExpB>rvExpA) begin  
				rvExpOut = rvExpB;
				rvExpDiff = rvExpB-rvExpA; 
				LargerSigni = rvSigniB;
				SmallerSigni = rvSigniA;
				rSignB = rSignB^SubNotAdd;
				rFinalSign = rSignB;
				rOp = rFinalSign^rSignA;
				end
			else begin				
				rvExpOut = rvExpA;
				rvExpDiff = 0;
				rOp = rSignA^rSignB^SubNotAdd;
				if(rvSigniA>=rvSigniB) begin 
					LargerSigni = rvSigniA;
					SmallerSigni = rvSigniB;				
					rFinalSign=rSignA;
					end
				else begin
					LargerSigni = rvSigniB;
					SmallerSigni = rvSigniA;				
					rSignB = rSignB^SubNotAdd;
					rFinalSign=rSignB;
					end				
			end
			#1;
			SmallerSigni=(SmallerSigni>>rvExpDiff);
			rvExpOut = rvExpOut+1;
			if(rOp)
				Result = LargerSigni-SmallerSigni;
			else 
				Result = LargerSigni+SmallerSigni;
			#1
			if(Result!=0)
			while(!Result[(pManW+1+3)*2+1-1])
				begin
				Result = (Result<<1);
				rvExpOut=rvExpOut-1;
				end
			else 
				begin 
				rvExpOut = 0;
				rFinalSign = 0;
				end
			#1;
			if((&rvExpA[pExpW-1:0])||(&rvExpB[pExpW-1:0]))
				begin 
				ouC[pManW-1:0]=0;
				ouC[pManW+pExpW-1:pManW]={pExpW{1'b1}};
				ouC[pManW+pExpW+1-1]=0;
				end
			else begin 				
				ouC={9'h0,Result[(pManW+1+3)*2+1-2-:pManW]};
				if(Result[(pManW+1+3)*2+1-2-pManW]) 
					begin 
						if(|Result[(pManW+1+3)*2+1-2-pManW-1:0]) 
							ouC=ouC+1;
						else begin //Exactly Midway, round ties to zero
							if(Result[(pManW+1+3)*2+1-2-pManW+1]) ouC=ouC+1;
							end
						if(ouC[pManW])
							rvExpOut[pExpW-1:0]=rvExpOut[pExpW-1:0]+1;
					end
				if(rvExpOut[pExpW+1]||rvExpOut==0) begin //Underflow begin						
						ouC = 0;
					end				
				else if(rvExpOut[pExpW])//OverFlow
					begin
						ouC[pManW-1:0] = 0;
						ouC[pExpW+pManW-1:pManW] = 2**pExpW-1;
						ouC[pExpW+pManW+1-1] = rFinalSign;				
					end				
				else begin 			
					ouC[pManW+pExpW-1:pManW]=rvExpOut[pExpW-1:0];
					ouC[pManW+pExpW+1-1] = rFinalSign;
					end
				end
		end
	endtask
endmodule
