module ccu_mem_ctrl import ace_pkg::*; #(
    parameter int unsigned AxiIdWidth = 0,
    parameter type req_t = logic,
    parameter type resp_t = logic,
    parameter type aw_chan_t = logic,
    parameter type w_chan_t = logic
)(
    input clk_i,
    input rst_ni,
    input req_t wr_mst_req_i,
    output resp_t wr_mst_resp_o,
    input req_t r_mst_req_i,
    output resp_t r_mst_resp_o,
    output req_t mst_req_o,
    input resp_t mst_resp_i
);

localparam int unsigned FIFO_DEPTH = 4;

logic w_select, w_fifo_push, w_fifo_pop, w_fifo_empty, w_fifo_full;
logic w_select_fifo;
logic [$clog2(FIFO_DEPTH)-1:0] w_fifo_usage;
logic w_valid, w_ready;
logic aw_lock_d, aw_lock_q;
req_t mst_req;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
        aw_lock_q <= 1'b0;
    end else begin
        aw_lock_q <= aw_lock_d;
    end
end

// Index 0 - W FSM
// Index 1 - R FSM

// AW Channel
stream_arbiter #(
    .DATA_T(aw_chan_t),
    .N_INP (2)
) i_stream_arbiter_aw (
    .clk_i,
    .rst_ni,
    .inp_data_i ({r_mst_req_i.aw, wr_mst_req_i.aw}),
    .inp_valid_i({r_mst_req_i.aw_valid, wr_mst_req_i.aw_valid}),
    .inp_ready_o({r_mst_resp_o.aw_ready, wr_mst_resp_o.aw_ready}),
    .oup_data_o (mst_req.aw),
    .oup_valid_o(mst_req.aw_valid),
    .oup_ready_i(mst_resp_i.aw_ready)
);

// AR Channel (W-FSM cannot generate AR requests)
assign mst_req.ar            = r_mst_req_i.ar;
assign mst_req.ar_valid      = r_mst_req_i.ar_valid;
assign r_mst_resp_o.ar_ready = mst_resp_i.ar_ready;

// ID Prepending
// Ensure that restrictive accesses get the same ID
always_comb begin
    mst_req_o.aw = mst_req.aw;
    mst_req_o.ar = mst_req.ar;
    if (mst_req.aw.lock) begin
        mst_req_o.aw.id = {2'b00, mst_req.aw.id[AxiIdWidth-1:0]};
    end else begin
        mst_req_o.aw.id = {!w_select, w_select, mst_req.aw.id[AxiIdWidth-1:0]};
    end
    if (mst_req.ar.lock) begin
        mst_req_o.ar.id = {2'b00, mst_req.ar.id[AxiIdWidth-1:0]};
    end else begin
        mst_req_o.ar.id = {2'b01, mst_req.ar.id[AxiIdWidth-1:0]};
    end
end

// W Channel
stream_mux #(
    .DATA_T(w_chan_t),
    .N_INP (2)
) i_stream_mux_w (
    .inp_data_i ({r_mst_req_i.w, wr_mst_req_i.w}),
    .inp_valid_i({r_mst_req_i.w_valid, wr_mst_req_i.w_valid}),
    .inp_ready_o({r_mst_resp_o.w_ready, wr_mst_resp_o.w_ready}),
    .inp_sel_i  (w_select_fifo),
    .oup_data_o (mst_req_o.w),
    .oup_valid_o(w_valid),
    .oup_ready_i(w_ready)
);

// W index
fifo_v3 #(
    .FALL_THROUGH   (1'b1),
    .DATA_WIDTH     (1),
    .DEPTH          (FIFO_DEPTH)
) i_w_cmd_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (w_fifo_full),
    .empty_o    (),
    .usage_o    (w_fifo_usage),
    .data_i     (w_select),
    .push_i     (w_fifo_push),
    .data_o     (w_select_fifo),
    .pop_i      (w_fifo_pop)
);

assign w_select    = r_mst_req_i.aw_valid && r_mst_resp_o.aw_ready;
assign w_fifo_push = ~aw_lock_q && mst_req_o.aw_valid;
assign w_fifo_pop  = mst_req_o.w_valid && mst_resp_i.w_ready && mst_req_o.w.last;
assign aw_lock_d   = ~mst_resp_i.aw_ready && (mst_req_o.aw_valid || aw_lock_q);

assign w_fifo_empty = w_fifo_usage == 0 && !w_fifo_full;

// Block handshake if fifo empty
assign mst_req_o.w_valid = w_valid            && !w_fifo_empty;
assign w_ready           = mst_resp_i.w_ready && !w_fifo_empty;

// B Channel
assign r_mst_resp_o.b  = mst_resp_i.b;
assign wr_mst_resp_o.b = mst_resp_i.b;
always_comb begin
    if (mst_resp_i.b.id[AxiIdWidth+1:AxiIdWidth] == 2'b01) begin
        r_mst_resp_o.b_valid = mst_resp_i.b_valid;
        mst_req_o.b_ready    = r_mst_req_i.b_ready;
    end
    else begin
        wr_mst_resp_o.b_valid = mst_resp_i.b_valid;
        mst_req_o.b_ready     = wr_mst_req_i.b_ready;
    end
end

// R Channel
assign r_mst_resp_o.r  = mst_resp_i.r;
assign wr_mst_resp_o.r = mst_resp_i.r;
always_comb begin
    if (mst_resp_i.r.id[AxiIdWidth+1:AxiIdWidth] == 2'b10) begin
        wr_mst_resp_o.r_valid = mst_resp_i.r_valid;
        mst_req_o.r_ready     = wr_mst_req_i.r_ready;
    end
    else begin
        r_mst_resp_o.r_valid = mst_resp_i.r_valid;
        mst_req_o.r_ready    = r_mst_req_i.r_ready;
    end
end

endmodule
