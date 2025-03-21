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
// Memory controller
// Mux the two AW channel and keep locked until last W beat
// Add two bits to the ID to encode where response should be routed
// RID: 10 -> W FSM, else R FSM
// BID: 01 -> R FSM, else W FSM
// 00 is used for LR/SC sequence, where AWID and ARID must be the same
module ccu_mem_ctrl import ace_pkg::*; import ccu_pkg::*; #(
    parameter ccu_cfg_t CcuCfg   = '{default: '0},
    parameter type slv_req_t     = logic,
    parameter type slv_resp_t    = logic,
    parameter type mst_req_t     = logic,
    parameter type mst_resp_t    = logic,
    parameter type slv_ar_chan_t = logic,
    parameter type slv_r_chan_t  = logic,
    parameter type slv_aw_chan_t = logic,
    parameter type w_chan_t      = logic,
    parameter type slv_b_chan_t  = logic,
    parameter type mst_ar_chan_t = logic,
    parameter type mst_r_chan_t  = logic,
    parameter type mst_aw_chan_t = logic,
    parameter type mst_b_chan_t  = logic
)(
    input             clk_i,
    input             rst_ni,
    /// AXI request from W FSM
    input  slv_req_t  wr_slv_req_i,
    /// AXI response to W FSM
    output slv_resp_t wr_slv_resp_o,
    /// AXI request from R FSM
    input  slv_req_t  r_slv_req_i,
    /// AXI response to R FSM
    output slv_resp_t r_slv_resp_o,
    /// AXI request to main memory
    output mst_req_t  mst_req_o,
    /// AXI response from main memory
    input  mst_resp_t mst_resp_i,
    /// AW is write-back
    input  logic wr_slv_aw_wb_i,
    /// B is write-back
    output logic wr_slv_b_wb_o
);

localparam int unsigned FIFO_DEPTH = 4;

typedef enum logic [1:0] {
    MEM_ID_EXCL  = 2'b00,
    MEM_ID_R     = 2'b01,
    MEM_ID_WR    = 2'b10,
    MEM_ID_WR_WB = 2'b11
} mem_id_e;

slv_ar_chan_t r_slv_ar;
logic         r_slv_ar_valid, r_slv_ar_ready;

mst_ar_chan_t mst_ar;
logic         mst_ar_valid, mst_ar_ready;
mem_id_e      mst_ar_id_prefix;

mst_r_chan_t  mst_r;
logic         mst_r_valid, mst_r_ready;
// slv_r_chan_t  r_slv_r;
logic         r_slv_r_valid, r_slv_r_ready;
// slv_r_chan_t  wr_slv_r;
logic         wr_slv_r_valid, wr_slv_r_ready;
logic         slv_r_sel;

mst_aw_chan_t mst_aw;
logic         mst_aw_valid, mst_aw_ready;
mem_id_e      mst_aw_id_prefix;
slv_aw_chan_t slv_aw;
logic         slv_aw_valid, slv_aw_ready;
slv_aw_chan_t r_slv_aw;
logic         r_slv_aw_valid, r_slv_aw_ready;
slv_aw_chan_t wr_slv_aw;
logic         wr_slv_aw_valid, wr_slv_aw_ready;

w_chan_t      mst_w;
logic         mst_w_valid, mst_w_ready;
w_chan_t      r_slv_w;
logic         r_slv_w_valid, r_slv_w_ready;
w_chan_t      wr_slv_w;
logic         wr_slv_w_valid, wr_slv_w_ready;

mst_b_chan_t mst_b;
logic        mst_b_valid, mst_b_ready;
// slv_b_chan_t r_slv_b;
logic        r_slv_b_valid, r_slv_b_ready;
// slv_b_chan_t wr_slv_b;
logic        wr_slv_b_valid, wr_slv_b_ready;
logic        slv_b_sel;

logic slv_w_sel_fifo_in;
logic slv_w_sel_fifo_valid_in, slv_w_sel_fifo_ready_in;
logic slv_w_sel_fifo_out;
logic slv_w_sel_fifo_valid_out, slv_w_sel_fifo_ready_out;

// AR channel
assign mst_ar_valid     = r_slv_ar_valid;
assign r_slv_ar_ready   = mst_ar_ready;
assign mst_ar_id_prefix = r_slv_ar.lock ? MEM_ID_EXCL : MEM_ID_R;

