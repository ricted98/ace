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

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "ace/assign.svh"
`include "ace/typedef.svh"
`include "ace/convert.svh"
`include "ace/domain.svh"

module ace_ccu_top
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg        = '{default: '0},
    parameter type          domain_rule_t = logic,
    parameter type          slv_ar_t      = logic,
    parameter type          slv_aw_t      = logic,
    parameter type          w_t           = logic,
    parameter type          slv_b_t       = logic,
    parameter type          slv_r_t       = logic,
    parameter type          slv_req_t     = logic,
    parameter type          slv_resp_t    = logic,
    parameter type          mst_ar_t      = logic,
    parameter type          mst_aw_t      = logic,
    parameter type          mst_b_t       = logic,
    parameter type          mst_r_t       = logic,
    parameter type          mst_req_t     = logic,
    parameter type          mst_resp_t    = logic,
    parameter type          snoop_ac_t    = logic,
    parameter type          snoop_cr_t    = logic,
    parameter type          snoop_cd_t    = logic,
    parameter type          snoop_req_t   = logic,
    parameter type          snoop_resp_t  = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_i,
    output slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_o,

    input domain_rule_t [CcuCfg.u.SlvPorts-1:0] domain_rule_i,

    output snoop_req_t  [CcuCfg.u.SlvPorts-1:0] snoop_req_o,
    input  snoop_resp_t [CcuCfg.u.SlvPorts-1:0] snoop_resp_i,

    output mst_req_t  mst_req_o,
    input  mst_resp_t mst_resp_i
);

    // CcuCfg dependent typedefs

    // AXI/ACE types
    typedef logic [CcuCfg.u.AxiSlvIdWidth-1:0] slv_id_t;
    typedef logic [CcuCfg.AxiCcuIdWidth-1:0] ccu_id_t;
    typedef logic [CcuCfg.AxiMstIdWidth-1:0] mst_id_t;
    typedef logic [CcuCfg.u.AxiAddrWidth-1:0] addr_t;
    typedef logic [CcuCfg.u.AxiDataWidth-1:0] data_t;
    typedef logic [CcuCfg.AxiStrbWidth-1:0] strb_t;
    typedef logic [CcuCfg.u.AxiUserWidth-1:0] user_t;

    // Intermediate ACE and AXI channel types
    `ACE_TYPEDEF_AW_CHAN_T(ccu_ace_aw_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(ccu_ace_b_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(ccu_ace_ar_t, addr_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(ccu_ace_r_t, data_t, ccu_id_t, user_t)
    `ACE_TYPEDEF_REQ_T(ccu_ace_req_t, ccu_ace_aw_t, w_t, ccu_ace_ar_t)
    `ACE_TYPEDEF_RESP_T(ccu_ace_resp_t, ccu_ace_b_t, ccu_ace_r_t)

    `AXI_TYPEDEF_AW_CHAN_T(ccu_axi_aw_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(ccu_axi_b_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(ccu_axi_ar_t, addr_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(ccu_axi_r_t, data_t, ccu_id_t, user_t)
    `AXI_TYPEDEF_REQ_T(ccu_axi_req_t, ccu_axi_aw_t, w_t, ccu_axi_ar_t)
    `AXI_TYPEDEF_RESP_T(ccu_axi_resp_t, ccu_axi_b_t, ccu_axi_r_t)

    // Transaction ID type
    typedef logic [CcuCfg.TransactionIdWidth-1:0] tid_t;

    // Internal AW/AR request unified representation
    typedef struct packed {
        ccu_id_t          id;
        addr_t            addr;
        axi_pkg::len_t    len;
        axi_pkg::size_t   size;
        axi_pkg::burst_t  burst;
        logic             lock;
        axi_pkg::cache_t  cache;
        axi_pkg::prot_t   prot;
        axi_pkg::qos_t    qos;
        axi_pkg::region_t region;
        axi_pkg::atop_t   atop;
        user_t            user;
    } ccu_ax_t;

    // Frontend ~> Midend piped signals
    typedef struct packed {
        logic                         ax_is_write;
        logic                         ax_snooping;
        logic                         ar_accepts_dirty;
        logic                         ar_accepts_dirty_shared;
        logic                         ar_accepts_shared;
        logic [CcuCfg.u.SlvPorts-1:0] cr_sel_bv;
        tid_t                         tid;
        ccu_ax_t                      ax;
    } midend_t;

    // Midend ~> Backend piped signals
    typedef struct packed {
        cd_sel_t                      cd_sel;
        logic                         aw_sel;
        logic                         ar_sel;
        logic                         r_resp_dirty;
        logic                         r_resp_shared;
        logic                         ax_is_write;
        logic [CcuCfg.u.SlvPorts-1:0] cd_sel_bv;
        tid_t                         tid;
        ccu_ax_t                      ax;
    } backend_t;

    // Backend CD ctrl signals
    typedef struct packed {
        tid_t                                            tid;
        ccu_id_t                                         id;
        cd_sel_t                                         cd_sel;
        logic [CcuCfg.CachelineAxiTransfersIdxWidth-1:0] r_drop;
        logic                                            r_resp_shared;
        logic                                            r_resp_dirty;
        user_t                                           r_user;
        logic [CcuCfg.u.SlvPorts-1:0]                    cd_sel_bv;
        axi_pkg::len_t                                   r_len;
    } cd_ctrl_t;

    // Internal signals
    ccu_ace_req_t                                 ccu_nonblock_req;
    ccu_ace_resp_t                                ccu_nonblock_resp;
    ccu_ace_req_t                                 ccu_block_req;
    ccu_ace_resp_t                                ccu_block_resp;

    logic          [CcuCfg.u.MaxTransactions-1:0] pos_inflight_valid_r_clr;
    logic          [CcuCfg.u.MaxTransactions-1:0] pos_inflight_valid_b_clr;

    midend_t                                      midend;
    logic                                         midend_valid;
    logic                                         midend_ready;

    backend_t                                     backend;
    logic                                         backend_valid;
    logic                                         backend_ready;
    w_t                                           backend_w;
    logic                                         backend_w_valid;
    logic                                         backend_w_ready;


    tid_t                                         ccu_block_r_tid;
    tid_t                                         ccu_block_b_tid;

    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_ac_valid;
    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_ac_ready;
    snoop_ac_t     [       CcuCfg.u.SlvPorts-1:0] snoop_ac;
    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_cr_valid;
    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_cr_ready;
    snoop_cr_t     [       CcuCfg.u.SlvPorts-1:0] snoop_cr;
    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_cd_valid;
    logic          [       CcuCfg.u.SlvPorts-1:0] snoop_cd_ready;
    snoop_cd_t     [       CcuCfg.u.SlvPorts-1:0] snoop_cd;

    ccu_ace_req_t                                 ace_backend_req;
    ccu_ace_resp_t                                ace_backend_resp;

    ccu_axi_req_t                                 axi_backend_req;
    ccu_axi_resp_t                                axi_backend_resp;
    ccu_axi_req_t                                 axi_nonblock_req;
    ccu_axi_resp_t                                axi_nonblock_resp;

    mst_req_t                                     mst_req;
    mst_resp_t                                    mst_resp;


    //--------------------
    //  Frontend
    //--------------------

    ace_ccu_frontend #(
        .CcuCfg    (CcuCfg),
        .tid_t     (tid_t),
        .slv_aw_t  (slv_aw_t),
        .w_t       (w_t),
        .slv_b_t   (slv_b_t),
        .slv_ar_t  (slv_ar_t),
        .slv_r_t   (slv_r_t),
        .slv_req_t (slv_req_t),
        .slv_resp_t(slv_resp_t),
        .ccu_aw_t  (ccu_ace_aw_t),
        .ccu_b_t   (ccu_ace_b_t),
        .ccu_ar_t  (ccu_ace_ar_t),
        .ccu_r_t   (ccu_ace_r_t),
        .ccu_req_t (ccu_ace_req_t),
        .ccu_resp_t(ccu_ace_resp_t)
    ) u_ace_ccu_frontend (
        .clk_i,
        .rst_ni,
        .slv_req_i             (slv_req_i),
        .slv_resp_o            (slv_resp_o),
        .ccu_nonblock_req_o    (ccu_nonblock_req),
        .ccu_nonblock_resp_i   (ccu_nonblock_resp),
        .ccu_block_b_tid_i     (ccu_block_b_tid),
        .ccu_block_r_tid_i     (ccu_block_r_tid),
        .ccu_block_req_o       (ccu_block_req),
        .ccu_block_resp_i      (ccu_block_resp),
        .inflight_valid_r_clr_o(pos_inflight_valid_r_clr),
        .inflight_valid_b_clr_o(pos_inflight_valid_b_clr)
    );

    //--------------------
    //  Blocking traffic PoS
    //--------------------

    ace_ccu_pos #(
        .CcuCfg       (CcuCfg),
        .domain_rule_t(domain_rule_t),
        .ccu_aw_t     (ccu_ace_aw_t),
        .ccu_ar_t     (ccu_ace_ar_t),
        .ccu_ax_t     (ccu_ax_t),
        .ac_t         (snoop_ac_t),
        .midend_t     (midend_t),
        .tid_t        (tid_t)
    ) u_ace_ccu_pos (
        .clk_i,
        .rst_ni,
        .ac_o                  (snoop_ac),
        .ac_valid_o            (snoop_ac_valid),
        .ac_ready_i            (snoop_ac_ready),
        .domain_rule_i         (domain_rule_i),
        .aw_block_i            (ccu_block_req.aw),
        .aw_block_valid_i      (ccu_block_req.aw_valid),
        .aw_block_ready_o      (ccu_block_resp.aw_ready),
        .ar_block_i            (ccu_block_req.ar),
        .ar_block_valid_i      (ccu_block_req.ar_valid),
        .ar_block_ready_o      (ccu_block_resp.ar_ready),
        .midend_o              (midend),
        .midend_valid_o        (midend_valid),
        .midend_ready_i        (midend_ready),
        .inflight_valid_b_clr_i(pos_inflight_valid_b_clr),
        .inflight_valid_r_clr_i(pos_inflight_valid_r_clr)
    );

    // W buffer
    stream_fifo #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (CcuCfg.u.BlockingWFifoDepth),
        .T           (w_t)
    ) u_w_fifo (
        .clk_i,
        .rst_ni,
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (ccu_block_req.w),
        .valid_i   (ccu_block_req.w_valid),
        .ready_o   (ccu_block_resp.w_ready),
        .data_o    (backend_w),
        .valid_o   (backend_w_valid),
        .ready_i   (backend_w_ready)
    );

    //--------------------
    //  Midend
    //--------------------

    ace_ccu_midend #(
        .CcuCfg   (CcuCfg),
        .cr_t     (snoop_cr_t),
        .midend_t (midend_t),
        .cd_sel_t (cd_sel_t),
        .backend_t(backend_t)
    ) u_midend (
        .clk_i,
        .rst_ni,
        .midend_valid_i (midend_valid),
        .midend_ready_o (midend_ready),
        .midend_i       (midend),
        .cr_i           (snoop_cr),
        .cr_valid_i     (snoop_cr_valid),
        .cr_ready_o     (snoop_cr_ready),
        .backend_valid_o(backend_valid),
        .backend_ready_i(backend_ready),
        .backend_o      (backend)
    );

    //--------------------
    //  Backend
    //--------------------

    ace_ccu_backend #(
        .CcuCfg   (CcuCfg),
        .ccu_ar_t (ccu_ace_ar_t),
        .ccu_aw_t (ccu_ace_aw_t),
        .w_t      (w_t),
        .ccu_b_t  (ccu_ace_b_t),
        .ccu_r_t  (ccu_ace_r_t),
        .backend_t(backend_t),
        .cd_t     (snoop_cd_t),
        .cd_ctrl_t(cd_ctrl_t),
        .tid_t    (tid_t)
    ) u_backend (
        .clk_i,
        .rst_ni,
        .backend_valid_i(backend_valid),
        .backend_ready_o(backend_ready),
        .backend_i      (backend),
        .cd_i           (snoop_cd),
        .cd_valid_i     (snoop_cd_valid),
        .cd_ready_o     (snoop_cd_ready),
        .w_i            (backend_w),
        .w_valid_i      (backend_w_valid),
        .w_ready_o      (backend_w_ready),
        .r_o            (ccu_block_resp.r),
        .r_tid_o        (ccu_block_r_tid),
        .r_valid_o      (ccu_block_resp.r_valid),
        .r_ready_i      (ccu_block_req.r_ready),
        .b_o            (ccu_block_resp.b),
        .b_tid_o        (ccu_block_b_tid),
        .b_valid_o      (ccu_block_resp.b_valid),
        .b_ready_i      (ccu_block_req.b_ready),
        .ar_o           (ace_backend_req.ar),
        .ar_valid_o     (ace_backend_req.ar_valid),
        .ar_ready_i     (ace_backend_resp.ar_ready),
        .aw_o           (ace_backend_req.aw),
        .aw_valid_o     (ace_backend_req.aw_valid),
        .aw_ready_i     (ace_backend_resp.aw_ready),
        .w_o            (ace_backend_req.w),
        .w_valid_o      (ace_backend_req.w_valid),
        .w_ready_i      (ace_backend_resp.w_ready),
        .r_i            (ace_backend_resp.r),
        .r_valid_i      (ace_backend_resp.r_valid),
        .r_ready_o      (ace_backend_req.r_ready),
        .b_i            (ace_backend_resp.b),
        .b_valid_i      (ace_backend_resp.b_valid),
        .b_ready_o      (ace_backend_req.b_ready)
    );


    //--------------------
    //  Mst MUX
    //--------------------

    `ACE_TO_AXI_ASSIGN_REQ(axi_backend_req, ace_backend_req)
    `AXI_TO_ACE_ASSIGN_RESP(ace_backend_resp, axi_backend_resp)
    `ACE_TO_AXI_ASSIGN_REQ(axi_nonblock_req, ccu_nonblock_req)
    `AXI_TO_ACE_ASSIGN_RESP(ccu_nonblock_resp, axi_nonblock_resp)

    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.AxiCcuIdWidth),
        .slv_aw_chan_t(ccu_axi_aw_t),
        .mst_aw_chan_t(mst_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (ccu_axi_b_t),
        .mst_b_chan_t (mst_b_t),
        .slv_ar_chan_t(ccu_axi_ar_t),
        .mst_ar_chan_t(mst_ar_t),
        .slv_r_chan_t (ccu_axi_r_t),
        .mst_r_chan_t (mst_r_t),
        .slv_req_t    (ccu_axi_req_t),
        .slv_resp_t   (ccu_axi_resp_t),
        .mst_req_t    (mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .NoSlvPorts   (2),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_axi_mst_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i ({axi_nonblock_req, axi_backend_req}),
        .slv_resps_o({axi_nonblock_resp, axi_backend_resp}),
        .mst_req_o  (mst_req),
        .mst_resp_i (mst_resp)
    );

    //--------------------
    //  ACE/AXI cuts
    //--------------------

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_snoop_queues
        spill_register #(
            .T     (snoop_ac_t),
            .Bypass(!CcuCfg.u.CutSnoopReq)
        ) u_ac_queue (
            .clk_i,
            .rst_ni,
            .valid_i(snoop_ac_valid[i]),
            .ready_o(snoop_ac_ready[i]),
            .data_i (snoop_ac[i]),
            .valid_o(snoop_req_o[i].ac_valid),
            .ready_i(snoop_resp_i[i].ac_ready),
            .data_o (snoop_req_o[i].ac)
        );

        spill_register #(
            .T     (snoop_cr_t),
            .Bypass(!CcuCfg.u.CutSnoopResp)
        ) u_cr_queue (
            .clk_i,
            .rst_ni,
            .valid_i(snoop_resp_i[i].cr_valid),
            .ready_o(snoop_req_o[i].cr_ready),
            .data_i (snoop_resp_i[i].cr_resp),
            .valid_o(snoop_cr_valid[i]),
            .ready_i(snoop_cr_ready[i]),
            .data_o (snoop_cr[i])
        );

        spill_register #(
            .T     (snoop_cd_t),
            .Bypass(!CcuCfg.u.CutSnoopResp)
        ) u_cd_queue (
            .clk_i,
            .rst_ni,
            .valid_i(snoop_resp_i[i].cd_valid),
            .ready_o(snoop_req_o[i].cd_ready),
            .data_i (snoop_resp_i[i].cd),
            .valid_o(snoop_cd_valid[i]),
            .ready_i(snoop_cd_ready[i]),
            .data_o (snoop_cd[i])
        );
    end

    axi_cut #(
        .BypassAw  (!CcuCfg.u.CutMstReq),
        .BypassW   (!CcuCfg.u.CutMstReq),
        .BypassB   (!CcuCfg.u.CutMstResp),
        .BypassAr  (!CcuCfg.u.CutMstReq),
        .BypassR   (!CcuCfg.u.CutMstResp),
        .aw_chan_t (mst_aw_t),
        .w_chan_t  (w_t),
        .b_chan_t  (mst_b_t),
        .ar_chan_t (mst_ar_t),
        .r_chan_t  (mst_r_t),
        .axi_req_t (mst_req_t),
        .axi_resp_t(mst_resp_t)
    ) u_mst_queue (
        .clk_i,
        .rst_ni,
        .slv_req_i (mst_req),
        .slv_resp_o(mst_resp),
        .mst_req_o (mst_req_o),
        .mst_resp_i(mst_resp_i)
    );

endmodule

module ace_ccu_top_intf
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter  ace_ccu_cfg_t CCU_CFG       = '{default: '0},
    localparam type          domain_bv_t   = `DOMAIN_BV_T(CCU_CFG.u.SlvPorts),
    localparam type          domain_rule_t = `DOMAIN_RULE_T(domain_bv_t)
) (
    input logic                                    clk_i,
    input logic                                    rst_ni,
    input domain_rule_t   [CCU_CFG.u.SlvPorts-1:0] domain_rule_i,
          ACE_BUS.Slave                            slv          [CCU_CFG.u.SlvPorts-1:0],
          SNOOP_BUS.Slave                          snoop        [CCU_CFG.u.SlvPorts-1:0],
          AXI_BUS.Master                           mst
);

    typedef logic [CCU_CFG.u.AxiSlvIdWidth-1:0] slv_id_t;
    typedef logic [CCU_CFG.AxiMstIdWidth-1:0] mst_id_t;
    typedef logic [CCU_CFG.u.AxiAddrWidth-1:0] addr_t;
    typedef logic [CCU_CFG.u.AxiDataWidth-1:0] data_t;
    typedef logic [CCU_CFG.u.AxiDataWidth/8-1:0] strb_t;
    typedef logic [CCU_CFG.u.AxiUserWidth-1:0] user_t;

    `ACE_TYPEDEF_AW_CHAN_T(slv_aw_t, addr_t, slv_id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(w_t, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(slv_b_t, slv_id_t, user_t)
    `ACE_TYPEDEF_AR_CHAN_T(slv_ar_t, addr_t, slv_id_t, user_t)
    `ACE_TYPEDEF_R_CHAN_T(slv_r_t, data_t, slv_id_t, user_t)
    `ACE_TYPEDEF_REQ_T(slv_req_t, slv_aw_t, w_t, slv_ar_t)
    `ACE_TYPEDEF_RESP_T(slv_resp_t, slv_b_t, slv_r_t)

    `AXI_TYPEDEF_AW_CHAN_T(mst_aw_t, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(mst_b_t, mst_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(mst_ar_t, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(mst_r_t, data_t, mst_id_t, user_t)
    `AXI_TYPEDEF_REQ_T(mst_req_t, mst_aw_t, w_t, mst_ar_t)
    `AXI_TYPEDEF_RESP_T(mst_resp_t, mst_b_t, mst_r_t)

    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_t, snoop_cr_t)

    slv_req_t    [CCU_CFG.u.SlvPorts-1:0] slv_req;
    slv_resp_t   [CCU_CFG.u.SlvPorts-1:0] slv_resp;

    mst_req_t                             mst_req;
    mst_resp_t                            mst_resp;

    snoop_req_t  [CCU_CFG.u.SlvPorts-1:0] snoop_req;
    snoop_resp_t [CCU_CFG.u.SlvPorts-1:0] snoop_resp;

    for (genvar i = 0; i < CCU_CFG.u.SlvPorts; i++) begin
        `ACE_ASSIGN_TO_REQ(slv_req[i], slv[i])
        `ACE_ASSIGN_FROM_RESP(slv[i], slv_resp[i])
        `SNOOP_ASSIGN_FROM_REQ(snoop[i], snoop_req[i])
        `SNOOP_ASSIGN_TO_RESP(snoop_resp[i], snoop[i])
    end

    `AXI_ASSIGN_FROM_REQ(mst, mst_req)
    `AXI_ASSIGN_TO_RESP(mst_resp, mst)

    ace_ccu_top #(
        .CcuCfg       (CCU_CFG),
        .domain_rule_t(domain_rule_t),
        .slv_ar_t     (slv_ar_t),
        .slv_aw_t     (slv_aw_t),
        .w_t          (w_t),
        .slv_b_t      (slv_b_t),
        .slv_r_t      (slv_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_ar_t     (mst_ar_t),
        .mst_aw_t     (mst_aw_t),
        .mst_b_t      (mst_b_t),
        .mst_r_t      (mst_r_t),
        .mst_req_t    (mst_req_t),
        .mst_resp_t   (mst_resp_t),
        .snoop_ac_t   (snoop_ac_t),
        .snoop_cr_t   (snoop_cr_t),
        .snoop_cd_t   (snoop_cd_t),
        .snoop_req_t  (snoop_req_t),
        .snoop_resp_t (snoop_resp_t)
    ) u_ace_ccu (
        .clk_i,
        .rst_ni,
        .slv_req_i    (slv_req),
        .slv_resp_o   (slv_resp),
        .domain_rule_i(domain_rule_i),
        .snoop_req_o  (snoop_req),
        .snoop_resp_i (snoop_resp),
        .mst_req_o    (mst_req),
        .mst_resp_i   (mst_resp)
    );

endmodule
