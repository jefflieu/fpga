
module quartus_logic_analyzer #(
  parameter DATA_IN_WIDTH = 8)
(
   
   input    [DATA_IN_WIDTH-1:0]     data_in,
   input                            clk_in,
   output                           trigger_out,
   output                           sampling_clk
);

  reg [15:0] sampling_clk_div;
  reg [15:0] sampling_period;
  reg storage_en;
  reg [DATA_IN_WIDTH-1:0] data_in_r;
  reg [DATA_IN_WIDTH-1:0] data_in_rr;
  
  /*
    Making a timer which period is controlled by the "sampling period" from the vio
    when Timer expires, we issue a sampling pulse which is the storage qualifier to the signal tap
  */
  always@(posedge clk_in)
  begin 
    storage_en <= 1'b0;
    sampling_clk_div <= sampling_clk_div + 1;
    if (sampling_clk_div == sampling_period) 
      begin 
        sampling_clk_div <= 16'h0;
        storage_en     <= 1'b1;
      end 
    
    /* 
      double clock data in to protect signal_tap system
    */    
    data_in_r  <= data_in;
    data_in_rr <= data_in_r;
    
  end 
  assign sampling_clk = storage_en;
  
  vio vio0 (
		.source     (sampling_period),  //    sources.source
		.probe      (1'b0),             //     probes.probe
		.source_clk (clk_in)   // source_clk.clk
	);

  
  signal_tap u0 (
		.acq_data_in    (data_in_rr),    //               tap.acq_data_in
		.acq_trigger_in (data_in_rr), //                  .acq_trigger_in
		.acq_clk        (clk_in),        //           acq_clk.clk
		.storage_enable (storage_en)  // storage_qualifier.storage_enable
	);


endmodule 
