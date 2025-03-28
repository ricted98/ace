// Copyright (c) 2025 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`include "ace/typedef.svh"
`include "ace/assign.svh"

module ace_ccu_snoop_path import ace_pkg::*; import ccu_pkg::*; #(
    parameter ccu_cfg_t CcuCfg             = '{default: '0},
    parameter type ace_aw_chan_t           = logic, // AW Channel Type, ACE, without FSM route bits
    parameter type ace_ar_chan_t           = logic, // AR Channel Type, ACE, without FSM route bits
    parameter type ace_r_chan_t            = logic,
    parameter type ace_req_t               = logic, // Request type, ACE, without FSM route bits
    parameter type ace_resp_t              = logic, // Response type, ACE, without FSM route bits
    parameter type w_chan_t                = logic, // W Channel Type
    parameter type axi_req_t               = logic, // Request type, AXI, with FSM route bits
    parameter type axi_resp_t              = logic, // Response type, AXI, with FSM route bits
    parameter type axi_ar_chan_t           = logic,
    parameter type axi_r_chan_t            = logic,
    parameter type axi_aw_chan_t           = logic,
    parameter type axi_b_chan_t            = logic,
    parameter type snoop_ac_t              = logic, // AC channel, snoop port
    parameter type snoop_cr_t              = logic, // CR channel, snoop port
    parameter type snoop_cd_t              = logic, // CD channel, snoop port
    parameter type snoop_req_t             = logic, // Snoop port request type
    parameter type snoop_resp_t            = logic, // Snoop port response type
    parameter type domain_mask_t           = logic,
    parameter type domain_set_t            = logic
) (
    input  logic                                           clk_i,
    input  logic                                           rst_ni,
    input  ace_req_t                                       slv_req_i,
    output ace_resp_t                                      slv_resp_o,
    output axi_req_t                                       mst_req_o,
    input  axi_resp_t                                      mst_resp_i,
    input  domain_set_t  [CcuCfg.NoSlvPerGroup-1:0]        domain_set_i,
    output snoop_req_t   [CcuCfg.NoSnoopPortsPerGroup-1:0] snoop_reqs_o,
    input  snoop_resp_t  [CcuCfg.NoSnoopPortsPerGroup-1:0] snoop_resps_i,
    output domain_mask_t [CcuCfg.NoSnoopPortsPerGroup-1:0] snoop_masks_o
);
    localparam int unsigned SlvIdxBits = CcuCfg.NoSlvPerGroup > 1 ? $clog2(CcuCfg.NoSlvPerGroup) : 1;
    typedef logic [SlvIdxBits-1:0] slv_idx_t;

    typedef logic [CcuCfg.AxiAddrWidth-1:0] addr_t;
    typedef logic [CcuCfg.AxiDataWidth-1:0] data_t;
    typedef logic [CcuCfg.AxiUserWidth-1:0] user_t;

    // ID width after FSM
    typedef logic [CcuCfg.AxiPostMuxIdWidth-1:0] pm_id_t;

    // Datatypes for between FSMs and ccu_mem_ctrl
    `AXI_TYPEDEF_AW_CHAN_T(int_axi_aw_chan_t, addr_t, pm_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T (int_axi_b_chan_t, pm_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(int_axi_ar_chan_t, addr_t, pm_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T (int_axi_r_chan_t, data_t, pm_id_t, user_t)
    `AXI_TYPEDEF_REQ_T    (int_axi_req_t, int_axi_aw_chan_t, w_chan_t, int_axi_ar_chan_t)
    `AXI_TYPEDEF_RESP_T   (int_axi_resp_t, int_axi_b_chan_t, int_axi_r_chan_t)

    int_axi_req_t  [1:0] mst_reqs;
    int_axi_resp_t [1:0] mst_resps;

    ace_req_t  slv_read_req, slv_write_req;
    ace_resp_t slv_read_resp, slv_write_resp;

    logic aw_wb, b_wb;

    ///////////
    // SPLIT //
    ///////////

    `ACE_ASSIGN_AR_STRUCT (slv_read_req.ar, slv_req_i.ar)
    assign slv_read_req.ar_valid = slv_req_i.ar_valid;
    assign slv_resp_o.ar_ready   = slv_read_resp.ar_ready;
    assign slv_read_req.aw       = '0;
    assign slv_read_req.w        = '0;
    assign slv_read_req.aw_valid = 1'b0;
    assign slv_read_req.w_valid  = 1'b0;
    assign slv_read_req.b_ready  = 1'b0;

    `ACE_ASSIGN_AW_STRUCT ( slv_write_req.aw , slv_req_i.aw       )
    `AXI_ASSIGN_W_STRUCT  ( slv_write_req.w  , slv_req_i.w        )
    `AXI_ASSIGN_B_STRUCT  ( slv_resp_o.b     , slv_write_resp.b )
    assign slv_write_req.aw_valid = slv_req_i.aw_valid;
    assign slv_write_req.w_valid  = slv_req_i.w_valid;
    assign slv_write_req.b_ready  = slv_req_i.b_ready;
    assign slv_resp_o.aw_ready    = slv_write_resp.aw_ready;
    assign slv_resp_o.w_ready     = slv_write_resp.w_ready;
    assign slv_resp_o.b_valid     = slv_write_resp.b_valid;
    assign slv_write_req.ar_valid = 1'b0;

    // Arbiter to mux between R responses from W FSM and R FSM
    // This is fine because W FSM provides only R responses from
    // atomic transactions, and they must have different ID than
    // any outstanding transaction (AXI Issue J A7.4.4)
    stream_arbiter #(
        .DATA_T  (ace_r_chan_t),
        .N_INP   (2),
        .ARBITER ("rr")
    ) i_r_arbiter (
        .clk_i,
        .rst_ni,
        .inp_data_i ({slv_write_resp.r, slv_read_resp.r}),
        .inp_valid_i({slv_write_resp.r_valid, slv_read_resp.r_valid}),
        .inp_ready_o({slv_write_req.r_ready, slv_read_req.r_ready}),
        .oup_data_o (slv_resp_o.r),
        .oup_valid_o(slv_resp_o.r_valid),
        .oup_ready_i(slv_req_i.r_ready)
    );

    ////////////////
    // WRITE PATH //
    ////////////////

    acsnoop_t write_acsnoop;
    slv_idx_t write_slv_idx;

    if (CcuCfg.NoSlvPerGroup > 1)
        assign write_slv_idx = slv_write_req.aw.id[CcuCfg.AxiSlvIdWidth+:SlvIdxBits];
    else
        assign write_slv_idx = '0;

    ace_aw_transaction_decoder #(
        .aw_chan_t (ace_aw_chan_t)
    ) i_write_decoder (
        .aw_i          (slv_write_req.aw),
        .snooping_o    (),
        .acsnoop_o     (write_acsnoop),
        .illegal_trs_o ()
    );

    ccu_ctrl_wr_snoop #(
        .CcuCfg              (CcuCfg),
        .slv_req_t           (ace_req_t),
        .slv_resp_t          (ace_resp_t),
        .slv_aw_chan_t       (ace_aw_chan_t),
        .slv_w_chan_t        (w_chan_t),
        .mst_req_t           (int_axi_req_t),
        .mst_resp_t          (int_axi_resp_t),
        .mst_aw_chan_t       (int_axi_aw_chan_t),
        .mst_w_chan_t        (w_chan_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t),
        .domain_set_t        (domain_set_t),
        .domain_mask_t       (domain_mask_t),
        .FIFO_DEPTH          (2)
    ) i_ccu_ctrl_wr_snoop (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .slv_req_i     (slv_write_req),
        .slv_resp_o    (slv_write_resp),
        .snoop_trs_i   (write_acsnoop),
        .mst_req_o     (mst_reqs       [0]),
        .mst_resp_i    (mst_resps      [0]),
        .snoop_req_o   (snoop_reqs_o   [0]),
        .snoop_resp_i  (snoop_resps_i  [0]),
        .domain_set_i  (domain_set_i[write_slv_idx]),
        .domain_mask_o (snoop_masks_o  [0]),
        .aw_wb_o       (aw_wb),
        .b_wb_i        (b_wb)
    );

    ///////////////
    // READ PATH //
    ///////////////

    snoop_info_t read_snoop_info;
    slv_idx_t    read_slv_idx;

    if (CcuCfg.NoSlvPerGroup > 1)
        assign read_slv_idx = slv_read_req.ar.id[CcuCfg.AxiSlvIdWidth+:SlvIdxBits];
    else
        assign read_slv_idx = '0;

    ace_ar_transaction_decoder #(
        .LEGACY    (CcuCfg.AmoHotfix),
        .ar_chan_t (ace_ar_chan_t)
    ) i_read_decoder (
        .ar_i          (slv_read_req.ar),
        .snooping_o    (),
        .snoop_info_o  (read_snoop_info),
        .illegal_trs_o ()
    );

    ccu_ctrl_r_snoop #(
        .CcuCfg              (CcuCfg),
        .slv_req_t           (ace_req_t),
        .slv_resp_t          (ace_resp_t),
        .slv_ar_chan_t       (ace_ar_chan_t),
        .slv_r_chan_t        (ace_r_chan_t),
        .mst_req_t           (int_axi_req_t),
        .mst_resp_t          (int_axi_resp_t),
        .mst_snoop_req_t     (snoop_req_t),
        .mst_snoop_resp_t    (snoop_resp_t),
        .domain_set_t        (domain_set_t),
        .domain_mask_t       (domain_mask_t),
        .FIFO_DEPTH          (2)
    ) i_ccu_ctrl_r_snoop (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .slv_req_i     (slv_read_req),
        .slv_resp_o    (slv_read_resp),
        .snoop_info_i  (read_snoop_info),
        .mst_req_o     (mst_reqs       [1]),
        .mst_resp_i    (mst_resps      [1]),
        .snoop_req_o   (snoop_reqs_o   [1]),
        .snoop_resp_i  (snoop_resps_i  [1]),
        .domain_set_i  (domain_set_i[read_slv_idx]),
        .domain_mask_o (snoop_masks_o  [1])
    );

    ccu_mem_ctrl #(
        .CcuCfg        (CcuCfg),
        .slv_req_t     (int_axi_req_t),
        .slv_resp_t    (int_axi_resp_t),
        .mst_req_t     (axi_req_t),
        .mst_resp_t    (axi_resp_t),
        .slv_ar_chan_t (int_axi_ar_chan_t),
        .slv_r_chan_t  (int_axi_r_chan_t),
        .slv_aw_chan_t (int_axi_aw_chan_t),
        .w_chan_t      (w_chan_t),
        .slv_b_chan_t  (int_axi_b_chan_t),
        .mst_ar_chan_t (axi_ar_chan_t),
        .mst_r_chan_t  (axi_r_chan_t),
        .mst_aw_chan_t (axi_aw_chan_t),
        .mst_b_chan_t  (axi_b_chan_t)
    ) i_ccu_mem_ctrl (
        .clk_i,
        .rst_ni,
        .wr_slv_req_i   (mst_reqs[0]),
        .wr_slv_resp_o  (mst_resps[0]),
        .r_slv_req_i    (mst_reqs[1]),
        .r_slv_resp_o   (mst_resps[1]),
        .mst_req_o,
        .mst_resp_i,
        .wr_slv_aw_wb_i (aw_wb),
        .wr_slv_b_wb_o  (b_wb)
    );

endmodule