// ID Prepending
// Ensure that restrictive accesses get the same ID
always_comb begin
    `AXI_SET_AR_STRUCT(mst_ar, r_slv_ar)
    mst_ar.id = {mst_ar_id_prefix, r_slv_ar.id[CcuCfg.AxiPostMuxIdWidth-1:0]};
end

// AW Channel
rr_arb_tree #(
    .NumIn      (2),
    .DataType   (slv_aw_chan_t),
    .ExtPrio    (1'b0),
    .AxiVldRdy  (1'b1),
    .LockIn     (1'b1)
) i_arbiter (
    .clk_i,
    .rst_ni,
    .flush_i ('0),
    .rr_i    ('0),
    .req_i   ({r_slv_aw_valid, wr_slv_aw_valid}),
    .gnt_o   ({r_slv_aw_ready, wr_slv_aw_ready}),
    .data_i  ({r_slv_aw, wr_slv_aw}),
    .req_o   (slv_aw_valid),
    .gnt_i   (slv_aw_ready),
    .data_o  (slv_aw),
    .idx_o   (slv_w_sel_fifo_in)
);

stream_fork #(
    .N_OUP (2)
) i_mst_aw_fork (
    .clk_i,
    .rst_ni,
    .valid_i (slv_aw_valid),
    .ready_o (slv_aw_ready),
    .valid_o ({mst_aw_valid, slv_w_sel_fifo_valid_in}),
    .ready_i ({mst_aw_ready, slv_w_sel_fifo_ready_in})
);

// ID Prepending
// Ensure that restrictive accesses get the same ID
assign mst_aw_id_prefix = slv_aw.lock       ? MEM_ID_EXCL  :
                          slv_w_sel_fifo_in ? MEM_ID_R     :
                          wr_slv_aw_wb_i    ? MEM_ID_WR_WB :
                                              MEM_ID_WR;

always_comb begin
    `AXI_SET_AW_STRUCT(mst_aw, slv_aw)
    mst_aw.id = {mst_aw_id_prefix, slv_aw.id[CcuCfg.AxiPostMuxIdWidth-1:0]};
end

// W Channel
// Index 0 - W FSM
// Index 1 - R FSM
stream_mux #(
    .DATA_T (w_chan_t),
    .N_INP  (2)
) i_slv_mux_w (
    .inp_data_i  ({r_slv_w, wr_slv_w}),
    .inp_valid_i ({r_slv_w_valid, wr_slv_w_valid}),
    .inp_ready_o ({r_slv_w_ready, wr_slv_w_ready}),
    .inp_sel_i   (slv_w_sel_fifo_out),
    .oup_data_o  (mst_w),
    .oup_valid_o (slv_w_valid),
    .oup_ready_i (slv_w_ready)
);

// W index
stream_fifo #(
    .FALL_THROUGH   (1'b1),
    .DATA_WIDTH     (1),
    .DEPTH          (FIFO_DEPTH)
) i_slv_w_sel_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .usage_o    (),
    .data_i     (slv_w_sel_fifo_in),
    .valid_i    (slv_w_sel_fifo_valid_in),
    .ready_o    (slv_w_sel_fifo_ready_in),
    .data_o     (slv_w_sel_fifo_out),
    .valid_o    (slv_w_sel_fifo_valid_out),
    .ready_i    (slv_w_sel_fifo_ready_out && mst_w.last)
);

stream_join #(
  .N_INP (2)
) i_mst_w_join (
    .inp_valid_i ({slv_w_valid, slv_w_sel_fifo_valid_out}),
    .inp_ready_o ({slv_w_ready, slv_w_sel_fifo_ready_out}),
    .oup_valid_o (mst_w_valid),
    .oup_ready_i (mst_w_ready)
);

// B Channel demuxing
assign slv_b_sel     = mem_id_e'(mst_b.id[CcuCfg.AxiPostMuxIdWidth+:2]) ==  MEM_ID_R;
assign wr_slv_b_wb_o = mem_id_e'(mst_b.id[CcuCfg.AxiPostMuxIdWidth+:2]) ==  MEM_ID_WR_WB;

stream_demux #(
  .N_OUP (2)
) i_b_demux (
  .inp_valid_i (mst_b_valid),
  .inp_ready_o (mst_b_ready),
  .oup_sel_i   (slv_b_sel),
  .oup_valid_o ({r_slv_b_valid, wr_slv_b_valid}),
  .oup_ready_i ({r_slv_b_ready, wr_slv_b_ready})
);

// R Channel demuxing
assign slv_r_sel = mem_id_e'(mst_r.id[CcuCfg.AxiPostMuxIdWidth+:2]) !=  MEM_ID_WR;

