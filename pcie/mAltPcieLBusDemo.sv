/*
Copyright � 2013 lieumychuong@gmail.com

File		:
Description	:

Remarks		:

Disclaimer	: This source code has been provided to you, either by free download or paid purchase, has been 
tested to certain extent that the owner thinks it's sufficiently suitable for normal use. The owner does not 
guarantee in any way and will not be responsible for any kind of damage that may be caused by the codes.

Revision	:
	Date	Author	Description

*/


module mAltPcieLBusDemo #(parameter pSIM=0)(

	//synthesis translate_off 
		input  [31:0]		test_in,
		input  wire			simu_mode_pipe,
		input  wire         sim_pipe_pclk_in,   //           hip_pipe.sim_pipe_pclk_in
		output wire [1:0]   sim_pipe_rate,      //                   .sim_pipe_rate
		output wire [4:0]   sim_ltssmstate,     //                   .sim_ltssmstate
		output wire [2:0]   eidleinfersel0,     //                   .eidleinfersel0
		output wire [2:0]   eidleinfersel1,     //                   .eidleinfersel1
		output wire [2:0]   eidleinfersel2,     //                   .eidleinfersel2
		output wire [2:0]   eidleinfersel3,     //                   .eidleinfersel3
		output wire [1:0]   powerdown0,         //                   .powerdown0
		output wire [1:0]   powerdown1,         //                   .powerdown1
		output wire [1:0]   powerdown2,         //                   .powerdown2
		output wire [1:0]   powerdown3,         //                   .powerdown3
		output wire         rxpolarity0,        //                   .rxpolarity0
		output wire         rxpolarity1,        //                   .rxpolarity1
		output wire         rxpolarity2,        //                   .rxpolarity2
		output wire         rxpolarity3,        //                   .rxpolarity3
		output wire         txcompl0,           //                   .txcompl0
		output wire         txcompl1,           //                   .txcompl1
		output wire         txcompl2,           //                   .txcompl2
		output wire         txcompl3,           //                   .txcompl3
		output wire [7:0]   txdata0,            //                   .txdata0
		output wire [7:0]   txdata1,            //                   .txdata1
		output wire [7:0]   txdata2,            //                   .txdata2
		output wire [7:0]   txdata3,            //                   .txdata3
		output wire         txdatak0,           //                   .txdatak0
		output wire         txdatak1,           //                   .txdatak1
		output wire         txdatak2,           //                   .txdatak2
		output wire         txdatak3,           //                   .txdatak3
		output wire         txdetectrx0,        //                   .txdetectrx0
		output wire         txdetectrx1,        //                   .txdetectrx1
		output wire         txdetectrx2,        //                   .txdetectrx2
		output wire         txdetectrx3,        //                   .txdetectrx3
		output wire         txelecidle0,        //                   .txelecidle0
		output wire         txelecidle1,        //                   .txelecidle1
		output wire         txelecidle2,        //                   .txelecidle2
		output wire         txelecidle3,        //                   .txelecidle3
		output wire         txswing0,           //                   .txswing0
		output wire         txswing1,           //                   .txswing1
		output wire         txswing2,           //                   .txswing2
		output wire         txswing3,           //                   .txswing3
		output wire [2:0]   txmargin0,          //                   .txmargin0
		output wire [2:0]   txmargin1,          //                   .txmargin1
		output wire [2:0]   txmargin2,          //                   .txmargin2
		output wire [2:0]   txmargin3,          //                   .txmargin3
		output wire         txdeemph0,          //                   .txdeemph0
		output wire         txdeemph1,          //                   .txdeemph1
		output wire         txdeemph2,          //                   .txdeemph2
		output wire         txdeemph3,          //                   .txdeemph3
		input  wire         phystatus0,         //                   .phystatus0
		input  wire         phystatus1,         //                   .phystatus1
		input  wire         phystatus2,         //                   .phystatus2
		input  wire         phystatus3,         //                   .phystatus3
		input  wire [7:0]   rxdata0,            //                   .rxdata0
		input  wire [7:0]   rxdata1,            //                   .rxdata1
		input  wire [7:0]   rxdata2,            //                   .rxdata2
		input  wire [7:0]   rxdata3,            //                   .rxdata3
		input  wire         rxdatak0,           //                   .rxdatak0
		input  wire         rxdatak1,           //                   .rxdatak1
		input  wire         rxdatak2,           //                   .rxdatak2
		input  wire         rxdatak3,           //                   .rxdatak3
		input  wire         rxelecidle0,        //                   .rxelecidle0
		input  wire         rxelecidle1,        //                   .rxelecidle1
		input  wire         rxelecidle2,        //                   .rxelecidle2
		input  wire         rxelecidle3,        //                   .rxelecidle3
		input  wire [2:0]   rxstatus0,          //                   .rxstatus0
		input  wire [2:0]   rxstatus1,          //                   .rxstatus1
		input  wire [2:0]   rxstatus2,          //                   .rxstatus2
		input  wire [2:0]   rxstatus3,          //                   .rxstatus3
		input  wire         rxvalid0,           //                   .rxvalid0
		input  wire         rxvalid1,           //                   .rxvalid1
		input  wire         rxvalid2,           //                   .rxvalid2
		input  wire         rxvalid3,           //                   .rxvalid3
	//synthesis translate_on


	input i_PcieRefClk,
	input i_PcieRst_L,
	input [3:0] i4_Rx,
	output[3:0] o4_Tx,
	input i_Clk125M);

	
	localparam pRECONF_CHANNEL_NUM = 5;/*This value will change with number of Lanes*/
	localparam pRECONF_TO_XCVR_W = pRECONF_CHANNEL_NUM*70;
	localparam pRECONF_FR_XCVR_W = pRECONF_CHANNEL_NUM*46;
	
	if_AvalonStream_t	#(.pWIDTH(64))	if_RxStream();
	if_AvalonStream_t	#(.pWIDTH(64))	if_RxBuffOut();
	if_AvalonStream_t	#(.pWIDTH(64))	if_TxStream();
	if_AvalonBus_t		#(.pDWIDTH(32),.pAWIDTH(7))	if_ReconfMgmt();
	if_WishboneBus_t	#(.pDWIDTH(32),.pAWIDTH(12))if_LBusRegBank();
	
	wire 	[7:0]	w8_RxBarHit;
	wire 	w_TxFifoEmpty;
	wire 	[11:0]	w12_TxCredND,w12_TxCredPD,w12_TxCredCD;
	wire 	[07:0]	w8_TxCredNH,w8_TxCredPH,w8_TxCredCH;
	wire 	[5:0]	w6_InfiCred,w6_ConsCred;
	wire 	[11:0]	w12_TxCredConsND,w12_TxCredConsPD,w12_TxCredConsCD;
	wire 	[07:0]	w8_TxCredConsNH,w8_TxCredConsPH,w8_TxCredConsCH;

	wire w_HipResetStatus,w_HipSrdsPllLocked,w_AppClk,w_AppReset,w_AppReset_L;
	wire [127:0]	w128_ErrDesc;
	wire [6:0]	w7_CplErrIn,w7_CplErrOut;
	wire [31:0]	w32_LMIADataIn,w32_LMIDataOut;
	wire [11:0] w12_LMIAddr;
	wire w_LMIAck,w_LMIRead,w_LMIWrite,w_CplErrLMIBusy;
	
	wire 	[pRECONF_TO_XCVR_W-1:0] wv_ReconfToXcvr;
	wire 	[pRECONF_FR_XCVR_W-1:0] wv_ReconfFrXcvr;
	
	wire 	[4:0]	w5_MsiNum;
	wire 	w_MsiReq,w_MsiAck;
	wire 	[2:0]	w3_MsiTc;
	wire 	[0:0]	w_MsiStsVec;
	wire 	[4:0]	w5_TLHotPlugCtrller;
	wire 	w_TLCfgCtrl,w_TLCfgCtrlWr,w_TLCfgStatusWr;
	wire 	w_CplPending,w_DErrCorExtRcv,w_DErrCorExtRpl,w_DErrRpl,w_DlupExit;
	wire	[4:0]	w5_LTSSM;
	wire 	w_Ev128ns,w_Ev1us,w_HotRstExit,w_L2Exit;
	wire 	[3:0]	w4_IntStatus,w4_LaneActive;
	wire 	[11:0]	w12_K0CplSpcData;
	wire 	[07:0]	w8_K0CplSpcHeader;
	wire 	[01:0]	w2_DLCurrentSpd;
	
	wire 	[31:0]	w32_TLCfgCtrl;	
	wire 	[6:0]	w7_TLCfgAddress;
	wire 	[52:0]	w53_TLCfgStatus;	
	wire 	[12:0]	w13_Cfg_BusDev;
	wire 	w_ReconfClk,w_ReconfClkLock;
	
	wire 	[31:0]	w32_LMIDataIn;
	wire 	w_PMAuxPwr,w_PMEToCR,w_PMEToSR,w_PMEvent;
	wire 	[9:0]	w10_PMData;
	wire 	w_DataLinkUpExit,w_ReconfBusy;
	
	/* PLL Core */
	mAltPll uReconfigClk (
	.refclk		(i_Clk125M		),//  refclk.clk
	.rst		(1'b0			),//   reset.reset
	.outclk_0	(w_ReconfClk	), // outclk0.clk
	.locked    	(w_ReconfClkLock)//  locked.export
	);
	
	/* Instantiate PCIe Core */
	mAltPcie	uPcieHIP(
	.npor			(i_PcieRst_L	),//               npor.npor
	.pin_perst		(i_PcieRst_L	),//                   .pin_perst
	.test_in		(pSIM?test_in:32'h0		 ),//           hip_ctrl.test_in
	.simu_mode_pipe	(pSIM?simu_mode_pipe:1'b0),//                   .simu_mode_pipe
	.pld_clk		(w_AppClk		),//            pld_clk.clk
	.coreclkout		(w_AppClk		),//     coreclkout_hip.clk
	.refclk			(i_PcieRefClk	),//             refclk.clk
	.rx_in0			(i4_Rx[0]		),//         hip_serial.rx_in0
	.rx_in1			(i4_Rx[1]		),//                   .rx_in1
	.rx_in2			(i4_Rx[2]		),//                   .rx_in2
	.rx_in3			(i4_Rx[3]		),//                   .rx_in3
	.tx_out0		(o4_Tx[0]		),//                   .tx_out0
	.tx_out1		(o4_Tx[1]		),//                   .tx_out1
	.tx_out2		(o4_Tx[2]		),//                   .tx_out2
	.tx_out3		(o4_Tx[3]		),//                   .tx_out3
	
	.rx_st_valid	(if_RxStream.w_Valid	),//              rx_st.valid
	.rx_st_sop		(if_RxStream.w_Sop		),//                   .startofpacket
	.rx_st_eop		(if_RxStream.w_Eop		),//                   .endofpacket
	//.rx_st_empty	(if_RxStream.w_Empty	),//                   .empty
	.rx_st_ready	(if_RxStream.w_Ready	),//                   .ready
	.rx_st_err		(if_RxStream.w_Error	),//                   .error
	.rx_st_data		(if_RxStream.wv_Data	),//                   .data
	
	.rx_st_bar		(w8_RxBarHit			),//          rx_bar_be.rx_st_bar
	.rx_st_mask		(1'b0					),//                   .rx_st_mask
	
	.tx_st_valid	(if_TxStream.w_Valid	),//              tx_st.valid
	.tx_st_sop      (if_TxStream.w_Sop		),//                   .startofpacket
	.tx_st_eop      (if_TxStream.w_Eop		),//                   .endofpacket
	//.tx_st_empty    (if_TxStream.w_Empty	),//                   .empty
	.tx_st_ready    (if_TxStream.w_Ready	),//                   .ready
	.tx_st_err	    (if_TxStream.w_Error	),//                   .error
	.tx_st_data	    (if_TxStream.wv_Data	),//                   .data
	.tx_fifo_empty	(w_TxFifoEmpty			),//            tx_fifo.fifo_empty
		
	
	/*	Credit Stuff */
	.tx_cred_datafccp	(w12_TxCredCD		),//            tx_cred.tx_cred_datafccp
	.tx_cred_datafcnp	(w12_TxCredND		),//                   .tx_cred_datafcnp
	.tx_cred_datafcp	(w12_TxCredPD		),//                   .tx_cred_datafcp
	.tx_cred_fchipcons	(w6_ConsCred		),//                   .tx_cred_fchipcons
	.tx_cred_fcinfinite	(w6_InfiCred		),//                   .tx_cred_fcinfinite
	.tx_cred_hdrfccp	(w8_TxCredCH		),//                   .tx_cred_hdrfccp
	.tx_cred_hdrfcnp	(w8_TxCredNH		),//                   .tx_cred_hdrfcnp
	.tx_cred_hdrfcp		(w8_TxCredPH		),//                   .tx_cred_hdrfcp
	.ko_cpl_spc_header	(w8_K0CplSpcHeader	),//                   .ko_cpl_spc_header
	.ko_cpl_spc_data	(w12_K0CplSpcData	),//                   .ko_cpl_spc_data	
	
	/*
		PIPE Interface for simulation
	*/
	//synthesis translate_off
	.sim_pipe_pclk_in	(sim_pipe_pclk_in	),   
	.sim_pipe_rate		(sim_pipe_rate		),      
	.sim_ltssmstate		(sim_ltssmstate		),     
	.eidleinfersel0		(eidleinfersel0		),     
	.eidleinfersel1		(eidleinfersel1		),     
	.eidleinfersel2		(eidleinfersel2		),     
	.eidleinfersel3		(eidleinfersel3		),     
	.powerdown0			(powerdown0			),         
	.powerdown1			(powerdown1			),         
	.powerdown2			(powerdown2			),         
	.powerdown3			(powerdown3			),         
	.rxpolarity0		(rxpolarity0		),        
	.rxpolarity1		(rxpolarity1		),        
	.rxpolarity2		(rxpolarity2		),        
	.rxpolarity3		(rxpolarity3		),        
	.txcompl0			(txcompl0			),           
	.txcompl1			(txcompl1			),           
	.txcompl2			(txcompl2			),           
	.txcompl3			(txcompl3			),           
	.txdata0			(txdata0			),            
	.txdata1			(txdata1			),            
	.txdata2			(txdata2			),            
	.txdata3			(txdata3			),            
	.txdatak0			(txdatak0			),           
	.txdatak1			(txdatak1			),           
	.txdatak2			(txdatak2			),           
	.txdatak3			(txdatak3			),           
	.txdetectrx0		(txdetectrx0		),        
	.txdetectrx1		(txdetectrx1		),        
	.txdetectrx2		(txdetectrx2		),        
	.txdetectrx3		(txdetectrx3		),        
	.txelecidle0		(txelecidle0		),        
	.txelecidle1		(txelecidle1		),        
	.txelecidle2		(txelecidle2		),        
	.txelecidle3		(txelecidle3		),        
	.txswing0			(txswing0			),           
	.txswing1			(txswing1			),           
	.txswing2			(txswing2			),           
	.txswing3			(txswing3			),           
	.txmargin0			(txmargin0			),          
	.txmargin1			(txmargin1			),          
	.txmargin2			(txmargin2			),          
	.txmargin3			(txmargin3			),          
	.txdeemph0			(txdeemph0			),          
	.txdeemph1			(txdeemph1			),          
	.txdeemph2			(txdeemph2			),          
	.txdeemph3			(txdeemph3			),          
	.phystatus0			(phystatus0			),         
	.phystatus1			(phystatus1			),         
	.phystatus2			(phystatus2			),         
	.phystatus3			(phystatus3			),         
	.rxdata0			(rxdata0			),            
	.rxdata1			(rxdata1			),            
	.rxdata2			(rxdata2			),            
	.rxdata3			(rxdata3			),            
	.rxdatak0			(rxdatak0			),           
	.rxdatak1			(rxdatak1			),           
	.rxdatak2			(rxdatak2			),           
	.rxdatak3			(rxdatak3			),           
	.rxelecidle0		(rxelecidle0		),        
	.rxelecidle1		(rxelecidle1		),        
	.rxelecidle2		(rxelecidle2		),        
	.rxelecidle3		(rxelecidle3		),        
	.rxstatus0			(rxstatus0			),          
	.rxstatus1			(rxstatus1			),          
	.rxstatus2			(rxstatus2			),          
	.rxstatus3			(rxstatus3			),          
	.rxvalid0			(rxvalid0			),           
	.rxvalid1			(rxvalid1			),           
	.rxvalid2			(rxvalid2			),           
	.rxvalid3			(rxvalid3			), 
	//synthesis translate_on
	
	/* LMI Interface */
	.reset_status		(w_HipResetStatus	),//            hip_rst.reset_status
	.serdes_pll_locked	(w_HipSrdsPllLocked	),//                   .serdes_pll_locked
	.pld_clk_inuse		(					),//                   .pld_clk_inuse
	.pld_core_ready		(w_HipSrdsPllLocked	),//                   .pld_core_ready
	.testin_zero		(					),//                   .testin_zero
		
	.lmi_addr			(w12_LMIAddr		),//                lmi.lmi_addr
	.lmi_din			(w32_LMIDataIn		),//                   .lmi_din
	.lmi_rden			(w_LMIRead			),//                   .lmi_rden
	.lmi_wren			(w_LMIWrite			),//                   .lmi_wren
	.lmi_ack			(w_LMIAck			),//                   .lmi_ack
	.lmi_dout			(w32_LMIDataOut		),//                   .lmi_dout
	.cpl_err			(w7_CplErrOut		),//                   .cpl_err
	.cpl_pending		(w_CplPending		),//                   .cpl_pending
	
	/* Power Management Interface */	
	.pm_auxpwr				(w_PMAuxPwr		),//         power_mngt.pm_auxpwr
	.pm_data				(w10_PMData		),//                   .pm_data
	.pme_to_cr          	(w_PMEToCR		),//                   .pme_to_cr
	.pm_event           	(w_PMEvent		),//                   .pm_event
	.pme_to_sr				(w_PMEToSR		),//                   .pme_to_sr
	
	/*Reconfig Interface */
	.reconfig_to_xcvr		(wv_ReconfToXcvr),//reconfig_to_xcvr.reconfig_to_xcvr
	.reconfig_from_xcvr		(wv_ReconfFrXcvr),//reconfig_from_xcvr.reconfig_from_xcvr
	
	/*MSI Interrupt Request Interface */	
	.app_msi_num		(w5_MsiNum			),//            int_msi.app_msi_num
	.app_msi_req		(w_MsiReq			),//                   .app_msi_req
	.app_msi_tc			(w3_MsiTc			),//                   .app_msi_tc
	.app_msi_ack		(w_MsiAck			),//                   .app_msi_ack
	.app_int_sts_vec	(w_MsiStsVec		),//                   .app_int_sts
		
	
	/*Transaction Layer Configuration Interface */	
	.tl_hpg_ctrl_er		(5'h0				),//          config_tl.hpg_ctrler
	.tl_cfg_ctl			(w32_TLCfgCtrl		),//                   .tl_cfg_ctl
	
	.tl_cfg_add			(w7_TLCfgAddress[3:0]),//                   .tl_cfg_add
	.tl_cfg_sts			(w53_TLCfgStatus	),//                   .tl_cfg_sts
	
	.tl_cfg_ctl_wr		(w_TLCfgCtrlWr		),//                   .tl_cfg_ctl_wr
	.tl_cfg_sts_wr		(w_TLCfgStatusWr	),//                   .tl_cfg_sts_wr
	
	/* Corrected or Uncorrectable Errors Reporting*/
	.derr_cor_ext_rcv0	(					),//         hip_status.derr_cor_ext_rcv
	.derr_cor_ext_rpl	(					),//                   .derr_cor_ext_rpl
	.derr_rpl			(					),//                   .derr_rpl
	
	/* Hard IP Status Interface */
	.dlup_exit			(w_DataLinkUpExit	),//                   .dlup_exit
	.dl_ltssm			(w5_LTSSM			),//                   .ltssmstate
	.ev128ns			(w_Ev128ns			),//                   .ev128ns
	.ev1us				(w_Ev1us			),//                   .ev1us
	.hotrst_exit		(w_HotRstExit		),//                   .hotrst_exit
	.int_status			(w4_IntStatus		),//                   .int_status
	.l2_exit			(w_L2Exit			),//                   .l2_exit
	.lane_act			(w4_LaneActive		),//                   .lane_act
	
	.dl_current_speed	(w2_DLCurrentSpd	)//   hip_currentspeed.currentspeed
	);
	
	/*
	LMI Interface to write error log
	*/
	assign w_CplPending = 1'b0;
	assign w7_CplErrIn  = 7'h0;
	assign w7_CplErrOut = 7'h0;
	assign w_LMIWrite 	= 1'b0;
	assign w_LMIRead	= 1'b0;
	assign w32_LMIDataIn= 32'h0;
	assign w12_LMIAddr	= 12'h0;
	/*
	altpcierd_cplerr_lmi  uCmplErrReport(
   .clk_in		(w_AppClk			),
   .rstn		(w_HipSrdsPllLocked	),
   .err_desc	(w128_ErrDesc		),// TLP descriptor corresponding to cpl_err bits.  Written to AER header log when cpl_err[6] is asserted.
   .cpl_err_in	(w7_CplErrIn		),// cpl_err bits from application.  edge sensitive inputs.
   .lmi_ack		(w_LMIAck			),             // lmi read/write request acknowledge from core

   .lmi_din		(w32_LMIDataIn		),// lmi write data to core
   .lmi_addr	(w12_LMIAddr		),// lmi address to core
   .lmi_wren	(w_LMIWrite			),// lmi write request to core
   .cpl_err_out	(w7_CplErrOut		),// cpl_err signal to core
   .lmi_rden	(w_LMIRead			),// lmi read request to core
   .cplerr_lmi_busy	(w_CplErrLMIBusy));	// 1'b1 means this module is busy writing cpl_err/err_desc  to the core.
                                        // transitions on cpl_err while this signal is high are ignored.
        
	*/
	/* We don't use Power Management Interface Yet*/
	assign w_PMAuxPwr	= 1'b0;
	assign w10_PMData	= 10'h0;
	assign w_PMEToCR	= 1'b0;
	assign w_PMEvent	= 1'b0;
	
	/*This Reconfig Controller is used to do at least Offset Calcellation
	The Avalon Mgmt Interface is not required unless you'd like to 
	reconfig parameters otherthan Offset Calcellation
	*/
	assign if_ReconfMgmt.wv_Address = 0;
	assign if_ReconfMgmt.wv_WriteData = 0;
	assign if_ReconfMgmt.w_Read = 0;
	assign if_ReconfMgmt.w_Write = 0;
	mAltReconfCtrller u0AltReconfCtrller(
	.reconfig_busy			(w_ReconfBusy				),//      reconfig_busy.reconfig_busy
	.mgmt_clk_clk			(w_ReconfClk				),//       mgmt_clk_clk.clk
	.mgmt_rst_reset			(w_ReconfClkLock			),//     mgmt_rst_reset.reset
	.reconfig_mgmt_address	(if_ReconfMgmt.wv_Address	),//      reconfig_mgmt.address
	.reconfig_mgmt_read		(if_ReconfMgmt.w_Read		),//                   .read
	.reconfig_mgmt_readdata	(if_ReconfMgmt.wv_ReadData	),//                   .readdata
	.reconfig_mgmt_waitrequest(if_ReconfMgmt.w_WaitReq	),//                   .waitrequest
	.reconfig_mgmt_write	(if_ReconfMgmt.w_Write		),//                   .write
	.reconfig_mgmt_writedata(if_ReconfMgmt.wv_WriteData	),//                   .writedata
	
	.reconfig_to_xcvr		(wv_ReconfToXcvr			),//   reconfig_to_xcvr.reconfig_to_xcvr
	.reconfig_from_xcvr     (wv_ReconfFrXcvr			));// reconfig_from_xcvr.reconfig_from_xcvr
	
	/* For Simple Example, we dont generate any MSI */
	assign w5_MsiNum 	= 5'h0;
	assign w_MsiReq	 	= 1'b0;
	assign w3_MsiTc	 	= 3'h0;
	assign w_MsiStsVec 	= 1'b0;
	
	/* Reset Controller 
	Don't try to attempt this yourself
	There's some tricks and workaround involved for each FPGA family
	It's advisable to use the Reset Controller From the Example
	*/
	altpcierd_hip_rs u0ResetController(
    .dlup_exit		(w_DataLinkUpExit	),
    .hotrst_exit	(w_HotRstExit		),
    .l2_exit		(w_L2Exit			),
    .ltssm			(w5_LTSSM			),
    .npor			(i_PcieRst_L		),
    .pld_clk		(w_AppClk			),
    .test_sim		(1'b0),
    .app_rstn		(w_AppReset_L		));
	assign w_AppReset = ~w_AppReset_L;
	
	/*Configuration Sampler
	This module reads back data from the HIP to retrieve some configuration
	that is only available after Endpoint gets configured by the RootPort
	*/
	wire [31:0] w32_DevCsr,w32_LinkCsr,w32_PwrCsr;
	wire w_ReqGranted,w_ReqToSend,w_SupportedMsg;
	
	altpcierd_tl_cfg_sample uTLConfigReader(
	.pld_clk		(w_AppClk			),// 125Mhz or 250Mhz
	.rstn			(w_AppReset_L		),
	.tl_cfg_add		(w7_TLCfgAddress	),// from core_clk domain
	.tl_cfg_ctl		(w32_TLCfgCtrl		),// from core_clk domain
	.tl_cfg_ctl_wr	(w_TLCfgCtrlWr		),// from core_clk domain
	.tl_cfg_sts		(w53_TLCfgStatus	),// from core_clk domain
	.tl_cfg_sts_wr	(w_TLCfgStatusWr	),// from core_clk domain
  
	.cfg_busdev		(w13_Cfg_BusDev		),// synced to pld_clk
	.cfg_devcsr		(w32_DevCsr			),// synced to pld_clk
	.cfg_linkcsr	(w32_LinkCsr		),// synced to pld_clk
	.cfg_prmcsr		(w32_PwrCsr			),

	.cfg_io_bas	(),
	.cfg_io_lim	(),
	.cfg_np_bas	(),
	.cfg_np_lim	(),
	.cfg_pr_bas	(),
	.cfg_pr_lim	(),

	.cfg_tcvcmap(),
	.cfg_msicsr	());
	
	
	/*Application Portion*/
	
	/*Credit Tracker*/
	wire w_UpdConsPH,w_UpdConsPD;
	wire [07:0]	w8_IncCredPH;
	wire [11:0]	w12_IncCredPD;
	mTxCreditTracker u0TxCreditTracker(
	
	.i_HipCons1PH	(w6_ConsCred[5]),		//the tx_cred_fchipcons only toggles for internally generated TLP, you have 
	.i_HipCons1CH	(w6_ConsCred[1]),		//to monitor yourself for externally generated
	.i_HipCons1NH	(w6_ConsCred[3]),
	
	.i_HipCons1PD	(w6_ConsCred[4]),
	.i_HipCons1CD	(w6_ConsCred[0]),
	.i_HipCons1ND	(w6_ConsCred[2]),
	
	.i_AppConsXPH	(1'b0),				//If you have multiple requestor, these lines must be multiplexed accordingly
	.i_AppConsXCH	(1'b0),				//In some Altera family the fchipcons somehow doesn't work as supposed to
	.i_AppConsXNH	(1'b0),
	
	.i_AppConsXPD	(1'b0),
	.i_AppConsXCD	(1'b0),
	.i_AppConsXND	(1'b0),
	
	.i8_CredPH		(8'h0),
	.i8_CredCH		(8'h0),
	.i8_CredNH		(8'h0),
	
	.i12_CredPD		(12'h0),
	.i12_CredCD		(12'h0),
	.i12_CredND		(12'h0),
	
	.o8_CredPH		(w8_TxCredConsPH	),//Posted Header
	.o8_CredCH		(w8_TxCredConsCH	),//Completion Header
	.o8_CredNH		(w8_TxCredConsNH	),//Non Posted Header
	
	.o12_CredPD		(w12_TxCredConsPD	),//Posted Data
	.o12_CredCD		(w12_TxCredConsCD	),//Completion Data
	.o12_CredND		(w12_TxCredConsND	),//Nonposted Ddata
	
	.i_Clk			(w_AppClk	),
	.i_ARst			(w_AppReset	),
	.i_SClr			(1'b0));
	
	
	
	wire w_NxtPktMemWr,w_NxtPktMemRd,w_NxtPktIOWr,w_NxtPktIORd,w_NxtPktCmplD,w_NxtPktCmpl,w_NxtPktOthers;		
	wire [7:0] w8_NxtPktBarHit;
	wire [2:0] w3_NxtPktFuncHit;
	wire [9:0] w10_NxtPktPayldLen;
	mTLPBuffer #(
	.pWIDTH(64), 
	.pDEPTH(64)) u0TLPBuffer(
	
	.i_InRxDv		(if_RxStream.w_Valid),
	.i_InRxSop		(if_RxStream.w_Sop),
	.i_InRxEop		(if_RxStream.w_Eop),
	.iv_InRxData	(if_RxStream.wv_Data),
	.i_InRxErr		(if_RxStream.w_Error),
	.i_InRxEmpty	(if_RxStream.w_Empty),
	.o_InRxReady	(if_RxStream.w_Ready),
	.i8_BarHit		(w8_RxBarHit)		,//Bar
	.i3_Function	(3'h0)				,//Function
	
	.o_OutRxDv		(if_RxBuffOut.w_Valid),
	.o_OutRxSop		(if_RxBuffOut.w_Sop),
	.o_OutRxEop		(if_RxBuffOut.w_Eop),
	.ov_OutRxData	(if_RxBuffOut.wv_Data),
	.o_OutRxErr		(if_RxBuffOut.w_Error),
	.o_OutRxEmpty	(if_RxBuffOut.w_Empty),
	.i_OutRxReady	(if_RxBuffOut.w_Ready),
	
	.o_NxtPktMemWr		(w_NxtPktMemWr		),
	.o_NxtPktMemRd		(w_NxtPktMemRd		),
	.o_NxtPktIOWr		(w_NxtPktIOWr		),
	.o_NxtPktIORd		(w_NxtPktIORd		),
	.o_NxtPktCmplD		(w_NxtPktCmplD		),	//Completion With Data
	.o_NxtPktCmpl		(w_NxtPktCmpl		),	//Completion Without Data
	.o_NxtPktOthers		(w_NxtPktOthers		),
	.o8_NxtPktBarHit	(w8_NxtPktBarHit	),//Bar
	.o3_NxtPktFuncHit	(w3_NxtPktFuncHit	),//Function	
	.o10_NxtPktPayldLen	(w10_NxtPktPayldLen	),
	
	.i_Clk		(w_AppClk	),
	.i_ARst		(w_AppReset	));
	

	wire w_TLPBuffRead;
	wire w_mAltPcieLBusReady;
	wire [3:0] w4_TLPEngineEn;
	wire [7:0] w8_BarHit;
	assign if_RxBuffOut.w_Ready = w_TLPBuffRead;
	
	mTLPRxModerator #(.pENGINENUM(4)) u0TLPModerator(
	.iv_EngineReady	({3'b0,w_mAltPcieLBusReady}),
	.ov_EngineEn	(w4_TLPEngineEn),
	.o_TLPBuffRead	(w_TLPBuffRead),

	.i_RxSop	(if_RxBuffOut.w_Sop),
	.i_RxEop	(if_RxBuffOut.w_Eop),
	.i_RxDv		(if_RxBuffOut.w_Valid),
	
	.i_NxtPktMemWr	(w_NxtPktMemWr	),
	.i_NxtPktMemRd	(w_NxtPktMemRd	),
	.i_NxtPktIOWr	(w_NxtPktIOWr	),
	.i_NxtPktIORd	(w_NxtPktIORd	),
	.i_NxtPktCmplD	(w_NxtPktCmplD	),	//Completion With Data
	.i_NxtPktCmpl	(w_NxtPktCmpl	),	//Completion Without Data
	.i_NxtPktOthers	(w_NxtPktOthers	),
	.i8_NxtPktBarHit	(w8_NxtPktBarHit)	,//Bar
	.i3_NxtPktFuncHit	(w3_NxtPktFuncHit),//Function	
	.i10_NxtPktPayldLen	(w10_NxPktPayldLen),		
	.i_Clk			(w_AppClk),
	.i_ARst			(w_AppReset));
	
	
	/*PCIe LocalBus Interface */
	wire w_WbAck,w_WbCyc,w_WbStb,w_WbWnR,w_mAstPcieLBusRxDv;
	wire [31:0]	w32_WbWrData,w32_WbRdData;
	assign w_mAstPcieLBusRxDv = if_RxBuffOut.w_Valid & w4_TLPEngineEn[0]; 
	mAltPcieAst64LBus #(.pBUS_ADDR_WIDTH(12)) uPcieLBus(	
	//Avalon Stream TX
	.o_AstTxSop		(if_TxStream.w_Sop	),
	.o_AstTxEop		(if_TxStream.w_Eop	),
	.o_AstTxEmpty	(if_TxStream.w_Empty),//NotUsed
	.o_AstTxDv		(if_TxStream.w_Valid),
	.ov_AstTxData	(if_TxStream.wv_Data),
	.i_AstTxHIPReady(if_TxStream.w_Ready),
	
	//Avalon Stream RX
	.i_AstRxSop		(if_RxBuffOut.w_Sop),
	.i_AstRxEop		(if_RxBuffOut.w_Eop),
	.i_AstRxEmpty	(if_RxBuffOut.w_Empty),//NotUsed
	.i_AstRxDv		(w_mAstPcieLBusRxDv),
	.iv_AstRxData	(if_RxBuffOut.wv_Data),
	.o_AstRxReady	(w_mAltPcieLBusReady),
	.o_AstRxMask	(),
	.i7_BARSelect	(w8_NxtPktBarHit[6:0]),
	//Credit interface	
	.i8_CredLimPH	(w8_TxCredPH		),		//Posted Header
	.i8_CredLimCH	(w8_TxCredCH		),		//Completion Header
	.i8_CredLimNH	(w8_TxCredNH		),		//Non Posted Header	
	.i12_CredLimPD	(w12_TxCredPD		),	//Posted Data
	.i12_CredLimCD	(w12_TxCredCD		),	//Completion Data
	.i12_CredLimND	(w12_TxCredND		),	//Nonposted Ddata
	
	.i8_CredConPH	(w8_TxCredConsPH	),		//Posted Header
	.i8_CredConCH	(w8_TxCredConsCH	),		//Completion Header
	.i8_CredConNH	(w8_TxCredConsNH	),		//Non Posted Header	
	.i12_CredConPD	(w12_TxCredConsPD	),	//Posted Data
	.i12_CredConCD	(w12_TxCredConsCD	),	//Completion Data
	.i12_CredConND	(w12_TxCredConsND	),	//Nonposted Ddata
	
	.i_InfinitePH	(w6_InfiCred[5]		),
	.i_InfiniteCH	(w6_InfiCred[1]		),
	.i_InfiniteNH	(w6_InfiCred[3]		),
	.i_InfinitePD	(w6_InfiCred[4]		),
	.i_InfiniteCD	(w6_InfiCred[0]		),
	.i_InfiniteND	(w6_InfiCred[2]		),
	
	.i16_CompletorID	({w13_Cfg_BusDev,3'b000}),//Retrieve from HIP from Configuration Space, BusNum[15:8], DevNum[7:3],FuncNum[2:0];
	
	//Arbitration Interface
	.o_ReqToTx			(w_ReqToSend	),
	.i_ReqGranted		(w_ReqGranted	),
	.o_SupportedMsg		(w_SupportedMsg	),			//Raise this flag when the Msg is supported
	
	//Wishbone Bus master
	.o7_BARSelect		(),
	.o_WbCyc		(if_LBusRegBank.w_Cyc		),
	.o_WbStb		(if_LBusRegBank.w_Stb		),	
	.o_WbWnR		(if_LBusRegBank.w_WnR		),
	.ov_WbAddr		(if_LBusRegBank.wv_Address	),
	.o32_WbWrData	(if_LBusRegBank.wv_WriteData),
	.i32_WbRdData	(if_LBusRegBank.wv_ReadData	),
	.i_WbAck		(if_LBusRegBank.w_Ack),
	.o4_ByteEn		(if_LBusRegBank.w4_ByteEn),
	.i_Clk			(w_AppClk		),
	.i_ARst			(w_AppReset		));
	
	
	
	//Simple Arbitration Controller
	reg [3:0] r4_Granted;
	always@(posedge w_AppClk)
		begin 
			if(w_ReqToSend) r4_Granted <= 4'b0001;	
		end
	assign w_ReqGranted = r4_Granted[0];
	
	
	mRegisterBank #(.pADDRW(5)) u0RegBank(
	
	.i_WbCyc		(if_LBusRegBank.w_Cyc		),
	.i_WbStb		(if_LBusRegBank.w_Stb		),	
	.i_WbWnR		(if_LBusRegBank.w_WnR		),
	.iv_WbAddr		(if_LBusRegBank.wv_Address[6:2]),
	.i32_WbWrData	(if_LBusRegBank.wv_WriteData),
	.o32_WbRdData	(if_LBusRegBank.wv_ReadData	),
	.o_WbAck		(if_LBusRegBank.w_Ack),	
	.i4_ByteEn		(if_LBusRegBank.w4_ByteEn),
	.i_Clk	(w_AppClk	),
	.i_ARst	(w_AppReset	));
	
endmodule
