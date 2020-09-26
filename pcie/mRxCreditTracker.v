/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	:

Remarks		:

Revision	:
	Date	Author	Description

*/

module mRxCreditTracker #(parameter pREQUESTOR_NUM=1,pCMPLHANDLER_NUM=1) (
	
	input 	[pREQUESTOR_NUM-1:0]	iv_MemRdReqSubmit,
	input 	[pREQUESTOR_NUM*8-1:0]	iv_MemRdReqCH,				//Note1		
	input 	[pREQUESTOR_NUM*12-1:0]	iv_MemRdReqCD,
	
	input 	[pCMPLHANDLER_NUM-1:0]		iv_MemRdCmplReceive,
	input 	[pCMPLHANDLER_NUM*8-1:0]	iv_MemRdCmplCH,			//Should be one
	input 	[pCMPLHANDLER_NUM*12-1:0]	iv_MemRdCmplCD,			
	
	
	input 	[7:0]	i8_TotalCredCH	,
	input 	[11:0]	i12_TotalCredCD	,
	
	output 	[7:0]	o8_AvailCredCH	, 	//Note2 
	output 	[11:0]	o12_AvailCredCD	,
		
	input 	i_Clk,
	input 	i_ARst
);
	//Note1: iv_MemRdReqCH: Completion Header Credit Required to complete the Request
	//Not the Credit of the Request itself
	//Same for Completion Data iv_MemRdReqCD
	//may not be one if the requestor thinks that the completor may split the completion
	
	
	//Note2: it takes 2 cycles to update the new Available Credit 
	//The Memory Requestor should not submit 2 consecutive requests
	
	//Rule at any one time, only 1 submitter or 1 completor is allowed to assert 
	//And the value must only be non-zero at the cycle of assert;	
	
	wire 	[7:0]	w8_RequiredCH;
	wire 	[11:0]	w12_RequiredCD;
	wire 	[7:0]	w8_ReceivedCH;
	wire 	[11:0]	w12_ReceivedCD;
		
	reg 	[7:0]	r8_AvailCredCH;
	reg 	[11:0]	r12_AvailCredCD;
	
	reg 	[7:0]	r8_NewCredCH;
	reg 	[11:0]	r12_NewCredCD;	

	reg 	r_Init;
	
	
	//This block converts all the Credits in input array into a Single Value
	//By or all the credits of all the Submiter/Receiver Together to Collapse into 1 value
	//Note that for this to work, only 1 submitter or Receiver is active at a time
	generate 
		genvar WHO,BIT;
		wire [pREQUESTOR_NUM-1:0] wv8_ReqCH[0:7];
		wire [pREQUESTOR_NUM-1:0] wv12_ReqCD[0:11];		
		wire [pCMPLHANDLER_NUM-1:0] wv8_RecvCH[0:7];
		wire [pCMPLHANDLER_NUM-1:0] wv12_RecvCD[0:11];	
		for(BIT=0;BIT<8;BIT=BIT+1)		
			begin:BIT8REQ 
				for(WHO=0;WHO<pREQUESTOR_NUM;WHO=WHO+1)
					begin:OringAllCredits
					assign wv8_ReqCH[BIT][WHO] = iv_MemRdReqCH[WHO*8+BIT-:1]&iv_MemRdReqSubmit[WHO];				
					end
			assign w8_RequiredCH[BIT]=|wv8_ReqCH[BIT];
			end
		
		for(BIT=0;BIT<12;BIT=BIT+1)		
			begin:BIT12REQ 
				for(WHO=0;WHO<pREQUESTOR_NUM;WHO=WHO+1)
					begin:OringAllCredits
					assign wv12_ReqCD[BIT][WHO] = iv_MemRdReqCD[WHO*12+BIT-:1]&iv_MemRdReqSubmit[WHO];	
					end
			assign w12_RequiredCD[BIT]=|wv12_ReqCD[BIT];
			end		
		
		for(BIT=0;BIT<8;BIT=BIT+1)		
			begin:BIT8RECV 
				for(WHO=0;WHO<pCMPLHANDLER_NUM;WHO=WHO+1)
					begin:OringAllCredits
					assign wv8_RecvCH[BIT][WHO] = iv_MemRdCmplCH[WHO*8+BIT-:1]&iv_MemRdCmplReceive[WHO];				
					end
			assign w8_ReceivedCH[BIT]=|wv8_RecvCH[BIT];
			end
		
		for(BIT=0;BIT<12;BIT=BIT+1)		
			begin:BIT12RECV
				for(WHO=0;WHO<pREQUESTOR_NUM;WHO=WHO+1)
					begin:OringAllCredits
					assign wv12_RecvCD[BIT][WHO] = iv_MemRdCmplCD[WHO*12+BIT-:1]&iv_MemRdCmplReceive[WHO];	
					end
			assign w12_ReceivedCD[BIT]=|wv12_RecvCD[BIT];
			end		
		
	endgenerate
		
	
	//Timing will be very tight at this point
	always@(posedge i_Clk or posedge i_ARst)
		if(i_ARst)
			begin 
				r8_AvailCredCH  <= 8'h0;
				r12_AvailCredCD <= 12'h0;
				r8_NewCredCH  	<= 8'h0;
				r12_NewCredCD	<= 12'h0;
				r_Init 			<= 1'b1;
			end
		else begin 		
		r_Init <= 1'b0;		
		if(r_Init)
			begin 
				r8_AvailCredCH  <= i8_TotalCredCH;
				r12_AvailCredCD <= i12_TotalCredCD;
				r8_NewCredCH	<= i8_TotalCredCH;
				r12_NewCredCD	<= i12_TotalCredCD;
			end
		else 
			begin 				
				//Handle Header Credit
				if((|iv_MemRdReqSubmit)&(~(|iv_MemRdCmplReceive)))			//One submit only
					r8_NewCredCH=r8_AvailCredCH-w8_RequiredCH;	
				else if((~(|iv_MemRdReqSubmit))&(|iv_MemRdCmplReceive))		//One receive only
					r8_NewCredCH=r8_AvailCredCH+w8_ReceivedCH;
				else if((|iv_MemRdReqSubmit)&(|iv_MemRdCmplReceive))		//Both
					r8_NewCredCH=(r8_AvailCredCH-w8_RequiredCH)+w8_ReceivedCH;			
						
				//Handle Data Credit
				if((|iv_MemRdReqSubmit)&(~(|iv_MemRdCmplReceive)))			//One submit only
					r12_NewCredCD=r12_AvailCredCD-w12_RequiredCD;	
				else if((~(|iv_MemRdReqSubmit))&(|iv_MemRdCmplReceive))		//One receive only
					r12_NewCredCD=r12_AvailCredCD+w12_ReceivedCD;
				else if((|iv_MemRdReqSubmit)&(|iv_MemRdCmplReceive))		//Both
					r12_NewCredCD=(r12_AvailCredCD-w12_RequiredCD)+w12_ReceivedCD;			
				
				//Need to check if it's larger than Total
				r8_AvailCredCH<=(r8_NewCredCH>i8_TotalCredCH)?i8_TotalCredCH:r8_NewCredCH;
				r12_AvailCredCD<=(r12_NewCredCD>i12_TotalCredCD)?i12_TotalCredCD:r12_NewCredCD;
				
				
			end
		end
	
	assign o8_AvailCredCH = r8_AvailCredCH;
	assign o12_AvailCredCD= r12_AvailCredCD;
	

	
	

endmodule 