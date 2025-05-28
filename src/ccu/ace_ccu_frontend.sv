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

module ace_ccu_frontend
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg     = '{default: '0},
    parameter type          tid_t      = logic,
    parameter type          slv_aw_t   = logic,
    parameter type          w_t        = logic,
    parameter type          slv_b_t    = logic,
    parameter type          slv_ar_t   = logic,
    parameter type          slv_r_t    = logic,
    parameter type          slv_req_t  = logic,
    parameter type          slv_resp_t = logic,
    parameter type          ccu_aw_t   = logic,
    parameter type          ccu_b_t    = logic,
    parameter type          ccu_ar_t   = logic,
    parameter type          ccu_r_t    = logic,
    parameter type          ccu_req_t  = logic,
    parameter type          ccu_resp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_i,
    output slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_o,

    output ccu_req_t  ccu_nonblock_req_o,
    input  ccu_resp_t ccu_nonblock_resp_i,
    input  tid_t      ccu_block_b_tid_i,
    input  tid_t      ccu_block_r_tid_i,
    output ccu_req_t  ccu_block_req_o,
    input  ccu_resp_t ccu_block_resp_i,

    output logic [CcuCfg.u.MaxTransactions-1:0] inflight_valid_r_clr_o,
    output logic [CcuCfg.u.MaxTransactions-1:0] inflight_valid_b_clr_o
);

    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_req_cut;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_resp_cut;

    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_nonblock_req;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_nonblock_resp;
    slv_req_t  [CcuCfg.u.SlvPorts-1:0] slv_block_req;
    slv_resp_t [CcuCfg.u.SlvPorts-1:0] slv_block_resp;

    logic      [CcuCfg.u.SlvPorts-1:0] b_idx;
    logic      [CcuCfg.u.SlvPorts-1:0] r_idx;

    tid_t      [CcuCfg.u.SlvPorts-1:0] pos_r_tid;
    tid_t      [CcuCfg.u.SlvPorts-1:0] pos_b_tid;
    logic      [CcuCfg.u.SlvPorts-1:0] r_ignore;
    logic      [CcuCfg.u.SlvPorts-1:0] b_ignore;

    // Demux slv traffic into blocking and non-blocking traffic
    // Non-blocking traffic is expected to proceed even when the snoop
    // interface is stalling

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_slv_demux

        logic aw_is_nonblock;
        logic ar_is_read_no_snoop;

        ace_cut #(
            .BypassAw  (!CcuCfg.u.CutSlvReq),
            .BypassW   (!CcuCfg.u.CutSlvReq),
            .BypassB   (!CcuCfg.u.CutSlvResp),
            .BypassAr  (!CcuCfg.u.CutSlvReq),
            .BypassR   (!CcuCfg.u.CutSlvResp),
            .BypassAck (1'b1),
            .aw_chan_t (slv_aw_t),
            .w_chan_t  (w_t),
            .b_chan_t  (slv_b_t),
            .ar_chan_t (slv_ar_t),
            .r_chan_t  (slv_r_t),
            .ace_req_t (slv_req_t),
            .ace_resp_t(slv_resp_t)
        ) u_ace_cut (
            .clk_i,
            .rst_ni,
            .slv_req_i (slv_req_i[i]),
            .slv_resp_o(slv_resp_o[i]),
            .mst_req_o (slv_req_cut[i]),
            .mst_resp_i(slv_resp_cut[i])
        );

        // Separate in each port blocking and non-blocking traffic
        assign aw_is_nonblock = aw_is_non_blocking(
            slv_req_cut[i].aw.bar[0], slv_req_cut[i].aw.domain, slv_req_cut[i].aw.snoop
        );

        assign ar_is_read_no_snoop = is_read_no_snoop(
            slv_req_cut[i].ar.bar[0], slv_req_cut[i].ar.domain, slv_req_cut[i].ar.snoop
        );

        axi_demux_simple #(
            .AxiIdWidth (CcuCfg.u.AxiSlvIdWidth),
            .AtopSupport(1'b1),
            .axi_req_t  (slv_req_t),
            .axi_resp_t (slv_resp_t),
            .NoMstPorts (2),
            .MaxTrans   (CcuCfg.u.MaxTransactions),
            .AxiLookBits(CcuCfg.u.AxiIdLookupBits),
            .UniqueIds  (CcuCfg.u.AxiUniqueIds)
        ) u_ace_demux (
            .clk_i,
            .rst_ni,
            .test_i         (1'b0),
            .slv_req_i      (slv_req_cut[i]),
            .slv_resp_o     (slv_resp_cut[i]),
            .slv_aw_select_i(aw_is_nonblock),
            .slv_ar_select_i(ar_is_read_no_snoop),
            .mst_reqs_o     ({slv_nonblock_req[i], slv_block_req[i]}),
            .mst_resps_i    ({slv_nonblock_resp[i], slv_block_resp[i]}),
            .mst_b_idx_o    (b_idx[i]),
            .mst_r_idx_o    (r_idx[i])
        );
    end

    // Mux all non-blocking traffic into a single stream
    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(ccu_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (ccu_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(ccu_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (ccu_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (ccu_req_t),
        .mst_resp_t   (ccu_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_ace_nonblock_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i (slv_nonblock_req),
        .slv_resps_o(slv_nonblock_resp),
        .mst_req_o  (ccu_nonblock_req_o),
        .mst_resp_i (ccu_nonblock_resp_i)
    );

    // Mux all blocking traffic into a single stream
    axi_mux #(
        .SlvAxiIDWidth(CcuCfg.u.AxiSlvIdWidth),
        .slv_aw_chan_t(slv_aw_t),
        .mst_aw_chan_t(ccu_aw_t),
        .w_chan_t     (w_t),
        .slv_b_chan_t (slv_b_t),
        .mst_b_chan_t (ccu_b_t),
        .slv_ar_chan_t(slv_ar_t),
        .mst_ar_chan_t(ccu_ar_t),
        .slv_r_chan_t (slv_r_t),
        .mst_r_chan_t (ccu_r_t),
        .slv_req_t    (slv_req_t),
        .slv_resp_t   (slv_resp_t),
        .mst_req_t    (ccu_req_t),
        .mst_resp_t   (ccu_resp_t),
        .NoSlvPorts   (CcuCfg.u.SlvPorts),
        .MaxWTrans    (32'd8),
        .FallThrough  (1'b1),
        .SpillAw      (1'b0),
        .SpillW       (1'b0),
        .SpillB       (1'b0),
        .SpillAr      (1'b0),
        .SpillR       (1'b0)
    ) u_ace_block_mux (
        .clk_i,
        .rst_ni,
        .test_i     (1'b0),
        .slv_reqs_i (slv_block_req),
        .slv_resps_o(slv_block_resp),
        .mst_req_o  (ccu_block_req_o),
        .mst_resp_i (ccu_block_resp_i)
    );

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin : gen_xack_fifos
        logic r_tid_push, b_tid_push;

        assign r_tid_push = slv_resp_cut[i].r_valid && slv_req_cut[i].r_ready
                            && slv_resp_cut[i].r.last;
        assign b_tid_push = slv_resp_cut[i].b_valid && slv_req_cut[i].b_ready;

        stream_fifo #(
            .FALL_THROUGH(1'b0),
            .DEPTH       (CcuCfg.u.MaxTransactions),
            .DATA_WIDTH  (CcuCfg.TransactionIdWidth + 1)
        ) u_r_tid_fifo (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .usage_o   (),
            .data_i    ({ccu_block_r_tid_i, r_idx[i]}),
            .valid_i   (r_tid_push),
            .ready_o   (),
            .data_o    ({pos_r_tid[i], r_ignore[i]}),
            .valid_o   (),
            .ready_i   (slv_req_cut[i].rack)
        );

        stream_fifo #(
            .FALL_THROUGH(1'b0),
            .DEPTH       (CcuCfg.u.MaxTransactions),
            .DATA_WIDTH  (CcuCfg.TransactionIdWidth + 1)
        ) u_b_tid_fifo (
            .clk_i,
            .rst_ni,
            .flush_i   (1'b0),
            .testmode_i(1'b0),
            .usage_o   (),
            .data_i    ({ccu_block_b_tid_i, b_idx[i]}),
            .valid_i   (b_tid_push),
            .ready_o   (),
            .data_o    ({pos_b_tid[i], b_ignore[i]}),
            .valid_o   (),
            .ready_i   (slv_req_cut[i].wack)
        );
    end

    always_comb begin
        inflight_valid_r_clr_o = '0;
        inflight_valid_b_clr_o = '0;

        for (int unsigned i = 0; i < CcuCfg.u.SlvPorts; i++) begin
            if (slv_req_cut[i].rack && !r_ignore[i]) inflight_valid_r_clr_o[pos_r_tid[i]] = 1'b1;
            if (slv_req_cut[i].wack && !b_ignore[i]) inflight_valid_b_clr_o[pos_b_tid[i]] = 1'b1;
        end
    end


endmodule
