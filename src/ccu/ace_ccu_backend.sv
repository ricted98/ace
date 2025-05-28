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
`include "ace/convert.svh"

module ace_ccu_backend
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg    = '{default: '0},
    parameter type          ccu_ar_t  = logic,
    parameter type          ccu_aw_t  = logic,
    parameter type          w_t       = logic,
    parameter type          ccu_b_t   = logic,
    parameter type          ccu_r_t   = logic,
    parameter type          backend_t = logic,
    parameter type          cd_t      = logic,
    parameter type          cd_ctrl_t = logic,
    parameter type          tid_t     = logic
) (
    input  logic                             clk_i,
    input  logic                             rst_ni,
    // Piped signals from midend
    input  logic                             backend_valid_i,
    output logic                             backend_ready_o,
    input  backend_t                         backend_i,
    // CD snoop channel
    input  cd_t      [CcuCfg.u.SlvPorts-1:0] cd_i,
    input  logic     [CcuCfg.u.SlvPorts-1:0] cd_valid_i,
    output logic     [CcuCfg.u.SlvPorts-1:0] cd_ready_o,
    // Slave interface
    input  w_t                               w_i,
    input  logic                             w_valid_i,
    output logic                             w_ready_o,
    output ccu_r_t                           r_o,
    output tid_t                             r_tid_o,
    output logic                             r_valid_o,
    input  logic                             r_ready_i,
    output ccu_b_t                           b_o,
    output tid_t                             b_tid_o,
    output logic                             b_valid_o,
    input  logic                             b_ready_i,
    // Master interface
    output ccu_ar_t                          ar_o,
    output logic                             ar_valid_o,
    input  logic                             ar_ready_i,
    output ccu_aw_t                          aw_o,
    output logic                             aw_valid_o,
    input  logic                             aw_ready_i,
    output w_t                               w_o,
    output logic                             w_valid_o,
    input  logic                             w_ready_i,
    input  ccu_r_t                           r_i,
    input  logic                             r_valid_i,
    output logic                             r_ready_o,
    input  ccu_b_t                           b_i,
    input  logic                             b_valid_i,
    output logic                             b_ready_o
);

    // Typedefs
    typedef struct packed {
        logic is_write_back;
        tid_t tid;
    } resp_metadata_t;

    // Internal signals
    logic                                                      backend_stall;
    logic                                                      ax_id_hazard;

    logic                                                      write_valid;
    logic                                                      write_ready;
    logic                                                      read_valid;
    logic                                                      read_ready;

    logic                                                      cd_ctrl_reg_in_valid;
    logic                                                      cd_ctrl_reg_in_ready;
    cd_ctrl_t                                                  cd_ctrl_reg_in;
    logic           [CcuCfg.CachelineAxiTransfersIdxWidth-1:0] r_drop_threshold;
    logic                                                      cd_ctrl_reg_out_valid;
    logic                                                      cd_ctrl_reg_out_ready;
    cd_ctrl_t                                                  cd_ctrl_reg_out;
    logic                                                      cd_sel_write;
    logic                                                      cd_sel_read;
    logic                                                      cd_w_valid;
    logic                                                      cd_w_ready;
    w_t                                                        cd_w;
    logic                                                      cd_r_valid;
    logic                                                      cd_r_ready;
    ccu_r_t                                                    cd_r;

    logic                                                      r_drop_cnt_clr;
    logic                                                      r_drop_cnt_en;
    logic           [CcuCfg.CachelineAxiTransfersIdxWidth-1:0] r_drop_cnt;
    logic                                                      r_drop;

    logic                                                      r_len_cnt_clr;
    logic                                                      r_len_cnt_en;
    axi_pkg::len_t                                             r_len_cnt;
    logic                                                      r_last;
    logic                                                      r_done_d;
    logic                                                      r_done_q;

    ccu_r_t                                                    mem_r;
    logic                                                      r_is_mem;

    logic                                                      aw_write_back_done_d;
    logic                                                      aw_write_back_done_q;
    logic                                                      aw_is_write_back;
    logic                                                      aw_fork_in_valid;
    logic                                                      aw_fork_in_ready;

    logic                                                      w_ctrl_fifo_in_valid;
    logic                                                      w_ctrl_fifo_in_ready;
    logic                                                      w_ctrl_fifo_out_valid;
    logic                                                      w_ctrl_fifo_out_ready;
    logic                                                      w_is_write_back;
    logic                                                      w_mux_out_valid;
    logic                                                      w_mux_out_ready;
    w_t                                                        w_mux_out;

    logic                                                      cd_valid;
    logic                                                      cd_ready;
    cd_t                                                       cd;

    resp_metadata_t                                            aw_metadata;
    resp_metadata_t                                            ar_metadata;
    resp_metadata_t                                            r_metadata_out;
    resp_metadata_t                                            b_metadata_out;
    resp_metadata_t                                            r_metadata_in;
    logic           [                CcuCfg.AxiCcuIdWidth-1:0] r_metadata_id_in;
    resp_metadata_t                                            b_metadata_in;
    logic                                                      r_metadata_push;
    logic                                                      b_metadata_push;
    logic           [                CcuCfg.AxiCcuIdWidth-1:0] b_metadata_id_in;

    // ~> stall if an ID reordering hazard is detected
    // TODO: head of line stalling, optimize
    assign backend_stall = ax_id_hazard;

    stream_fork_dynamic #(
        .N_OUP(3)
    ) u_backend_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (backend_valid_i),
        .ready_o    (backend_ready_o),
        .sel_i      ({backend_i.aw_sel, backend_i.ar_sel, |backend_i.cd_sel}),
        .sel_valid_i(!backend_stall),
        .sel_ready_o(),
        .valid_o    ({write_valid, read_valid, cd_ctrl_reg_in_valid}),
        .ready_i    ({write_ready, read_ready, cd_ctrl_reg_in_ready})
    );

    //--------------------
    //  CD
    //--------------------

    if (CcuCfg.CachelineAxiTransfers == 1) begin : gen_r_drop_eqsize
        assign r_drop_threshold = '0;
    end else begin : gen_r_drop_diffsize
        assign r_drop_threshold =
            backend_i.ax.addr[CcuCfg.CachelineBytesIdxWidth-1:CcuCfg.AxiDataBytesIdxWidth];
    end

    assign cd_ctrl_reg_in = '{
            tid: backend_i.tid,
            id: backend_i.ax.id,
            r_len: backend_i.ax.len,
            // ~> number of AXI transfers to be skipped due to transfer being smaller than a cacheline
            r_drop:
            r_drop_threshold,
            r_resp_shared: backend_i.r_resp_shared,
            r_resp_dirty: backend_i.r_resp_dirty,
            r_user: backend_i.ax.user,
            cd_sel_bv: backend_i.cd_sel_bv,
            cd_sel: backend_i.cd_sel
        };

    fall_through_register #(
        .T(cd_ctrl_t)
    ) u_cd_ctrl_reg (
        .clk_i,
        .rst_ni,
        .clr_i     (1'b0),
        .testmode_i(1'b0),
        .data_i    (cd_ctrl_reg_in),
        .valid_i   (cd_ctrl_reg_in_valid),
        .ready_o   (cd_ctrl_reg_in_ready),
        .data_o    (cd_ctrl_reg_out),
        .valid_o   (cd_ctrl_reg_out_valid),
        .ready_i   (cd_ctrl_reg_out_ready)
    );

    ace_ccu_cd_arbiter #(
        .CcuCfg(CcuCfg),
        .cd_t  (cd_t)
    ) u_cd_merge (
        .clk_i,
        .rst_ni,
        .cd_valid_i    (cd_valid_i),
        .cd_ready_o    (cd_ready_o),
        .cd_i          (cd_i),
        .cd_sel_valid_i(cd_ctrl_reg_out_valid),
        .cd_sel_ready_o(cd_ctrl_reg_out_ready),
        .cd_sel_bv_i   (cd_ctrl_reg_out.cd_sel_bv),
        .cd_valid_o    (cd_valid),
        .cd_ready_i    (cd_ready),
        .cd_o          (cd)
    );

    assign cd_sel_write = cd_ctrl_reg_out.cd_sel.write;

    assign cd_sel_read = cd_ctrl_reg_out.cd_sel.read &&
        // ~> drop the first transfers due to misaligned address
        !r_drop &&
        // ~> drop remaining transfers due to reduced transfer len
        !r_done_q;

    stream_fork_dynamic #(
        .N_OUP(2)
    ) u_cd_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (cd_valid),
        .ready_o    (cd_ready),
        .sel_i      ({cd_sel_write, cd_sel_read}),
        .sel_valid_i('1),
        .sel_ready_o(),
        .valid_o    ({cd_w_valid, cd_r_valid}),
        .ready_i    ({cd_w_ready, cd_r_ready})
    );

    counter #(
        .WIDTH(CcuCfg.CachelineAxiTransfersIdxWidth)
    ) u_r_drop_counter (
        .clk_i,
        .rst_ni,
        .clear_i   (r_drop_cnt_clr),
        .en_i      (r_drop_cnt_en),
        .load_i    (1'b0),
        .down_i    (1'b0),
        .d_i       ('0),
        .q_o       (r_drop_cnt),
        .overflow_o()
    );

    counter #(
        .WIDTH($bits(axi_pkg::len_t))
    ) u_r_len_counter (
        .clk_i,
        .rst_ni,
        .clear_i   (r_len_cnt_clr),
        .en_i      (r_len_cnt_en),
        .load_i    ('0),
        .down_i    ('0),
        .d_i       ('0),
        .q_o       (r_len_cnt),
        .overflow_o()
    );

    assign r_drop         = r_drop_cnt != cd_ctrl_reg_out.r_drop;
    assign r_drop_cnt_en  = cd_valid && cd_ready && r_drop;
    assign r_drop_cnt_clr = cd_valid && cd_ready && cd.last;

    assign r_last         = r_len_cnt == cd_ctrl_reg_out.r_len;
    assign r_len_cnt_en   = cd_r_valid && cd_r_ready;
    assign r_len_cnt_clr  = cd_valid && cd_ready && cd.last;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) r_done_q <= 1'b0;
        else r_done_q <= r_done_d;
    end

    assign r_done_d = !r_len_cnt_clr && ((r_last && r_len_cnt_en) || r_done_q);

    assign cd_r = '{
            id: cd_ctrl_reg_out.id,
            data: cd.data,
            resp: {cd_ctrl_reg_out.r_resp_shared, cd_ctrl_reg_out.r_resp_dirty, 2'b0},
            last: cd.last,
            user: cd_ctrl_reg_out.r_user
        };

    assign cd_w = '{data: cd.data, strb: '1, last: cd.last, user: '0};

    //--------------------
    //  AR
    //--------------------

    assign ar_valid_o = read_valid;
    assign read_ready = ar_ready_i;

    assign ar_metadata = {1'b0, backend_i.tid};

    always_comb begin
        ar_o = '0;
        `AXI_SET_AR_STRUCT(ar_o, backend_i.ax)
    end

    // AR demuxing
    if (CcuCfg.u.AxiUniqueIds) begin : gen_axi_unique_ids

        assign ax_id_hazard = 1'b0;

    end else begin : gen_no_axi_unique_ids

        logic                                aw_atop_r_resp;
        logic [CcuCfg.u.AxiIdLookupBits-1:0] ax_id_lookup;
        logic [     CcuCfg.ArIdCounters-1:0] ax_id_lookup_onehot;
        logic [CcuCfg.u.AxiIdLookupBits-1:0] r_id_lookup;
        logic [     CcuCfg.ArIdCounters-1:0] r_id_lookup_onehot;
        logic [     CcuCfg.ArIdCounters-1:0] ax_id_hazard_onehot;

        assign aw_atop_r_resp = backend_i.ax.atop[axi_pkg::ATOP_R_RESP];

        assign ax_id_lookup = backend_i.ax.id[CcuCfg.AxiCcuIdWidth-1-:CcuCfg.u.AxiIdLookupBits];
        assign ax_id_lookup_onehot = CcuCfg.ArIdCounters'(1) << ax_id_lookup;
        assign ax_id_hazard = ax_id_hazard_onehot[ax_id_lookup];

        assign r_id_lookup = r_o.id[CcuCfg.AxiCcuIdWidth-1-:CcuCfg.u.AxiIdLookupBits];
        assign r_id_lookup_onehot = CcuCfg.ArIdCounters'(1) << r_id_lookup;

        for (genvar i = 0; i < CcuCfg.ArIdCounters; i++) begin : gen_r_id_counter

            logic is_cd_d, is_cd_q;
            logic credit_give;
            logic credit_take;
            logic credit_left;
            logic credit_full;

            assign is_cd_d = credit_full && credit_take ? backend_i.cd_sel.read : is_cd_q;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    is_cd_q <= 1'b0;
                end else begin
                    is_cd_q <= is_cd_d;
                end
            end

            credit_counter #(
                .NumCredits     (CcuCfg.u.MaxTransactions),
                .InitCreditEmpty(1'b0)
            ) u_credit_counter (
                .clk_i,
                .rst_ni,
                .credit_o     (),
                .credit_give_i(credit_give),
                .credit_take_i(credit_take),
                .credit_init_i(1'b0),
                .credit_left_o(credit_left),
                .credit_crit_o(),
                .credit_full_o(credit_full)
            );

            // Take a credit upon a regular read transaction or when an ATOP AW transaction generates also a response on the R channel
            assign credit_take = backend_valid_i && backend_ready_o && ax_id_lookup_onehot[i]
                                && (!backend_i.ax_is_write || aw_atop_r_resp);
            assign credit_give = r_valid_o && r_ready_i && r_o.last && r_id_lookup_onehot[i];

            assign ax_id_hazard_onehot[i] = |{
                // ~> no credits left for this ID
                !credit_left,
                // ~> inflight memory transactions with the same ID but different responders
                !credit_full && (is_cd_q != backend_i.cd_sel.read)};
        end
    end

    //--------------------
    //  R
    //--------------------

    `AXI_TO_ACE_ASSIGN_R_STRUCT(mem_r, r_i)

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (ccu_r_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b1)
    ) u_r_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   (1'b0),
        .req_i  ({r_valid_i, cd_r_valid}),
        .gnt_o  ({r_ready_o, cd_r_ready}),
        .data_i ({mem_r, cd_r}),
        .req_o  (r_valid_o),
        .gnt_i  (r_ready_i),
        .data_o (r_o),
        .idx_o  (r_is_mem)
    );

    assign r_tid_o = r_is_mem ? r_metadata_out.tid : cd_ctrl_reg_out.tid;

    //--------------------
    //  AW
    //--------------------

    always_comb begin
        aw_write_back_done_d = aw_write_back_done_q;
        aw_is_write_back     = 1'b0;

        aw_fork_in_valid     = write_valid;
        write_ready          = aw_fork_in_ready;

        if (!backend_i.cd_sel.write) begin
            // no write back is expected
            // ~> allow vld/rdy passthrough
        end else if (!aw_write_back_done_q) begin
            // a write back is pending
            // ~> send the AW/W transaction to memory
            aw_is_write_back = 1'b1;
            if (aw_fork_in_valid && aw_fork_in_ready) begin
                // The write back is done
                if (backend_i.ax_is_write) begin
                    // a write is also pending
                    // ~> mask the ready return signal
                    write_ready          = 1'b0;
                    // ~> set the status flag
                    aw_write_back_done_d = 1'b1;
                end
            end
        end else begin
            // the write back is done
            // a write is still pending
            // ~> allow vld/rdy passthrough
            if (aw_fork_in_valid && aw_fork_in_ready) begin
                // The write is done
                // ~> clear the status flag
                aw_write_back_done_d = 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_write_back_done_q <= 1'b0;
        end else begin
            aw_write_back_done_q <= aw_write_back_done_d;
        end
    end

    assign aw_metadata = '{is_write_back: aw_is_write_back, tid: backend_i.tid};

    always_comb begin
        aw_o = '0;
        `AXI_SET_AW_STRUCT(aw_o, backend_i.ax)

        if (aw_is_write_back) begin
            // AW transaction is a write back
            // ~> pass a full cacheline
            aw_o.addr  = axi_pkg::aligned_addr(backend_i.ax.addr, CcuCfg.CachelineBytesIdxWidth);
            aw_o.len   = CcuCfg.CachelineAxiTransfers - 1;
            aw_o.size  = CcuCfg.AxiDataBytesIdxWidth;
            // ~> burst type for write backs
            aw_o.burst = axi_pkg::BURST_WRAP;
            // ~> the write back is not atomic
            aw_o.lock  = 1'b0;
            aw_o.atop  = '0;
        end
    end

    stream_fork #(
        .N_OUP(2)
    ) u_aw_fork (
        .clk_i,
        .rst_ni,
        .valid_i(aw_fork_in_valid),
        .ready_o(aw_fork_in_ready),
        .valid_o({aw_valid_o, w_ctrl_fifo_in_valid}),
        .ready_i({aw_ready_i, w_ctrl_fifo_in_ready})
    );

    //--------------------
    //  W
    //--------------------

    stream_fifo #(
        .FALL_THROUGH(1'b1),
        .DATA_WIDTH  (1),
        .DEPTH       (2)
    ) u_w_ctrl_fifo (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .usage_o   (),
        .data_i    (aw_is_write_back),
        .valid_i   (w_ctrl_fifo_in_valid),
        .ready_o   (w_ctrl_fifo_in_ready),
        .data_o    (w_is_write_back),
        .valid_o   (w_ctrl_fifo_out_valid),
        .ready_i   (w_ctrl_fifo_out_ready && w_o.last)
    );

    stream_mux #(
        .DATA_T(w_t),
        .N_INP (2)
    ) u_w_mux (
        .inp_data_i ({cd_w, w_i}),
        .inp_valid_i({cd_w_valid, w_valid_i}),
        .inp_ready_o({cd_w_ready, w_ready_o}),
        .inp_sel_i  (w_is_write_back),
        .oup_data_o (w_mux_out),
        .oup_valid_o(w_mux_out_valid),
        .oup_ready_i(w_mux_out_ready)
    );

    stream_join #(
        .N_INP(2)
    ) u_w_join (
        .inp_valid_i({w_ctrl_fifo_out_valid, w_mux_out_valid}),
        .inp_ready_o({w_ctrl_fifo_out_ready, w_mux_out_ready}),
        .oup_valid_o(w_valid_o),
        .oup_ready_i(w_ready_i)
    );

    `AXI_ASSIGN_W_STRUCT(w_o, w_mux_out)

    //--------------------
    //  B
    //--------------------

    stream_filter u_b_filter (
        .valid_i(b_valid_i),
        .ready_o(b_ready_o),
        .drop_i (b_metadata_out.is_write_back),
        .valid_o(b_valid_o),
        .ready_i(b_ready_i)
    );

    `AXI_ASSIGN_B_STRUCT(b_o, b_i)

    assign b_tid_o = b_metadata_out.tid;

    //--------------------
    //  Metadata queues
    //--------------------

    // Metadata contains information useful for conflict management
    // and response routing
    // - TID
    // - is write back, i.e. the CCU issued the transaction

    always_comb begin : comb_r_metadata_in_mux
        // Regular AR operations
        // ~> use AR metadata
        r_metadata_in    = ar_metadata;
        // ~> use AR handshake to push metadata
        r_metadata_push  = ar_valid_o && ar_ready_i;
        // ~> use AR id to tag metadata
        r_metadata_id_in = ar_o.id;

        if (backend_i.ax_is_write && backend_i.ax.atop[axi_pkg::ATOP_R_RESP]) begin
            // ATOP injection
            // ~> use AW metadata
            r_metadata_in    = b_metadata_in;
            // ~> use AW handshake to push metadata
            r_metadata_push  = b_metadata_push;
            // ~> use AW id to tag metadata
            r_metadata_id_in = b_metadata_id_in;
        end
    end

    id_queue #(
        .ID_WIDTH           (CcuCfg.AxiCcuIdWidth),
        .CAPACITY           (CcuCfg.u.MaxTransactions),
        .FULL_BW            (1'b1),
        .CUT_OUP_POP_INP_GNT(1'b1),
        .data_t             (resp_metadata_t)
    ) u_r_metadata_queue (
        .clk_i,
        .rst_ni,
        .inp_id_i        (r_metadata_id_in),
        .inp_data_i      (r_metadata_in),
        .inp_req_i       (r_metadata_push),
        .inp_gnt_o       (),
        .exists_data_i   ('0),
        .exists_mask_i   ('0),
        .exists_req_i    ('0),
        .exists_o        (),
        .exists_gnt_o    (),
        .oup_id_i        (r_i.id),
        .oup_pop_i       (r_ready_o && r_i.last),
        .oup_req_i       (r_valid_i),
        .oup_data_o      (r_metadata_out),
        .oup_data_valid_o(),
        .oup_gnt_o       ()
    );

    assign b_metadata_push  = aw_valid_o && aw_ready_i;
    assign b_metadata_in    = aw_metadata;
    assign b_metadata_id_in = aw_o.id;

    id_queue #(
        .ID_WIDTH           (CcuCfg.AxiCcuIdWidth),
        .CAPACITY           (CcuCfg.u.MaxTransactions),
        .FULL_BW            (1'b1),
        .CUT_OUP_POP_INP_GNT(1'b1),
        .data_t             (resp_metadata_t)
    ) u_w_metadata_queue (
        .clk_i,
        .rst_ni,
        .inp_id_i        (b_metadata_id_in),
        .inp_data_i      (b_metadata_in),
        .inp_req_i       (b_metadata_push),
        .inp_gnt_o       (),
        .exists_data_i   ('0),
        .exists_mask_i   ('0),
        .exists_req_i    ('0),
        .exists_o        (),
        .exists_gnt_o    (),
        .oup_id_i        (b_i.id),
        .oup_pop_i       (b_ready_o),
        .oup_req_i       (b_valid_i),
        .oup_data_o      (b_metadata_out),
        .oup_data_valid_o(),
        .oup_gnt_o       ()
    );
endmodule
