/*
Author  : Jeff Lieu <lieumychuong@gmail.com>
File		:	Floating Point Multipler
Description	:
	Parameters:
		pPrecision	: 0: custom. 1: single precision. 2: double precision
		pWidthExp	: No effect when pPrecision=1 or 2, else specify the width of Exponential Part of Float
		pWidthMan	: No effect when pPrecision=1 or 2, else specify the width of Mantissa Part of Float
		The size of The Floating point number = pWidthExp+pWidthMan+1
		pWidthExp and pWidthMan do not need to follow IEEE754 documents. i.e you can specify pWidthExp=8, pWidthMan=31 to have a 40 bit number
		pPipeline	: Minimum pipeline is 3
	
Remarks		:

Revision	:
	Date	Author	Description

*/



module mFPMult #(parameter pTechnology="ALTERA", 
			pFamily="Cyclone V",
			pPrecision=2,
			pWidthExp=11,
			pWidthMan=26,	
			pExpW = (pPrecision==1)?08:((pPrecision==2)?11:pWidthExp),
			pManW = (pPrecision==1)?23:((pPrecision==2)?52:pWidthMan),
			pPipeline =5
		)  (
	input 	[pExpW+pManW:0] iv_InputA,		//Input A following IEEE754 binary format of single or double precision
	input 	[pExpW+pManW:0] iv_InputB,		//Input B following IEEE754 binary format of single or double precision
	output	[2:0]		 	o3_InputID,		//Input ID, only valid from 1 to 7, a 0 means Not valid input, to keep track of input and output
	input	i_Dv,
	
	output 	[pExpW+pManW:0] ov_Result,	//Product of A and B
	output	[2:0]		 	o3_OuputID,		//Output ID, to track which operation is valid at the output
	output	o_Overflow,
	output	o_Underflow,
	output	o_NAN,
	output	o_PINF,
	output	o_NINF,
	
	input	i_ClkEn,
	input 	i_Clk,							//Clock	
	input	i_ARst						//Async reset
);
	localparam pSigniW 	= pManW+1;
	localparam pBias	= (2**(pExpW-1))-1;
	localparam pEINF	= 2**pExpW-1;
	localparam st_NORM  = 3'b000;
	localparam st_ZERO	= 3'b001;
	localparam st_SUBN	= 3'b010;
	localparam st_INF	= 3'b011;
	localparam st_NAN	= 3'b100;
	
	
	wire w_SignA,w_SignB;
	wire 	[pSigniW-1:0] wv_SignificandA,wv_SignificandB;
	wire 	[pSigniW+1:0] wv_ManProduct;
	wire 	[pSigniW+1:0] wv_ManProductRnd;
	wire 	[pExpW-1:0] wv_ExpA,wv_ExpB;	
	wire 	[pExpW+1:0] wv_ExpP;	
	reg 	[pExpW+1:0] rv_ExpAB,rv_ExpP;
	
	reg 	r_SignOut;
	reg 	[pExpW+1:0]	rv_ExpOut;
	reg 	[pSigniW:0] rv_SignificandOut;
	
	wire 	[pExpW+3:0]	wv_ShiftIn;
	wire 	[pExpW+3:0]	wv_ShiftOut;
	reg 	r_SignA_D1,r_SignA_D2;
	reg 	r_SignB_D1,r_SignB_D2;
	
	reg 	[2:0] r3_StatA/* synthesis ramstyle = "MLAB" */;
	reg 	[2:0] r3_StatB/* synthesis ramstyle = "MLAB" */;
	wire 	[8:0] w9_StatIn;
	wire 	[8:0] w9_StatOut;
	wire 	[2:0] w3_StatAOut;
	wire 	[2:0] w3_StatBOut;
	
	reg 	rABUdflow;
	reg 	rABOvflow;
	reg		rABNaN;
	reg 	[2:0] r3_Id;
	reg 	[2:0] r3_IdIn/* synthesis ramstyle = "MLAB" */;
	reg 	[2:0] r3_IdOut;
	
	wire [pSigniW*2-1:0] wv_FullProduct;
	wire wDroppedBits;
	reg [2:0] w3_StatA, w3_StatB;
	
	assign w_SignA 	= iv_InputA[pExpW+pManW];
	assign w_SignB 	= iv_InputB[pExpW+pManW];
	assign wv_SignificandA	= {1'b1,iv_InputA[pManW-1:0]};// Leading may be 1 or 1 depending on the input
	assign wv_SignificandB	= {1'b1,iv_InputB[pManW-1:0]};//
	assign wv_ExpA 	= iv_InputA[pManW+pExpW-1:pManW];
	assign wv_ExpB 	= iv_InputB[pManW+pExpW-1:pManW];
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
	begin
		rv_ExpAB <= {(pExpW+1){1'b0}};
		rv_ExpP  <= {(pExpW+1){1'b0}};
		r3_Id	 <= 3'b001;
		r_SignA_D1 <= 1'b0;
		r_SignB_D1 <= 1'b0;
		r_SignA_D2 <= 1'b0;
		r_SignB_D2 <= 1'b0;
		r3_StatA <= st_NORM;
		r3_StatB <= st_NORM;
		r3_IdIn <= 3'b000;
	end 
	else	
	 if(i_ClkEn) begin
		if(i_Dv) 
			r3_Id <= (r3_Id==3'b111)?3'b001:r3_Id+1;
		r3_IdIn	<= o3_InputID;
		
		//Calculate the Exponential
		rv_ExpAB 	<= {2'b0,wv_ExpA}+{2'b0,wv_ExpB};
		rv_ExpP  	<= rv_ExpAB-pBias;
		r_SignA_D1	<= w_SignA;		
		r_SignB_D1	<= w_SignB;	
		r_SignA_D2	<= r_SignA_D1;		
		r_SignB_D2	<= r_SignB_D1;	
		
		//Decoding the state		
		r3_StatA <= 3'b0;
		r3_StatB <= 3'b0;
		if((|iv_InputA[pExpW+pManW-1:0])==1'b0)
			r3_StatA <= st_ZERO;
		else if(wv_ExpA==0)
			r3_StatA <= st_SUBN;
		else if(wv_ExpA==pEINF && (|iv_InputA[pManW-1:0]))
			r3_StatA <= st_NAN;
		else if(wv_ExpA==pEINF && (~|iv_InputA[pManW-1:0]))
			r3_StatA <= st_INF;
				
		if((|iv_InputB[pExpW+pManW-1:0])==1'b0)
			r3_StatB <= st_ZERO;
		else if(wv_ExpB==0)
			r3_StatB <= st_SUBN;
		else if(wv_ExpB==pEINF && (|iv_InputB[pManW-1:0]))
			r3_StatB <= st_NAN;
		else if(wv_ExpB==pEINF && (~|iv_InputB[pManW-1:0]))
			r3_StatB <= st_INF;	
	end
	
	generate 
	if(pTechnology=="ALTERA") begin
		
		assign wv_ExpP  = wv_ShiftOut[pExpW+1:0];
		if(pPipeline>3)
		begin:SyncRvExp
		assign wv_ShiftIn = {r_SignB_D2,r_SignA_D2,rv_ExpP};
		mShiftReg	u0ExpShift (
				.i_Clk (i_Clk),
				.iv_In (wv_ShiftIn),
				.ov_Out(wv_ShiftOut),
				.i_ARst(i_ARst),
				.i_ClkEn (i_ClkEn));
		defparam
			u0ExpShift.pFamily = pFamily,
			u0ExpShift.pDistance =pPipeline-3,
			u0ExpShift.pWidth=pExpW+4;
		end 
		else 
		begin 			
			assign wv_ShiftOut = {r_SignB_D2,r_SignA_D2,rv_ExpP};
		end
		
		always@(*)
			begin 
				if((|iv_InputA[pExpW+pManW-1:0])==1'b0)
					w3_StatA <= st_ZERO;
				else if(wv_ExpA==0)
					w3_StatA <= st_SUBN;
				else if(wv_ExpA==pEINF && (|iv_InputA[pManW-1:0]))
					w3_StatA <= st_NAN;
				else if(wv_ExpA==pEINF && (~|iv_InputA[pManW-1:0]))
					w3_StatA <= st_INF;
				else 
					w3_StatA <= 0;
						
				if((|iv_InputB[pExpW+pManW-1:0])==1'b0)
					w3_StatB <= st_ZERO;
				else if(wv_ExpB==0)
					w3_StatB <= st_SUBN;
				else if(wv_ExpB==pEINF && (|iv_InputB[pManW-1:0]))
					w3_StatB <= st_NAN;
				else if(wv_ExpB==pEINF && (~|iv_InputB[pManW-1:0]))
					w3_StatB <= st_INF;	
				else 
					w3_StatB <= 0;
			
			end
		
		//assign w9_StatIn = {r3_IdIn,r3_StatA,r3_StatB};
		assign w9_StatIn = {o3_InputID,w3_StatA,w3_StatB};
		assign w3_StatAOut = w9_StatOut[5:3];
		assign w3_StatBOut = w9_StatOut[2:0];
		mShiftReg	u0StatusShift (
				.i_Clk (i_Clk),
				.iv_In (w9_StatIn),
				.ov_Out(w9_StatOut),
				.i_ARst(i_ARst),
				.i_ClkEn (i_ClkEn));
		defparam
			u0StatusShift.pFamily = pFamily,
			u0StatusShift.pDistance =pPipeline-1,
			u0StatusShift.pUseReg = 0,
			u0StatusShift.pWidth=9;
		
		
		if(pSigniW<=27 || pFamily!="Cyclone V") begin
		lpm_mult	lpm_mult_component (
				.clock (i_Clk),
				.dataa (wv_SignificandA),
				.datab (wv_SignificandB),
				.result (wv_FullProduct),
				.aclr (i_ARst),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			lpm_mult_component.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			lpm_mult_component.lpm_pipeline = pPipeline-1,
			lpm_mult_component.lpm_representation = "UNSIGNED",
			lpm_mult_component.lpm_type = "LPM_MULT",
			lpm_mult_component.lpm_widtha = pSigniW,
			lpm_mult_component.lpm_widthb = pSigniW,
			lpm_mult_component.lpm_widthp = pSigniW*2;
			assign wv_ManProduct = wv_FullProduct[pSigniW*2-1-:(pSigniW+2)];
			assign wDroppedBits = |wv_FullProduct[pSigniW-3:0];
		end
		else 
		begin
		mMultiplier u0Multiplier(
			.i_Clk(i_Clk),
			.i_ClkEn(i_ClkEn),
			.iv_A(wv_SignificandA),
			.iv_B(wv_SignificandB),
			.ov_P(wv_ManProduct),
			.o_Droppedbit(wDroppedBits));			
		defparam u0Multiplier.pPipeline = pPipeline-1,
				 u0Multiplier.pSigniW	= (pManW+1);
		end
		
		always@(posedge i_Clk or posedge i_ARst)
		if(i_ARst)
		begin
			rv_SignificandOut 	<= 0;
			rv_ExpOut 			<= 0;
			r_SignOut 			<= 0;
			rABUdflow			<= 1'b0;
			rABNaN				<= 1'b0;
			rABOvflow			<= 1'b1;
			r3_IdOut			<= 0;
		end else if(i_ClkEn)
		begin 
			//TODO HANDLE INFINITIVE CASE
			
			r_SignOut	<= wv_ShiftOut[pExpW+3]^wv_ShiftOut[pExpW+2];
			
			if(w3_StatAOut==st_SUBN||w3_StatBOut==st_SUBN)
				rABUdflow<=1'b1;
			else 
				rABUdflow<=1'b0;
				
			if(((w3_StatAOut==st_INF)&&(w3_StatBOut==st_NORM))||
					((w3_StatBOut==st_INF)&&(w3_StatAOut==st_NORM)))
				rABOvflow<=1'b1;
			else 
				rABOvflow<=1'b0;
			
			if(w3_StatAOut==st_NAN||w3_StatBOut==st_NAN||(w3_StatAOut==st_INF&&w3_StatBOut==st_ZERO)||(w3_StatAOut==st_ZERO&&w3_StatBOut==st_INF))
				rABNaN <= 1'b1;
			else 
				rABNaN <= 1'b0;
			
			if(w3_StatAOut==st_ZERO||w3_StatBOut==st_ZERO||w3_StatAOut==st_SUBN||w3_StatBOut==st_SUBN)
				begin
					rv_SignificandOut	<={1'b0,{(pSigniW-1){1'b0}}};
					rv_ExpOut			<={(pExpW+1){1'b0}};
				end			
			else			
				if(wv_ManProduct[pSigniW+1])//Have to shift to normalize
					begin
						if(&wv_ManProduct[pSigniW:1])
							begin
							rv_SignificandOut	<={1'b1,{(pSigniW-1){1'b0}}};
							rv_ExpOut			<=wv_ExpP+2;
							end
						else 
							begin
							//Round to the Nearest Even
							rv_SignificandOut<=(wv_ManProduct[1])?((wv_ManProduct[2]|wDroppedBits|wv_ManProduct[0])?wv_ManProduct[pSigniW+1:2]+1:wv_ManProduct[pSigniW+1:2]):wv_ManProduct[pSigniW+1:2];						
							rv_ExpOut		 <=wv_ExpP+1;
							end								
					end
				else
					begin
						if(&wv_ManProduct[pSigniW:0])
							begin
							rv_SignificandOut	<={1'b1,{(pSigniW-1){1'b0}}};
							rv_ExpOut			<=wv_ExpP+1;
							end
						else 
							begin
							//Round to the Nearest Even
							rv_SignificandOut<=(wv_ManProduct[0])?((wv_ManProduct[1]|wDroppedBits)?wv_ManProduct[pSigniW:1]+1:wv_ManProduct[pSigniW:1]):wv_ManProduct[pSigniW:1];						
							rv_ExpOut			<=wv_ExpP;
							end				
					end	
			r3_IdOut <= w9_StatOut[8:6];
		end	
	assign ov_Result = {r_SignOut,o_Underflow?{(pExpW){1'b0}}:(o_Overflow?{pExpW{1'b1}}:rv_ExpOut[pExpW-1:0]),(o_Underflow|o_Overflow)?{pManW{1'b0}}:rv_SignificandOut[pManW-1:0]};
	assign o_Underflow = rABUdflow | (rv_ExpOut[pExpW+1:0]=={(pExpW+2){1'b0}}) | rv_ExpOut[pExpW+1];
	assign o_Overflow  = rABOvflow | (rv_ExpOut[pExpW-1:0]=={2'b00,{(pExpW){1'b1}}}) | {rv_ExpOut[pExpW+1:pExpW]==2'b01};
	assign o3_InputID  = i_Dv?r3_Id:3'b000;
	assign o3_OuputID  = r3_IdOut;
	assign o_NAN	   = rABNaN;
	assign o_PINF  = o_Overflow & (~r_SignOut);
	assign o_NINF  = o_Overflow & (r_SignOut);
	end	//If(pTechnology=="ALTERA")
	endgenerate
	

endmodule

/* This Multiplier is specially designed for Floating point Application*/
module mMultiplier #(parameter pPipeline=3, pSigniW=52)(
	input i_Clk,
	input i_ClkEn,
	input i_ARst,
	input [pSigniW-1:0] iv_A,
	input [pSigniW-1:0] iv_B,
	output [pSigniW+2-1:0] ov_P,
	output o_Droppedbit);
	
	localparam pMultPipeline=(pPipeline>3)?pPipeline-3:pPipeline-2;
	localparam pAdder = (pPipeline>3)?1:0;
	localparam pTH = pSigniW>>1;
	localparam pBH = pSigniW-pTH;
	
	
	wire [2*pBH-1:0] wv_PLL;
	wire [pBH+pTH-1:0] wv_PLH,wv_PHL;
	wire [2*pTH-1:0] wv_PHH;	
	
	
	
	reg [2*pSigniW-1:0] rv_Ptmp;	
	reg [2*pSigniW-1:0] rv_P;
	reg [pBH+pTH+1-1:0] rv_Ptmp2;
	reg [pSigniW+2-1:0] rv_Ptmp4;
	reg [pSigniW-3+1:0] rv_Ptmp3;
	reg rDroppedbits;
		
	lpm_mult	multll (
				.clock (i_Clk),
				.dataa (iv_A[pBH-1:0]),
				.datab (iv_B[pBH-1:0]),
				.result (wv_PLL),
				.aclr (i_ARst),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			multll.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			multll.lpm_pipeline = pMultPipeline,
			multll.lpm_representation = "UNSIGNED",
			multll.lpm_type = "LPM_MULT",
			multll.lpm_widtha = pBH,
			multll.lpm_widthb = pBH,
			multll.lpm_widthp = 2*pBH;
			
	lpm_mult	multlh (
				.clock (i_Clk),
				.dataa (iv_A[pBH+pTH-1:pBH]),
				.datab (iv_B[pBH-1:0]),
				.result (wv_PLH),
				.aclr (i_ARst),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			multlh.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			multlh.lpm_pipeline = pMultPipeline,
			multlh.lpm_representation = "UNSIGNED",
			multlh.lpm_type = "LPM_MULT",
			multlh.lpm_widtha = pTH,
			multlh.lpm_widthb = pBH,
			multlh.lpm_widths = 1,
			multlh.lpm_widthp = pTH+pBH;
	
	lpm_mult	multhl (
				.clock (i_Clk),
				.dataa (iv_A[pBH-1:0]),
				.datab (iv_B[pBH+pTH-1:pBH]),
				.result (wv_PHL),
				.aclr (i_ARst),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			multhl.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			multhl.lpm_pipeline = pMultPipeline,
			multhl.lpm_representation = "UNSIGNED",
			multhl.lpm_type = "LPM_MULT",
			multhl.lpm_widtha = pBH,
			multhl.lpm_widthb = pTH,
			multhl.lpm_widths = 1,
			multhl.lpm_widthp = pBH+pTH;

	lpm_mult	multhh (
				.clock (i_Clk),
				.dataa (iv_A[pBH+pTH-1:pBH]),
				.datab (iv_B[pBH+pTH-1:pBH]),
				.result (wv_PHH),
				.aclr (i_ARst),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			multhh.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			multhh.lpm_pipeline = pMultPipeline,
			multhh.lpm_representation = "UNSIGNED",
			multhh.lpm_type = "LPM_MULT",
			multhh.lpm_widtha = pTH,
			multhh.lpm_widthb = pTH,
			multhh.lpm_widthp = 2*pTH;
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
		begin 
			rDroppedbits <= 1'b0;
			rv_Ptmp  <= 0;
			rv_Ptmp2  <= 0;
			rv_Ptmp3 <= 0;
			rv_Ptmp4 <= 0;
			rv_P <= 0;
		end 
	else 
		if(i_ClkEn) begin 
			//First Stage
			rv_Ptmp <= {wv_PHH,wv_PLL};			
			rv_Ptmp2 <= {1'b0,wv_PHL}+{1'b0,wv_PLH};
			
			
			
			if(pAdder) begin 
				//Second Stage
				rv_Ptmp3 <= {1'b0,rv_Ptmp[pSigniW-3:0]}+{1'b0,rv_Ptmp2[pTH-3:0],{pBH{1'b0}}};
				rv_Ptmp4 <= {rv_Ptmp[2*pSigniW-1-:(pSigniW+2)]}+{{(2*pSigniW-1-(pTH+pBH)+1){1'b0}},rv_Ptmp2[pTH+pBH+1-1:pTH-2]};
			
				//Third Stage
				rv_P[2*pSigniW-1-:(pSigniW+2)] <= rv_Ptmp3[pSigniW-2]?rv_Ptmp4+1:rv_Ptmp4;
				rDroppedbits <= |rv_Ptmp3[pSigniW-3:0];
				end
			else 
				//Only Second Stage
				rv_P <= rv_Ptmp+ {{{1'b0}},rv_Ptmp2,{pBH{1'b0}}};
			
		end
	assign ov_P = rv_P[2*pSigniW-1-:(pSigniW+2)];	
	assign o_Droppedbit = pAdder?rDroppedbits:(|rv_P[2*pSigniW-1-(pSigniW+2):0]);
	
		//synthesis_off
		wire [pSigniW*2-1:0] w1 = {{pTH-1{1'b0}},rv_Ptmp2,{pBH{1'b0}}};
		wire [pSigniW*2-1:0] w2 = w1+rv_Ptmp;		
		wire [pSigniW*2-1:0] w3 = iv_A*iv_B;
		//synthesis_on
	
endmodule

/*module mShiftReg #(parameter pTechnology="ALTERA",pFamily="CYCLONE V",pDistance=4,pWidth=32)(
	input [pWidth-1:0] iv_In,
	output [pWidth-1:0] ov_Out,
	input i_ClkEn,
	input i_ARst,
	input i_Clk);
	
	reg [pWidth-1:0] rv_ShiftReg[0:pDistance-1];
	
	generate 
		if(pTechnology=="ALTERA") 
		begin
			if(pDistance>=3) begin:alteralpm 
				altshift_taps	u0altlpm (
				.clock (i_Clk),
				.shiftin (iv_In),
				.shiftout(ov_Out),
				.taps (),								
				.aclr (i_ARst),
				.clken (i_ClkEn)				
				);
			defparam
			u0altlpm.intended_device_family = pFamily,
			u0altlpm.lpm_hint = "RAM_BLOCK_TYPE=MLAB",
			u0altlpm.lpm_type = "altshift_taps",
			u0altlpm.number_of_taps = 1,
			u0altlpm.tap_distance =pDistance,
			u0altlpm.width=pWidth;				
			end	
			else begin: hdlbeh
				integer I;
				always@(posedge i_Clk or posedge i_ARst)
				if(i_ARst)
					begin 
						for(I=0;I<pDistance;I=I+1)
							rv_ShiftReg[I]<=0;					
					end
				else if(i_ClkEn)
					begin
						for(I=1;I<pDistance;I=I+1)
							rv_ShiftReg[I]<=rv_ShiftReg[I-1];
						rv_ShiftReg[0]=iv_In;	
					end
				assign ov_Out = rv_ShiftReg[pDistance-1];		
			end		
		end	
	endgenerate
endmodule*/

