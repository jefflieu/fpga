/*
Author  : Jeff Lieu <lieumychuong@gmail.com>
File		:	Floating Point Adder/Subtractor
Description	:
	Parameters:
		pPrecision	: 0: custom. 1: single precision. 2: double precision
		pWidthExp	: No effect when pPrecision=1 or 2, else specify the width of Exponential Part of Float
		pWidthMan	: No effect when pPrecision=1 or 2, else specify the width of Mantissa Part of Float
		The size of The Floating point number = pWidthExp+pWidthMan+1
		pWidthExp and pWidthMan do not need to follow IEEE754 documents. i.e you can specify pWidthExp=8, pWidthMan=31 to have a 40 bit number
		pPipeline	: Minimum pipeline is 3
	
Remarks		:
		Double Precision and Custom Precision have not been tested
		Only single precision is tested
		Performance and Usage
		Device 			 	LUTs/ALUTs	Regsiter		SpeedGrade Max Freq
		Cyclone III 		
		Cyclone IV GX		
		Cyclone V GX
		Arria II GX

Revision	:
	Date		Author	Description
	24/09/12	JL		Add Round to nearest, ties to even mode

*/



module mFPAddSub #(parameter pTechnology="ALTERA", 
			pFamily="CYCLONE V",
			pPrecision=2,
			pWidthExp=11,
			pWidthMan=26,	
			pExpW = (pPrecision==1)?08:((pPrecision==2)?11:pWidthExp),
			pManW = (pPrecision==1)?23:((pPrecision==2)?52:pWidthMan),
			pPipelineBarrelShifter=2,
			pPipelineNormalizer =3,
			pPipeline=pPipelineNormalizer+pPipelineBarrelShifter+5
		)  (
	input 	[pExpW+pManW:0] iv_InputA,		//Input A following IEEE754 binary format of single or double precision
	input 	[pExpW+pManW:0] iv_InputB,		//Input B following IEEE754 binary format of single or double precision
	output	[3:0]		 	o4_InputID,		//Input ID, only valid from 1 to 7, a 0 means Not valid input, to keep track of input and output
	input	i_Dv,
	input	i_SubNotAdd,
	
	output 	[pExpW+pManW:0] ov_Result,	//Product of A and B
	output	[3:0]		 	o4_OutputID,		//Output ID, to track which operation is valid at the output
	output	o_Overflow,
	output	o_Underflow,
	output	o_NAN,
	output	o_PINF,
	output	o_NINF,
	
	input	i_ClkEn,
	input 	i_Clk,							//Clock	
	input	i_ARst						//Async reset
);
	localparam pSigExt = 2;
	localparam pSigniW 	= pManW+1;
	localparam pESigniW = 1+pSigniW+pSigExt;
	localparam pBias	= (2**(pExpW-1))-1;
	localparam pEINF	= 2**pExpW-1;
	localparam pDISWID	= pESigniW>128?8:(pESigniW>64?7:(pESigniW>32?6:(pESigniW>16?5:(pESigniW>8?4:(pESigniW>4?3:2)))));
	localparam st_NORM  = 3'b000;
	localparam st_ZERO	= 3'b001;
	localparam st_SUBN	= 3'b010;
	localparam st_INF	= 3'b011;
	localparam st_NAN	= 3'b100;
	
	
	wire w_SignA,w_SignB;
	
	reg 	r_SignA_D1;
	reg 	r_SignB_D1;
	wire 	w_Alarger;
	wire	w_Blarger;
	reg		r_ManALarger;
	
	
	wire 	[pSigniW-1:0] 	wv_SignificandA,wv_SignificandB;
	reg 	[pESigniW-1:0] 	rv_SignificandA_D,rv_SignificandB_D;
	wire 	[pESigniW-1:0] 	wv_LargerSigni;			//Before The BarrelShift
	wire 	[pESigniW-1:0] 	wv_SmallerSigni;		//Before The BarrelShift
	reg 	[pESigniW*2-1:0] 	rv_SmallerSigniPadded0;		//Before The BarrelShift
	wire 	[pESigniW*2-1:0] 	wv_ShiftedSignificandPadded0;		//Before The BarrelShift
	wire 	[pESigniW-1:0] 	wv_ShiftedSignificand;	//After the BarrelShift
	wire 	[pESigniW-1:0] 	wv_LargerSignificand;	//After The BarrelShift
	wire 	[pESigniW-1:0] 	wv_SigniDiffToLZD;
	reg 	[pESigniW-1:0] 	rv_SigniDiffToNorm;
	wire 	[pSigniW+1-1:0] 	wv_NormFactor;
	reg 	[pSigniW+1-1:0] 	rv_NormFactor;
	reg 	[pExpW-1:0] 	rv_Log2NormFactor[0:pPipelineNormalizer-1];
	
	wire	[pSigniW+1-1:0] 	wv_NormSignificand;	
	wire 	[(pSigniW+1)*2-1:0] wv_NormSigniWhole;
		
	wire 	[pExpW-1:0] wv_ExpA,wv_ExpB;			
	reg 	[pExpW+1:0] rv_DiffExpAB,rv_DiffExpBA;	
	wire 	[pExpW-1:0] wv_LargerExp,wv_SmallerExp;	//Before the shift regsiter
	reg 	[pExpW-1:0] rv_LargerExpSync3;			
	reg 	[pExpW-1:0] rv_LargerExpSync4;			
	reg 	[pExpW-1:0] rv_LargerExpSync5;			
	
	reg 	[pExpW-1:0] rv_ExpA_D,rv_ExpB_D;		
	wire	[pExpW-1:0] wv_ShiftRight;
	reg 	[pDISWID-1:0] rv_ShiftDist;
	reg 	[pExpW+1:0]	rv_ExpOut;
	reg 	[pExpW+1:0]	rv_ExpMinusNormFactor;
		
	wire 	[pESigniW-1:0] 	wv_Sum;
	wire 	[pESigniW-1:0] 	wv_Diff;
	reg 	[pESigniW-1:0] 	rv_Result;
	reg 	[pSigniW-1:0] 	rv_ResultOut;
	
	reg 	r_SignOut;
	
	wire 	[pESigniW+1-1:0]	wv_ShiftInU0;
	wire 	[pESigniW+1-1:0]	wv_ShiftOutU0;
	
	wire 	[pExpW+1-1:0]	wv_ShiftInU1;
	wire 	[pExpW+1-1:0]	wv_ShiftOutU1;
	
	
	reg 	[2:0] r3_StatA;
	reg 	[2:0] r3_StatB;
	wire 	[9:0] w10_StatIn;
	wire 	[9:0] w10_StatOut;
	wire 	[2:0] w3_StatAOut;
	wire 	[2:0] w3_StatBOut;
	
	reg 	rABUdflow;
	reg 	rABOvflow;
	reg		rABNaN;
	reg 	[3:0] r4_Id;
	reg 	[3:0] r4_IdIn;
	reg 	[3:0] r4_IdOut;
	reg		r_Op;
	wire 	w_SubNotAdd1;
	wire 	w_SubNotAdd2;
	wire 	w_FinalSign;
	reg		r_FinalSign3;
	reg		r_FinalSign4;
	reg		r_FinalSign5;	
	reg		r_SubNotAdd3;
	wire 	w_FinalSign2;
	reg 	[9:0]	r_ZeroResult;
	reg 	[pESigniW-1:0] wvDroppedBitMask;
	reg 	[pPipelineNormalizer:0] rSignShiftOut;
	reg 	[pPipelineNormalizer-1:0] rRndUpBit;
	reg 	[pPipelineNormalizer-1:0] rAllOnes;
	reg	[pExpW+1:0] rv_ExpAdj[0:pPipelineNormalizer-1];
	reg	[pExpW+1:0] rv_ExpP1;
	reg	[pExpW+1:0] rv_ExpP2;
	reg	[pExpW+1:0] rv_ExpM1;
	reg	[pExpW+1:0] rv_ExpP0;
	reg	[pManW-1:0] rv_ManOut[0:pPipelineNormalizer-1];
	reg 	[pPipelineNormalizer-1:0] rFromNormalizer;
	wire [pExpW+1:0] wv_ExpTmp;
	
	assign w_SignA 	= iv_InputA[pExpW+pManW];
	assign w_SignB 	= iv_InputB[pExpW+pManW];
	assign wv_SignificandA	= {(|wv_ExpA),iv_InputA[pManW-1:0]};//Leading may be 1 or 0 depending on the input
	assign wv_SignificandB	= {(|wv_ExpB),iv_InputB[pManW-1:0]};//Leading may be 1 or 0 depending on the input
	assign wv_ExpA 	= iv_InputA[pManW+pExpW-1:pManW];
	assign wv_ExpB 	= iv_InputB[pManW+pExpW-1:pManW];	
	
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst)
	begin
		rv_DiffExpAB <= {(pExpW+1){1'b0}};
		rv_DiffExpBA  <= {(pExpW+1){1'b0}};
		r4_Id	 <= 4'b0001;
		r_SignA_D1 <= 1'b0;
		r_SignB_D1 <= 1'b0;
		r3_StatA <= st_NORM;
		r3_StatB <= st_NORM;
		r4_IdIn <= 3'b000;
		r_ManALarger <= 1'b0;	
		rv_ExpA_D <= {pExpW{1'b0}};
		rv_ExpB_D <= {pExpW{1'b0}};
		rv_SignificandA_D <= {pESigniW{1'b0}};
		rv_SignificandB_D <= {pESigniW{1'b0}};
		r_SignA_D1 <= 1'b0;
		r_SignB_D1 <= 1'b0;
		r_Op <= 1'b0;
	end 
	else	
	if(i_ClkEn) begin 
		if(i_Dv) 
			r4_Id <= (r4_Id==4'b1111)?4'b0001:r4_Id+4'b0001;
		r4_IdIn	<= o4_InputID;
		
		//Calculate the Exponential
		r_ManALarger <= (wv_SignificandA>wv_SignificandB)?1'b1:1'b0;
						
		rv_DiffExpAB  	<= {2'b0,wv_ExpA}-{2'b0,wv_ExpB};
		rv_DiffExpBA  	<= {2'b0,wv_ExpB}-{2'b0,wv_ExpA};
			
		rv_ExpA_D 	<= wv_ExpA;
		rv_ExpB_D 	<= wv_ExpB;
		
		rv_SignificandA_D <= {1'b0,(|wv_ExpA)?wv_SignificandA:{pSigniW{1'b0}},2'b0};
		rv_SignificandB_D <= {1'b0,(|wv_ExpB)?wv_SignificandB:{pSigniW{1'b0}},2'b0};
				
		r_SignA_D1	<= w_SignA & (|iv_InputA[pManW+pExpW-1-:pExpW]); //Change the sign of A,B to Positive if it is ZERO
		r_SignB_D1	<= w_SignB & (|iv_InputB[pManW+pExpW-1-:pExpW]);		
		
		r_Op <= i_SubNotAdd;
				
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
	
	assign w_Alarger = (rv_DiffExpBA[pExpW+1])|(~rv_DiffExpAB[pExpW+1] & r_ManALarger);
	
	generate 
	if(pTechnology=="ALTERA") begin	
		assign w10_StatIn = {r4_IdIn,r3_StatA,r3_StatB};
		assign w3_StatAOut = w10_StatOut[5:3];
		assign w3_StatBOut = w10_StatOut[2:0];
		
		mShiftReg #(.pWidth(10),.pDistance(pPipeline-2)) u0StatusShift
		(
		.iv_In(w10_StatIn),
		.ov_Out(w10_StatOut),
		.i_Clk(i_Clk),
		.i_ARst(i_ARst),
		.i_ClkEn(i_ClkEn));
		
		//Memorize 1st Stage result w_Alarger,w_Blarger,w_FinalSign,w_SubNotAdd1,wv_LargerExp,wv_LargerSigni
		assign wv_ShiftInU0 = {w_SubNotAdd1,wv_LargerSigni};
		mShiftReg #(.pWidth(pESigniW+1),.pDistance(pPipelineBarrelShifter+1),.pUseReg(1)) u0SyncBarrelShift
		(
		.iv_In(wv_ShiftInU0),
		.ov_Out(wv_ShiftOutU0),
		.i_Clk(i_Clk),
		.i_ARst(i_ARst),
		.i_ClkEn(i_ClkEn));		
		
		assign wv_ShiftInU1 = {w_FinalSign,wv_LargerExp};
		mShiftReg #(.pWidth(pExpW+1),.pDistance(2+pPipelineBarrelShifter)) u1SyncExp
		(
		.iv_In(wv_ShiftInU1),
		.ov_Out(wv_ShiftOutU1),
		.i_Clk(i_Clk),
		.i_ARst(i_ARst),
		.i_ClkEn(i_ClkEn));	
		
		assign wv_LargerSigni 	= w_Alarger?rv_SignificandA_D:rv_SignificandB_D;		
		assign wv_SmallerSigni 	= w_Alarger?rv_SignificandB_D:rv_SignificandA_D;		
		assign wv_ShiftRight	= rv_DiffExpBA[pExpW+1]?rv_DiffExpAB[pExpW-1:0]:rv_DiffExpBA[pExpW-1:0];		
		assign wv_LargerExp	 	= w_Alarger?rv_ExpA_D:rv_ExpB_D;
		assign w_SubNotAdd1 	= (r_SignB_D1^r_Op^r_SignA_D1);
		assign w_FinalSign		= w_Alarger?r_SignA_D1:(r_SignB_D1^r_Op);
				
		assign wv_LargerSignificand = {wv_ShiftOutU0[pESigniW-1:0]};
		assign w_SubNotAdd2 = wv_ShiftOutU0[pESigniW];		
		
		
		
		//Second stage				
		always@(posedge i_Clk)
			if(i_ClkEn)
				begin
					rv_SmallerSigniPadded0 <= {wv_SmallerSigni,{pESigniW{1'b0}}};
					rv_ShiftDist <= (wv_ShiftRight>pESigniW)?(pESigniW):wv_ShiftRight[pDISWID-1:0];		
				end
		
		lpm_clshift	u0InShifter (
				.clock (i_Clk),
				.clken (i_ClkEn),
				.direction (1'b1),
				.distance (rv_ShiftDist[pDISWID-1:0]),
				.aclr (i_ARst),
				.data (rv_SmallerSigniPadded0),
				.overflow (),
				.result (wv_ShiftedSignificandPadded0),
				.underflow ());
		defparam
			u0InShifter.lpm_pipeline = pPipelineBarrelShifter,
			u0InShifter.lpm_shifttype = "LOGICAL",
			u0InShifter.lpm_type = "LPM_CLSHIFT",
			u0InShifter.lpm_width = pESigniW*2,
			u0InShifter.lpm_widthdist = pDISWID;
		assign wv_ShiftedSignificand = wv_ShiftedSignificandPadded0[pESigniW*2-1-:pESigniW];
		
		//synopsis translate_off
		//This is to verify the rounded value
		wire [pESigniW*2-1:0] wvFullDiff;
		assign wvFullDiff = {wv_LargerSignificand,{pESigniW{1'b0}}}-wv_ShiftedSignificandPadded0;
		//synopsis translate_on
		
		integer T;
		wire wDroppedBits;				
		assign wv_Sum = wv_LargerSignificand+{wv_ShiftedSignificand};
		//When taking a difference, most of the time, we lost some bits after shift, in that case because 
		//the LSBs of the larger Significand contain all zeros, we will lose 1 unit count in the difference		
		assign wv_Diff = wv_LargerSignificand-{wv_ShiftedSignificand};
		assign wDroppedBits = |wv_ShiftedSignificandPadded0[pESigniW-1:0];
		
		//Third Stage
		reg [3:0] rv4RndCode;
		always@(posedge i_Clk)
		if(i_ClkEn)
			begin
				if(w_SubNotAdd2)
					begin
						if(wv_Diff[pESigniW-1-:2]==2'b01)
							rv4RndCode <= (wv_Diff[1:0]==2'b10 & wDroppedBits)?4'b0001:{wDroppedBits,3'b000};
						else if(wv_Diff[pESigniW-1-:3]==3'b001)
							rv4RndCode <= (wv_Diff[0]==1'b1 & wDroppedBits)?4'b0010:{wDroppedBits,3'b000};						
						else 
							rv4RndCode <= {wDroppedBits,3'b000};
					end
				else 
					rv4RndCode <= {wDroppedBits,3'b000};
							
				if(w_SubNotAdd2)
					rv_Result <= wv_Diff;
				else 
					rv_Result <= wv_Sum;
				
			end
		
		assign wv_SigniDiffToLZD = rv_Result;		
		mLZD #(.pTechnology(pTechnology),.pWidth(pSigniW+1),.pFamily(pFamily)) u0LZD (
			.iv_In(wv_SigniDiffToLZD[pESigniW-3-:(pSigniW+1)]),
			.ov_Out(wv_NormFactor));
		integer I;
		
		//4th Stage Find the Leading One
		reg rDroppedBits;
		always@(posedge i_Clk or posedge i_ARst)
		if(i_ARst) begin
				rv_NormFactor <= 0;
				rv_SigniDiffToNorm <= 0;								
			end
		else if(i_ClkEn)
			begin
				rv_NormFactor <= wv_NormFactor;
				
				if(rv4RndCode==4'b0001)
					rv_SigniDiffToNorm <= {wv_SigniDiffToLZD[pESigniW-1:pSigExt],2'b01};
				else if(rv4RndCode==4'b0010) 
					rv_SigniDiffToNorm <= {wv_SigniDiffToLZD[pESigniW-1:pSigExt-1],1'b0};
				else
					rv_SigniDiffToNorm <= wv_SigniDiffToLZD;
				
				rDroppedBits <= rv4RndCode[3];
				
				for(I=0;I<pSigniW+1;I=I+1)
					if(rv_NormFactor[I]==1'b1) rv_Log2NormFactor[0] <= I;	
				r_ZeroResult[0] <= ~(|rv_SigniDiffToNorm);
				r_ZeroResult[9:1]<=r_ZeroResult[8:0];	
				rFromNormalizer<=1'b0;
				
				rv_ExpP1 <= {2'b00,wv_ShiftOutU1[pExpW-1:0]}+1;
				rv_ExpP2 <= {2'b00,wv_ShiftOutU1[pExpW-1:0]}+2;
				rv_ExpM1 <= {2'b00,wv_ShiftOutU1[pExpW-1:0]}-1;
				rv_ExpP0 <= {2'b00,wv_ShiftOutU1[pExpW-1:0]};
				
				if(rv_SigniDiffToNorm[pESigniW-1]) begin
					rRndUpBit[0] <= rv_SigniDiffToNorm[pSigExt]&((|rv_SigniDiffToNorm[pSigExt-1:0])|rDroppedBits|rv_SigniDiffToNorm[pSigExt+1]);
					rv_ManOut[0] <= rv_SigniDiffToNorm[pESigniW-2-:pManW];
						if(rv_SigniDiffToNorm[pSigExt] && (&rv_SigniDiffToNorm[pESigniW-2-:pManW]))							
							rv_ExpAdj[0] <=rv_ExpP2;
						else 
							rv_ExpAdj[0] <=rv_ExpP1;					
					end
				else if(rv_SigniDiffToNorm[pESigniW-1-:2]==2'b01) begin
					rRndUpBit[0] <= rv_SigniDiffToNorm[pSigExt-1]&(rv_SigniDiffToNorm[pSigExt-2]|rDroppedBits|rv_SigniDiffToNorm[pSigExt]);
					rv_ManOut[0] <= rv_SigniDiffToNorm[pESigniW-3-:pManW];
						if(rv_SigniDiffToNorm[pSigExt-1] && (&rv_SigniDiffToNorm[pESigniW-3-:pManW]))							
							rv_ExpAdj[0] <=rv_ExpP1;
						else 
							rv_ExpAdj[0] <=rv_ExpP0;										
					end
				else if(rv_SigniDiffToNorm[pESigniW-1-:3]==3'b001) begin
					rRndUpBit[0] <= rv_SigniDiffToNorm[pSigExt-2]&(rDroppedBits|rv_SigniDiffToNorm[pSigExt-1]);
					rv_ManOut[0] <= rv_SigniDiffToNorm[pESigniW-4-:pManW];
						if(rv_SigniDiffToNorm[pSigExt-2] && (&rv_SigniDiffToNorm[pESigniW-4-:pManW]))							
							rv_ExpAdj[0] <=rv_ExpP0;
						else 
							rv_ExpAdj[0]<=rv_ExpM1;	
					end
				else begin
					rRndUpBit[0] <= 1'b0;
					rv_ExpAdj[0] <=rv_ExpM1;
					rv_ManOut[0] <= 0;
					rFromNormalizer<=1'b1;
					end
				for(I=1;I<pPipelineNormalizer;I=I+1)
					begin
					rRndUpBit[I]<=rRndUpBit[I-1];
					rv_ManOut[I]<=rv_ManOut[I-1];
					rFromNormalizer[I]<=rFromNormalizer[I-1];
					rv_ExpAdj[I] <= rv_ExpAdj[I-1];
					rv_Log2NormFactor[I]<=rv_Log2NormFactor[I-1];
					end			
			end
		assign wv_NormSignificand=wv_NormSigniWhole[pSigniW+1-1:0];		
		
		always@(posedge i_Clk)
		if(i_ClkEn) 
			begin
				rSignShiftOut[0] <= wv_ShiftOutU1[pExpW];
				for(I=1;I<=(pPipelineNormalizer);I=I+1)
					rSignShiftOut[I] <= rSignShiftOut[I-1];
			end
		
		if(pFamily=="ARRIA II GX")
		begin
			wire 	[(pSigniW+1)*2-1:0] wv_Tmp1;
			reg 	[(pSigniW+1)*2-1:0] rv_Tmp2;
			lpm_mult	normalizer (
					.clock (i_Clk),
					.dataa (wv_SigniDiffToLZD[pESigniW-3-:(pSigniW+1)]),
					.datab (wv_NormFactor),
					.result (wv_Tmp1),
					.aclr (1'b0),
					.clken (i_ClkEn),
					.sum (1'b0));
			defparam
				normalizer.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
				normalizer.lpm_pipeline = pPipelineNormalizer,
				normalizer.lpm_representation = "UNSIGNED",
				normalizer.lpm_type = "LPM_MULT",
				normalizer.lpm_widtha = (pSigniW+1),
				normalizer.lpm_widthb = (pSigniW+1),
				//normalizer.intended_device_family = pFamily,
				normalizer.lpm_widthp = (pSigniW+1)*2;	
			always@(posedge i_Clk)
			if(i_ClkEn)
				rv_Tmp2 <= wv_Tmp1;
			assign wv_NormSigniWhole = rv_Tmp2;
		end
		else
		begin
			lpm_mult	normalizer (
					.clock (i_Clk),
					.dataa (rv_SigniDiffToNorm[pESigniW-3-:(pSigniW+1)]),
					.datab (rv_NormFactor),
					.result (wv_NormSigniWhole),
					.aclr (1'b0),
					.clken (i_ClkEn),
					.sum (1'b0));
			defparam
				normalizer.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
				normalizer.lpm_pipeline = pPipelineNormalizer,
				normalizer.lpm_representation = "UNSIGNED",
				normalizer.lpm_type = "LPM_MULT",
				normalizer.lpm_widtha = (pSigniW+1),
				normalizer.lpm_widthb = (pSigniW+1),
				//normalizer.intended_device_family = pFamily,
				normalizer.lpm_widthp = (pSigniW+1)*2;
		end
		
			
		


		assign wv_ExpTmp = rv_ExpAdj[pPipelineNormalizer-1]-{2'b00,rv_Log2NormFactor[pPipelineNormalizer-1]};	
		//Last Stage Calculate Outputs
		always@(posedge i_Clk or posedge i_ARst)
		if(i_ARst) 
		begin		
			rv_ResultOut<=0;
			rABUdflow 	<= 1'b0;
			rABOvflow 	<= 1'b0;
			rABNaN		<= 1'b0;
			rv_ExpOut	<= 0;
			r_SignOut	<= 1'b0;
			r4_IdOut	<= 4'b0;
		end else if(i_ClkEn)
		begin		
		
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
			
			if(r_ZeroResult[pPipelineNormalizer-1]) 
				rv_ExpOut <= 0;
			else 
				if(rFromNormalizer[pPipelineNormalizer-1])
					rv_ExpOut <= wv_ExpTmp;//rv_ExpAdj[pPipelineNormalizer-1]-{2'b00,rv_Log2NormFactor[pPipelineNormalizer-1]};			
				else 
					rv_ExpOut <= rv_ExpAdj[pPipelineNormalizer-1];
			
			if(rFromNormalizer[pPipelineNormalizer-1])
				rv_ResultOut <= wv_NormSignificand[pSigniW-1-:pManW];			
			else 
				rv_ResultOut <= rv_ManOut[pPipelineNormalizer-1]+rRndUpBit[pPipelineNormalizer-1];				
			
			r_SignOut = rSignShiftOut[pPipelineNormalizer] & (~r_ZeroResult[pPipelineNormalizer-1]);
			
			r4_IdOut  = w10_StatOut[9:6];
		end
			
	assign ov_Result 	= {r_SignOut,o_Underflow?{(pExpW){1'b0}}:(o_Overflow?{pExpW{1'b1}}:rv_ExpOut[pExpW-1:0]),(o_Underflow|o_Overflow)?{pManW{1'b0}}:rv_ResultOut[pManW-1:0]};
	assign o_Underflow 	= (rv_ExpOut[pExpW+1:0]=={(pExpW+2){1'b0}} && ~r_ZeroResult[pPipelineNormalizer]) | rv_ExpOut[pExpW+1] | rABUdflow;
	assign o_Overflow  	= rABOvflow | (rv_ExpOut[pExpW+1:0]=={2'b00,{(pExpW){1'b1}}}) | {rv_ExpOut[pExpW+1:pExpW]==2'b01};
	assign o4_InputID  	= i_Dv?r4_Id:3'b000;
	assign o4_OutputID  = r4_IdOut;
	assign o_NAN	   	= rABNaN;
	assign o_PINF  		= o_Overflow & (~r_SignOut);
	assign o_NINF  		= o_Overflow & (r_SignOut);
	end	//If(pTechnology=="ALTERA")
	endgenerate
	
	
	
	//synthesis_off
	//Manual Coverage
	integer ZeroCnt;
	integer OfCnt;
	integer UfCnt;
	integer ShiftCnt [0:9];
	integer I;
	always@(posedge i_Clk)
	if(i_ARst==1'b1)
		begin
			ZeroCnt=0;
			OfCnt=0;
			UfCnt=0;
			for(I=0;I<10;I=I+1)
				ShiftCnt[I]=0;
		end
	else if(i_ClkEn) 
		begin
			if((~o_Underflow) && (~o_Overflow) && (ov_Result==0)) ZeroCnt=ZeroCnt+1;
			if((o_Underflow) && (~o_Overflow) && (ov_Result==0)) UfCnt=UfCnt+1;
			if((~o_Underflow) && (o_Overflow)) OfCnt=OfCnt+1;
			if(rv_ShiftDist==0) ShiftCnt[0]=ShiftCnt[0]+1; else
			if(rv_ShiftDist==1) ShiftCnt[1]=ShiftCnt[1]+1; else
			if(rv_ShiftDist==2) ShiftCnt[2]=ShiftCnt[2]+1; else
			if(rv_ShiftDist>2&&rv_ShiftDist<pManW) ShiftCnt[3]=ShiftCnt[3]+1; else
			if(rv_ShiftDist>=pManW && rv_ShiftDist<=(pManW+2)) ShiftCnt[4]=ShiftCnt[4]+1; else
			ShiftCnt[5]=ShiftCnt[5]+1;			
		end	
	//synthesis_on

endmodule

module mBarrelRight #(parameter pWidth=23,pWDist=5,pPipeline=1)
(
	input [pWidth-1:0] iv_In,
	input [pWDist-1:0] iv_Dist,
	output [pWidth-1:0] ov_Out,
	input i_ClkEn,
	input i_Clk
);
	wire [pWidth*2-1:0] wv_Output;
	wire [pWidth-1:0] wvInput;
	wire [pWidth-1:0] wvMultilier;
	
	
	generate 
	genvar I;
		for(I=0;I<pWidth;I=I+1)
		begin:BitSwap
			assign wvInput[I]=iv_In[pWidth-1-I];
			assign ov_Out[I]=wv_Output[pWidth-1-I];
			assign wvMultilier[I] = (iv_Dist==I)?1'b1:1'b0;
		end			
	endgenerate
	
	
	lpm_mult	shiftleft (
				.clock (i_Clk),
				.dataa (wvInput),
				.datab (wvMultilier),
				.result (wv_Output),
				.aclr (1'b0),
				.clken (i_ClkEn),
				.sum (1'b0));
		defparam
			shiftleft.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
			shiftleft.lpm_pipeline = pPipeline,
			shiftleft.lpm_representation = "UNSIGNED",
			shiftleft.lpm_type = "LPM_MULT",
			shiftleft.lpm_widtha = pWidth,
			shiftleft.lpm_widthb = pWidth,
			shiftleft.lpm_widthp = pWidth*2;

endmodule

module mShiftReg #(parameter pTechnology="ALTERA",pFamily="CYCLONE V",pDistance=4,pWidth=32,pUseReg=0)(
	input [pWidth-1:0] iv_In,
	output [pWidth-1:0] ov_Out,
	input i_ClkEn,	
	input i_Clk,
	input i_ARst);
	
	reg [pWidth-1:0] rv_ShiftReg[0:pDistance-1]/* synthesis ramstyle = "MLAB" */;
	
	generate 
		if(pTechnology=="ALTERA") 
		begin
			if(pDistance>=3 && pUseReg==0) begin:alteralpm 
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
				if(i_ARst) begin 
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
endmodule

module mLZD #(parameter pTechnology="ALTERA",pFamily="CYCLONE V",pWidth=64) (
	input [pWidth-1:0] iv_In,
	output [pWidth-1:0] ov_Out);
	
	
	
	wire [pWidth-1:0] wv_InRev;
	wire [pWidth-1:0] wv_InRevN;
	wire [pWidth-1:0] wv_CarryOut;
	wire [pWidth-1:0] wv_CarryIn;
	wire [pWidth-1:0] wv_Out;
	generate 
	genvar I;
	if(pTechnology=="ALTERA") 
	begin
		for(I=0;I<pWidth;I=I+1)
		begin:genCarry
		assign wv_InRev[I]=iv_In[pWidth-1-I];
		assign wv_InRevN[I]=~wv_InRev[I];
			mCell uCell(
				.iCin(wv_CarryIn[I]),
				.iAin(wv_InRevN[I]),
				.iBin((I==0)?1'b1:1'b0),
				.oCout(wv_CarryOut[I]),
				.oSout(wv_Out[I]));
		assign ov_Out[I]=wv_Out[I]&wv_InRev[I];	
		end
		for(I=1;I<pWidth;I=I+1)
		begin:connect
			assign wv_CarryIn[I]=wv_CarryOut[I-1];
		end
	end
	endgenerate		
	assign wv_CarryIn[0]=1'b0;	
endmodule


module mCell (
	input iCin,
	input iAin,
	input iBin,
	output oCout,
	output oSout);
	
	wire sout,cout;
	assign sout = iCin^iAin^iBin;
	assign cout = (iCin&(iAin^iBin))|(iAin&iBin);	
	
	carry_sum carry(
		.sin(sout),
		.cin(cout),
		.sout(oSout),
		.cout(oCout));
	
endmodule

module mLOD6(input [5:0] i6_In,
	output reg [2:0] o3_Pos,
	output o_Found);//Not Found
	always@(*)
		case(i6_In)
		6'b1XXXXX: o3_Pos<=3'd0;		
		6'b01XXXX: o3_Pos<=3'd1;		
		6'b001XXX: o3_Pos<=3'd2;		
		6'b0001XX: o3_Pos<=3'd3;		
		6'b00001X: o3_Pos<=3'd4;		
		6'b000001: o3_Pos<=3'd5;		
		endcase	
	assign o_Found = (|i6_In);
endmodule
