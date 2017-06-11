`timescale 1ns/100ps
module mCrc32_256Tb;

	reg r_Clk, r_SoP, r_EoP, r_Dv, r_Clr;
	reg [255:0] r256_Data;
	wire [31:0] w32_Crc;
	reg [4:0] r5_SEmpty,r5_EEmpty;
	reg [8*2000-1:0] r_TestVector;
	reg [31:0] r32_RefCrc;
		
	integer Length, Offset;
	integer I;
	
	function [31:0] mCrcCal;
		input [8*2000-1:0] iv_Data;	
		
		reg [31:0] Poly;
		reg [31:0] Crc;
		reg Inbit;
		integer I;
		
		begin 
			Poly = 32'h04C1_1DB7;
			Crc = 32'h0;
			for(I=8*2000-1;I>=-32;I=I-1)
				begin 
					Inbit = (I>=0)?iv_Data[I]:1'b0;
					Crc = (Crc[31]==1'b0)?{Crc[30:0],Inbit}:({Crc[30:0],Inbit}^Poly);				
				end	
			mCrcCal = Crc;
		end
	endfunction 
	
	mCrc32_256 dut(
	.iv_Input	(r256_Data),
	.i_SoP		(r_SoP),
	.i_EoP		(r_EoP),
	.i_Dv		(r_Dv),
	.i_Clr		(r_Clr),
	.i_Clk		(r_Clk),	
	.i5_SoPEmpty	(r5_SEmpty),
	.i5_EoPEmpty	(r5_EEmpty),
	.o_CrcV		(w_CrcValid),
	.o32_Crc	(w32_Crc));
	
	initial 
		forever
			begin 
			r_Clk <= 1'b1;
			#5;
			r_Clk <= 1'b0;
			#5;
			end
	
	initial
	begin 
		//Clear the CRC
		r_Clr = 1'b1;			
		@(posedge r_Clk);
		r_Clr = 1'b0;		
		//////////////////////////////////
		// repeat 1 million test
		//////////////////////////////////
		repeat(1_000_000)
		begin 				
			//Generate a random size
			Length = $random%1518;
			if(Length<0) Length=-Length;
			//Generate random offset 
			Length = Length+64;
			Offset = $random%32;
			$display("Length %d, Offset %d",Length,Offset);
			if(Offset<0) Offset=-Offset;			
			
			//Generate data
			r_TestVector = 0;			
			repeat(Length)
				begin 
					r_TestVector = {r_TestVector[8*2000-8-1:0],8'h0};
					r_TestVector[7:0] = $random&8'hFF;
				end			
						
			//Using length as the index to the data array
			Length = Length+Offset;
			@(posedge r_Clk);#1;
			r_Dv = 1'b1;
			r_SoP = 1'b1;
			while(Length>0) 
			begin 
				
				//Generate End of Packet
				if(Length<=32) r_EoP = 1'b1; else r_EoP = 1'b0;
				//Calculate the Empty Bytes for the first word
				if(r_SoP) r5_SEmpty = Offset;
				//Calculate the Empty Bytes for the last word
				if(Length<32) r5_EEmpty = 32-Length; else r5_EEmpty=0;

				//Put data from array to 256 bit 
				//Octet 0, 1, 2 ...
				if((Length)>=32) 
					r256_Data = r_TestVector[Length*8-1-:256];
				else 
					//Last word, put byte by byte
					begin 
					I=0;
					while(I<Length)
						begin 
							r256_Data[(32-I)*8-1-:8] = r_TestVector[(Length-I)*8-1-:8];
							I=I+1;
						end 					
					end		
				
				//Recalculate length				
				@(posedge r_Clk);					
				Length = Length - 32;
				r_SoP=1'b0;				
			end
			r_SoP = 1'b0;
			r_Dv = 1'b0;
			r_EoP = 1'b0;
			//Calculate reference CRC 
			
		end
		
		$display("Finished");
		$finish;
	end
	always@(posedge r_Clk)
	begin 		
		if(r_Dv)
			$display("%x",r256_Data);
		if(w_CrcValid)
			if(r32_RefCrc==w32_Crc) $display("Passed"); 
			else 
				begin 
				$display("Failed");
				$display("Test: %x",r_TestVector);
				$stop; 
				end
			
	end
	
	always@(negedge r_Clk)
		if(r_Dv & r_EoP) r32_RefCrc = mCrcCal(r_TestVector);
	
	
endmodule
