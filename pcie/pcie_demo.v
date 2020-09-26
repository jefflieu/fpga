

module mPcieGen2By4Demo(
	input i_PcieRefClk,
	input i_PcieRst_L,
	input [3:0] i4_Rx,
	output[3:0] o4_Tx,
	input i_Clk125M);




	 pcie_de_gen2_x4_ast128 u0DesignExample(
		.dut_refclk_clk			(i_PcieRefClk),                //     dut_refclk.clk
		.dut_hip_ctrl_test_in	(32'h0),          //   dut_hip_ctrl.test_in
		.dut_hip_ctrl_simu_mode_pipe(1'b0),   //               .simu_mode_pipe
		.dut_npor_npor			(i_PcieRst_L),                 //       dut_npor.npor
		.dut_npor_pin_perst		(i_PcieRst_L),            //               .pin_perst
		.reset_reset_n			(i_PcieRst_L),                 //          reset.reset_n
		.clk_clk				(i_Clk125M),
		.dut_hip_serial_rx_in0	(i4_Rx[0]),         // dut_hip_serial.rx_in0
		.dut_hip_serial_rx_in1	(i4_Rx[1]),         //               .rx_in1
		.dut_hip_serial_rx_in2	(i4_Rx[2]),         //               .rx_in2
		.dut_hip_serial_rx_in3	(i4_Rx[3]),         //               .rx_in3
		.dut_hip_serial_tx_out0	(o4_Tx[0]),        //               .tx_out0
		.dut_hip_serial_tx_out1	(o4_Tx[1]),        //               .tx_out1
		.dut_hip_serial_tx_out2	(o4_Tx[2]),        //               .tx_out2
		.dut_hip_serial_tx_out3	(o4_Tx[3]));            


endmodule

module mPcieGen1By4Demo(
	input i_PcieRefClk,
	input i_PcieRst_L,
	input [3:0] i4_Rx,
	output[3:0] o4_Tx,
	input i_Clk125M);




	 pcie_de_gen1_x4_ast64 u0DesignExample(
		.dut_refclk_clk			(i_PcieRefClk),                //     dut_refclk.clk
		.dut_hip_ctrl_test_in	(32'h0),          //   dut_hip_ctrl.test_in
		.dut_hip_ctrl_simu_mode_pipe(1'b0),   //               .simu_mode_pipe
		.dut_npor_npor			(i_PcieRst_L),                 //       dut_npor.npor
		.dut_npor_pin_perst		(i_PcieRst_L),            //               .pin_perst
		.reset_reset_n			(i_PcieRst_L),                 //          reset.reset_n
		.clk_clk				(i_Clk125M),
		.dut_hip_serial_rx_in0	(i4_Rx[0]),         // dut_hip_serial.rx_in0
		.dut_hip_serial_rx_in1	(i4_Rx[1]),         //               .rx_in1
		.dut_hip_serial_rx_in2	(i4_Rx[2]),         //               .rx_in2
		.dut_hip_serial_rx_in3	(i4_Rx[3]),         //               .rx_in3
		.dut_hip_serial_tx_out0	(o4_Tx[0]),        //               .tx_out0
		.dut_hip_serial_tx_out1	(o4_Tx[1]),        //               .tx_out1
		.dut_hip_serial_tx_out2	(o4_Tx[2]),        //               .tx_out2
		.dut_hip_serial_tx_out3	(o4_Tx[3]));            


endmodule