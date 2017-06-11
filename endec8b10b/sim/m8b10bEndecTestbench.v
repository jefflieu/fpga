


`timescale 1ns/10ps

module m8b10bEndecTestbench;
`include "Veritil.v"

wire w_Clk;
reg	[7:0] r8_DataIn;
reg r_Kin;
wire [9:0] w10_DataOut;	
reg r_ARst_L;
wire w_Rd;
wire 	[7:0] w8_DecDataOut;
wire 	w_Kout;
reg 	r_ForceParity,r_Disparity;
wire 	w_Err;

	mClkGen u0ClkGen(w_Clk);
	
	mEnc8b10bMem	u0Enc8b10bMem(
	.i8_Din		(r8_DataIn),
	.i_Kin		(r_Kin),
	.i_ForceDisparity	(r_ForceParity),
	.i_Disparity		(r_Disparity),		//1 positive, 0 is negative
	.o10_Dout			(w10_DataOut),
	.o_Rd				(w_Rd),	
	.o_KErr				(w_KErr),
	.i_Clk				(w_Clk),
	.i_ARst_L			(r_ARst_L));
	
	mDec8b10bMem	u0Dec8b10bMem(
	.o8_Dout	(w8_DecDataOut),		//HGFEDCBA
	.o_Kout		(w_Kout),
	.o_DErr		(w_Err),
	.o_KErr		(),
	.o_DpErr	(),
	.i_ForceDisparity	(1'b0),
	.i_Disparity		(1'b0),		//1 Is negative, 0 is positive	
	.i10_Din	(w10_DataOut),	//abcdeifghj
	.o_Rd		(),	
	.i_Clk		(w_Clk),
	.i_ARst_L	(r_ARst_L));
	
	initial 	
		begin
			r_ARst_L = 1'b0;
			r_Kin = 1'b0;
			r_ForceParity = 1'b0;
			r_Disparity	= 1'b0;
			#100;
			r_ARst_L = 1'b1;
			r8_DataIn = 0;
			
			//Normal Test no K
			$display("Normal data test, no K");
			repeat(256)
				begin 					
					@(posedge w_Clk);				
					r8_DataIn = r8_DataIn +1;
				end
			#10000;
			
			//Normal Test with K
			$display("Normal data test, with valid K");
			repeat(100)
			repeat(256)
				begin 					
					@(posedge w_Clk);				
					r8_DataIn = r8_DataIn +1;
					if(r8_DataIn==8'h1C||r8_DataIn==8'h3C||r8_DataIn==8'h5C||r8_DataIn==8'h7C||
							r8_DataIn==8'h9C||r8_DataIn==8'hBC||r8_DataIn==8'hDC||r8_DataIn==8'hFC||
							r8_DataIn==8'hF7||r8_DataIn==8'hFB||r8_DataIn==8'hFD||r8_DataIn==8'hFE) 
						r_Kin=$random; else r_Kin=1'b0;
				end
		
			//Force Parity Error
			$display("Inject Parity Error");
			repeat(256)
				begin 					
					@(posedge w_Clk);				
					r8_DataIn = r8_DataIn +1;
					if(r8_DataIn==8'h1C||r8_DataIn==8'h3C||r8_DataIn==8'h5C||r8_DataIn==8'h7C||
							r8_DataIn==8'h9C||r8_DataIn==8'hBC||r8_DataIn==8'hDC||r8_DataIn==8'hFC||
							r8_DataIn==8'hF7||r8_DataIn==8'hFB||r8_DataIn==8'hFD||r8_DataIn==8'hFE) 
						r_Kin=$random; else r_Kin=1'b0;
					if(($random&32'h3F)==0)
						begin
						r_Disparity = ~w_Rd;
						r_ForceParity = 1'b1;						
						end
						else 
							r_ForceParity = 1'b0;						
				end
			r_ForceParity = 1'b0;							
			#10000;
			$display("Inject K Error");
			repeat(100)
				repeat(256)
					begin 					
						@(posedge w_Clk);				
						r8_DataIn = r8_DataIn +1;
						if(r8_DataIn==8'h1C||r8_DataIn==8'h3C||r8_DataIn==8'h5C||r8_DataIn==8'h7C||
								r8_DataIn==8'h9C||r8_DataIn==8'hBC||r8_DataIn==8'hDC||r8_DataIn==8'hFC||
								r8_DataIn==8'hF7||r8_DataIn==8'hFB||r8_DataIn==8'hFD||r8_DataIn==8'hFE||
								r8_DataIn==8'h17||r8_DataIn==8'h1B||r8_DataIn==8'h1D||r8_DataIn==8'h1E)//Invalid Ks 
							r_Kin=$random; else r_Kin=1'b0;
					end
			
			#10000;
			$display("Totally Random Test");			
				repeat(25600000)
					begin 					
						@(posedge w_Clk);				
						r8_DataIn = $random&8'hFF;
						if(r8_DataIn==8'h1C||r8_DataIn==8'h3C||r8_DataIn==8'h5C||r8_DataIn==8'h7C||
								r8_DataIn==8'h9C||r8_DataIn==8'hBC||r8_DataIn==8'hDC||r8_DataIn==8'hFC||
								r8_DataIn==8'hF7||r8_DataIn==8'hFB||r8_DataIn==8'hFD||r8_DataIn==8'hFE||
								r8_DataIn==8'h17||r8_DataIn==8'h1B||r8_DataIn==8'h1D||r8_DataIn==8'h1E)//Invalid Ks 
							r_Kin=$random; else r_Kin=1'b0;
						if(($random&32'h3F)==0)
						begin
						r_Disparity = ~w_Rd;
						r_ForceParity = 1'b1;						
						end
						else 
							r_ForceParity = 1'b0;		
					end
			
			$display("Done");
			$stop;		
		end
		
	//Checker
	reg [7:0] r8_D[7:0];
	reg [7:0] r_K;
	reg [7:0] r_KEncErr;
	reg [7:0] r_DecErr;
		
	always@(posedge w_Clk)
		if(~w_Err)
		begin 
			r8_D[0] <= r8_DataIn;
			r8_D[1] <= r8_D[0];
			r_K[0] <= r_Kin;
			r_K[1] <= r_K[0];
			r_KEncErr[0] <= w_KErr;
			`CheckW(w8_DecDataOut,r8_D[1],"Data Out Mismatch")
			if(~r_KEncErr[0]) `CheckW(w_Kout,r_K[1],"Data Out Mismatch")
		end

endmodule


module mClkGen #(parameter pClkPeriod=10) (output reg o_Clk);

	initial 
		forever
			begin 
				o_Clk = 1'b0;
				#pClkPeriod;
				o_Clk = 1'b1;
				#pClkPeriod;
			end

endmodule