stream_demux #(
  .N_OUP (2)
) i_r_demux (
  .inp_valid_i (mst_r_valid),
  .inp_ready_o (mst_r_ready),
  .oup_sel_i   (slv_r_sel),
  .oup_valid_o ({r_slv_r_valid, wr_slv_r_valid}),
  .oup_ready_i ({r_slv_r_ready, wr_slv_r_ready})
);

//////////////
// Channels //
//////////////

/* SLV INTF */
// R slv
// AR
`AXI_ASSIGN_AR_STRUCT(r_slv_ar, r_slv_req_i.ar)
assign r_slv_ar_valid         = r_slv_req_i.ar_valid;
assign r_slv_resp_o.ar_ready  = r_slv_ar_ready;

// R
`AXI_ASSIGN_R_STRUCT(r_slv_resp_o.r, mst_r)
assign r_slv_resp_o.r_valid = r_slv_r_valid;
assign r_slv_r_ready        = r_slv_req_i.r_ready;

// AW
`AXI_ASSIGN_AW_STRUCT(r_slv_aw, r_slv_req_i.aw)
assign r_slv_aw_valid        = r_slv_req_i.aw_valid;
assign r_slv_resp_o.aw_ready = r_slv_aw_ready;

// W
`AXI_ASSIGN_W_STRUCT(r_slv_w, r_slv_req_i.w)
assign r_slv_w_valid        = r_slv_req_i.w_valid;
assign r_slv_resp_o.w_ready = r_slv_w_ready;

// B
`AXI_ASSIGN_B_STRUCT(r_slv_resp_o.b, mst_b)
assign r_slv_resp_o.b_valid = r_slv_b_valid;
assign r_slv_b_ready        = r_slv_req_i.b_ready;

// W slv
// AR
assign wr_slv_resp_o.ar_ready = 1'b0;

// R
`AXI_ASSIGN_R_STRUCT(wr_slv_resp_o.r, mst_r)
assign wr_slv_resp_o.r_valid = wr_slv_r_valid;
assign wr_slv_r_ready        = wr_slv_req_i.r_ready;

// AW
`AXI_ASSIGN_AW_STRUCT(wr_slv_aw, wr_slv_req_i.aw)
assign wr_slv_aw_valid        = wr_slv_req_i.aw_valid;
assign wr_slv_resp_o.aw_ready = wr_slv_aw_ready;

// W
`AXI_ASSIGN_W_STRUCT(wr_slv_w, wr_slv_req_i.w)
assign wr_slv_w_valid        = wr_slv_req_i.w_valid;
assign wr_slv_resp_o.w_ready = wr_slv_w_ready;

// B
`AXI_ASSIGN_B_STRUCT(wr_slv_resp_o.b, mst_b)
assign wr_slv_resp_o.b_valid = wr_slv_b_valid;
assign wr_slv_b_ready        = wr_slv_req_i.b_ready;

/* MST INTF */
// AR
`AXI_ASSIGN_AR_STRUCT(mst_req_o.ar, mst_ar)
assign mst_req_o.ar_valid = mst_ar_valid;
assign mst_ar_ready       = mst_resp_i.ar_ready;

// R
`AXI_ASSIGN_R_STRUCT(mst_r, mst_resp_i.r)
assign mst_r_valid       = mst_resp_i.r_valid;
assign mst_req_o.r_ready = mst_r_ready;

// AW
`AXI_ASSIGN_AW_STRUCT(mst_req_o.aw, mst_aw)
assign mst_req_o.aw_valid = mst_aw_valid;
assign mst_aw_ready       = mst_resp_i.aw_ready;

// W
`AXI_ASSIGN_W_STRUCT(mst_req_o.w, mst_w)
assign mst_req_o.w_valid = mst_w_valid;
assign mst_w_ready       = mst_resp_i.w_ready;

// B
`AXI_ASSIGN_B_STRUCT(mst_b, mst_resp_i.b)
assign mst_b_valid       = mst_resp_i.b_valid;
assign mst_req_o.b_ready = mst_b_ready;

// pragma translate_off
`ifndef VERILATOR
initial begin : b_assert
    assert(($bits(mst_req_o.aw.id) - $bits(r_slv_req_i.aw.id)) == 2)
        else $fatal(1, "Difference in AW ID widths should be 2");
    assert(($bits(mst_req_o.ar.id) - $bits(r_slv_req_i.ar.id)) == 2)
        else $fatal(1, "Difference in AR ID widths should be 2");
end
`endif
// pragma translate_on

endmodule
