/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	: Used to track credit consumed

Remarks		:

Revision	:
	Date	Author	Description

*/

module mTxCreditTracker(
	
	input i_HipCons1PH,	
	input i_HipCons1CH,	
	input i_HipCons1NH,	
	
	input i_HipCons1PD,	
	input i_HipCons1CD,	
	input i_HipCons1ND,	
	
	input i_AppConsXPH,	
	input i_AppConsXCH,	
	input i_AppConsXNH,	
	
	input i_AppConsXPD,	
	input i_AppConsXCD,	
	input i_AppConsXND,	
	
	input 	[07:0]	i8_CredPH,
	input 	[07:0]	i8_CredCH,
	input 	[07:0]	i8_CredNH,
	
	input 	[11:0]	i12_CredPD,
	input 	[11:0]	i12_CredCD,
	input 	[11:0]	i12_CredND,
	
	output reg [7:0] o8_CredPH,		//Posted Header
	output reg [7:0] o8_CredCH,		//Completion Header
	output reg [7:0] o8_CredNH,		//Non Posted Header
	
	output reg [11:0] o12_CredPD,	//Posted Data
	output reg [11:0] o12_CredCD,	//Completion Data
	output reg [11:0] o12_CredND,	//Nonposted Ddata
	
	input i_Clk,
	input i_ARst,
	input i_SClr);

	reg r_DeferIncPH,r_DeferIncPD;
	reg r_DeferIncNH,r_DeferIncND;
	reg r_DeferIncCH,r_DeferIncCD;
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst) begin 
		o8_CredPH <= 8'h0;
		o8_CredCH <= 8'h0;
		o8_CredNH <= 8'h0;
		o12_CredPD <= 12'h0;
		o12_CredCD <= 12'h0;
		o12_CredND <= 12'h0;		
		end
	else 
		if(i_SClr) begin 
				o8_CredPH <= 8'h0;
				o8_CredCH <= 8'h0;
				o8_CredNH <= 8'h0;
				o12_CredPD <= 12'h0;
				o12_CredCD <= 12'h0;
				o12_CredND <= 12'h0;	
			end 
		else begin 
			
			r_DeferIncPH <= i_AppConsXPH & i_HipCons1PH;
			if(i_AppConsXPH) o8_CredPH <= o8_CredPH+i8_CredPH; 
			else if(i_HipCons1PH|r_DeferIncPH) o8_CredPH <= o8_CredPH+8'h1;
			
			
			r_DeferIncNH <= i_AppConsXNH & i_HipCons1NH;
			if(i_AppConsXNH) o8_CredNH <= o8_CredNH+i8_CredNH; 
			else if(i_HipCons1NH|r_DeferIncNH ) o8_CredNH <= o8_CredNH+8'h1;
			
			r_DeferIncCH <= i_AppConsXCH & i_HipCons1CH;
			if(i_AppConsXCH) o8_CredCH <= o8_CredCH+i8_CredCH; 
			else if(i_HipCons1CH|r_DeferIncCH ) o8_CredCH <= o8_CredCH+8'h1;
			
			r_DeferIncPD <= i_AppConsXPD & i_HipCons1PD;			
			if(i_AppConsXPD) o12_CredPD <= o12_CredPD+i12_CredPD; 
			else if(i_HipCons1PD|r_DeferIncPD) o12_CredPD <= o12_CredPD+12'h1;
			
			r_DeferIncND <= i_AppConsXND & i_HipCons1ND;						
			if(i_AppConsXND) o12_CredND <= o12_CredND+i12_CredND; 
			else if(i_HipCons1ND|r_DeferIncND) o12_CredND <= o12_CredND+12'h1;
			
			r_DeferIncCD <= i_AppConsXCD & i_HipCons1CD;						
			if(i_AppConsXCD) o12_CredCD <= o12_CredCD+i12_CredCD; 
			else if(i_HipCons1CD|r_DeferIncCD) o12_CredCD <= o12_CredCD+12'h1;
			
		
		end		
	

endmodule 

/*
module mConsCredTracker	(
	input i_CredConsPH,	
	input i_CredConsCH,	
	input i_CredConsNH,	
	
	input i_CredConsPD,	
	input i_CredConsCD,	
	input i_CredConsND,	
	
	output reg [7:0] o8_CredPH,		//Posted Header
	output reg [7:0] o8_CredCH,		//Completion Header
	output reg [7:0] o8_CredNH,		//Non Posted Header
	
	output reg [11:0] o12_CredPD,	//Posted Data
	output reg [11:0] o12_CredCD,	//Completion Data
	output reg [11:0] o12_CredND,	//Nonposted Ddata
	
	input i_Clk,
	input i_ARst,
	input i_SClr);
	
	always@(posedge i_Clk or posedge i_ARst)
	if(i_ARst) begin 
		o8_CredPH <= 8'h0;
		o8_CredCH <= 8'h0;
		o8_CredNH <= 8'h0;
		o12_CredPD <= 12'h0;
		o12_CredCD <= 12'h0;
		o12_CredND <= 12'h0;		
		end
	else 
		if(i_SClr) begin 
				o8_CredPH <= 8'h0;
				o8_CredCH <= 8'h0;
				o8_CredNH <= 8'h0;
				o12_CredPD <= 12'h0;
				o12_CredCD <= 12'h0;
				o12_CredND <= 12'h0;	
			end 
		else begin 
			if(i_CredConsPH) o8_CredPH <= o8_CredPH+8'h1;
			if(i_CredConsCH) o8_CredCH <= o8_CredCH+8'h1;
			if(i_CredConsNH) o8_CredNH <= o8_CredNH+8'h1;
			
			if(i_CredConsPD) o12_CredPD <= o12_CredPD+8'h1;
			if(i_CredConsCD) o12_CredCD <= o12_CredCD+8'h1;
			if(i_CredConsND) o12_CredND <= o12_CredND+8'h1;		
		end		
endmodule */