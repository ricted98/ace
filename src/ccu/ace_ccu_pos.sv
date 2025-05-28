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

module ace_ccu_pos
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg        = '{default: '0},
    parameter type          domain_rule_t = logic,
    parameter type          ccu_aw_t      = logic,
    parameter type          ccu_ar_t      = logic,
    parameter type          ccu_ax_t      = logic,
    parameter type          ac_t          = logic,
    parameter type          midend_t      = logic,
    parameter type          tid_t         = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // PoS <-> Snoop
    output ac_t  [CcuCfg.u.SlvPorts-1:0] ac_o,
    output logic [CcuCfg.u.SlvPorts-1:0] ac_valid_o,
    input  logic [CcuCfg.u.SlvPorts-1:0] ac_ready_i,

    // Frontend <-> PoS
    input  ccu_aw_t aw_block_i,
    input  logic    aw_block_valid_i,
    output logic    aw_block_ready_o,
    input  ccu_ar_t ar_block_i,
    input  logic    ar_block_valid_i,
    output logic    ar_block_ready_o,

    input domain_rule_t [CcuCfg.u.SlvPorts-1:0] domain_rule_i,

    // PoS <-> Blocking Pipe
    output midend_t midend_o,
    output logic    midend_valid_o,
    input  logic    midend_ready_i,

    // PoS <-> Response path
    input logic [CcuCfg.u.MaxTransactions-1:0] inflight_valid_b_clr_i,
    input logic [CcuCfg.u.MaxTransactions-1:0] inflight_valid_r_clr_i
);
    // Typedefs
    typedef logic [CcuCfg.CachelineAddrWidth-1:0] cacheline_addr_t;

    // Internal signals
    ccu_ax_t                                        aw_block;
    ccu_ax_t                                        ar_block;

    logic                                           aw_snooping;
    acsnoop_t                                       aw_acsnoop;
    logic                                           ar_snooping;
    acsnoop_t                                       ar_acsnoop;
    logic                                           ar_accepts_dirty;
    logic                                           ar_accepts_dirty_shared;
    logic                                           ar_accepts_shared;

    logic                                           ax_block_valid;
    logic                                           ax_block_ready;
    logic                                           ax_block_is_write;

    logic                                           ax_block_snooping;
    acsnoop_t                                       ax_block_acsnoop;
    axdomain_t                                      ax_block_domain;
    logic                                           ax_block_stall;
    ccu_ax_t                                        ax_block;

    logic            [  CcuCfg.SlvPortIdxWidth-1:0] slv_idx;

    logic            [       CcuCfg.u.SlvPorts-1:0] ac_sel_bv;

    logic                                           midend_valid;
    logic                                           midend_ready;
    midend_t                                        midend_d;


    logic                                           tid_pop;
    logic                                           tid_push;
    logic                                           tid_list_empty;

    logic            [CcuCfg.u.MaxTransactions-1:0] tid_push_d;
    logic            [CcuCfg.u.MaxTransactions-1:0] tid_push_q;
    logic            [CcuCfg.u.MaxTransactions-1:0] tid_push_set;
    logic            [CcuCfg.u.MaxTransactions-1:0] tid_push_clr;

    tid_t                                           ax_block_tid;
    tid_t                                           arb_tid;


    cacheline_addr_t [CcuCfg.u.MaxTransactions-1:0] inflight_addr_q;
    cacheline_addr_t [CcuCfg.u.MaxTransactions-1:0] inflight_addr_d;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_b_q;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_b_d;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_b_set;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_r_q;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_r_d;
    logic            [CcuCfg.u.MaxTransactions-1:0] inflight_valid_r_set;
    logic                                           inflight_addr_hit;

    logic                                           midend_handshake_d;
    logic                                           midend_handshake_q;

    ac_t                                            ac;


    //--------------------
    //  Blocking path
    //--------------------

    // AW generates a snoop transaction
    assign aw_snooping = aw_is_coherent(aw_block_i.bar[0], aw_block_i.domain, aw_block_i.snoop);
    // ACSNOOP computed from AWSNOOP
    assign aw_acsnoop = aw_acsnoop_map(aw_block_i.bar[0], aw_block_i.domain, aw_block_i.snoop);
    // AR generates a snoop transaction
    assign ar_snooping = ar_is_coherent(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop
    ) || ar_is_cache_maintenance(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop
    );
    // ACSNOOP computed from ARSNOOP
    assign ar_acsnoop = ar_acsnoop_map(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop, ar_block_i.lock
    );
    // Read transaction can accept a cacheline in Dirty state
    assign ar_accepts_dirty = ar_resp_accepts_dirty(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop
    );
    // Read transaction can accept a cacheline in Dirty and Shared state
    assign ar_accepts_dirty_shared = ar_resp_accepts_dirty_shared(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop
    );
    // Read transaction can accept a cacheline in Shared state
    assign ar_accepts_shared = ar_resp_accepts_shared(
        ar_block_i.bar[0], ar_block_i.domain, ar_block_i.snoop
    );

    // Assign AW to internal AX data type
    always_comb begin
        aw_block = '0;
        `AXI_SET_AW_STRUCT(aw_block, aw_block_i)
    end

    // Assign AR to internal AX data type
    always_comb begin
        ar_block = '0;
        `AXI_SET_AR_STRUCT(ar_block, ar_block_i)
    end

    rr_arb_tree #(
        .NumIn    (2),
        .DataType (ccu_ax_t),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b1)
    ) u_ax_block_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   (1'b0),
        .req_i  ({aw_block_valid_i, ar_block_valid_i}),
        .gnt_o  ({aw_block_ready_o, ar_block_ready_o}),
        .data_i ({aw_block, ar_block}),
        .req_o  (ax_block_valid),
        .gnt_i  (ax_block_ready),
        .data_o (ax_block),
        .idx_o  (ax_block_is_write)
    );

    assign ax_block_snooping = ax_block_is_write ? aw_snooping : ar_snooping;
    assign ax_block_acsnoop  = ax_block_is_write ? aw_acsnoop : ar_acsnoop;
    assign ax_block_domain   = ax_block_is_write ? aw_block_i.domain : ar_block_i.domain;

    assign ax_block_stall    = !midend_handshake_q && (tid_list_empty || inflight_addr_hit);

    assign slv_idx           = ax_block.id[CcuCfg.AxiCcuIdWidth-1 : CcuCfg.u.AxiSlvIdWidth];

    always_comb begin
        ac_sel_bv = '0;

        if (ax_block_snooping) begin
            case (ax_block_domain)
                NonShareable:   ac_sel_bv = '0;
                InnerShareable: ac_sel_bv = domain_rule_i[slv_idx].inner;
                OuterShareable: ac_sel_bv = domain_rule_i[slv_idx].outer;
                System:         ac_sel_bv = ~domain_rule_i[slv_idx].initiator;
            endcase
        end
    end

    // Broadcast AC to all snooped masters
    stream_fork_dynamic #(
        .N_OUP(1 + CcuCfg.u.SlvPorts)
    ) u_ax_block_fork (
        .clk_i,
        .rst_ni,
        .valid_i    (ax_block_valid),
        .ready_o    (ax_block_ready),
        .sel_i      ({1'b1, ac_sel_bv}),
        .sel_valid_i(!ax_block_stall),
        .sel_ready_o(),
        .valid_o    ({midend_valid, ac_valid_o}),
        .ready_i    ({midend_ready, ac_ready_i})
    );

    assign midend_handshake_d = !(ax_block_valid && ax_block_ready) && ((midend_valid && midend_ready) || midend_handshake_q);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            midend_handshake_q <= 1'b0;
        end else begin
            midend_handshake_q <= midend_handshake_d;
        end
    end

    assign ac = '{addr: ax_block.addr, snoop: ax_block_acsnoop, prot: '0};
    assign ac_o = {CcuCfg.u.SlvPorts{ac}};

    assign midend_d = '{
            ax: ax_block,
            ax_is_write: ax_block_is_write,
            ax_snooping: ax_block_snooping,
            ar_accepts_dirty: ar_accepts_dirty,
            ar_accepts_dirty_shared: ar_accepts_dirty_shared,
            ar_accepts_shared: ar_accepts_shared,
            cr_sel_bv: ac_sel_bv,
            tid: ax_block_tid
        };

    spill_register #(
        .T     (midend_t),
        .Bypass(1'b0)
    ) u_block_pipe_register (
        .clk_i,
        .rst_ni,
        .valid_i(midend_valid),
        .ready_o(midend_ready),
        .data_i (midend_d),
        .valid_o(midend_valid_o),
        .ready_i(midend_ready_i),
        .data_o (midend_o)
    );

    //--------------------
    //  TID generation
    //--------------------

    ace_ccu_stack #(
        .FREE_LIST(1'b1),
        .DEPTH    (CcuCfg.u.MaxTransactions)
    ) u_tid_free_list (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .full_o (),
        .empty_o(tid_list_empty),
        .usage_o(),
        .data_i (arb_tid),
        .push_i (tid_push),
        .data_o (ax_block_tid),
        .pop_i  (tid_pop)
    );

    assign tid_pop = midend_valid && midend_ready;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tid_push_q <= '0;
        end else begin
            tid_push_q <= tid_push_d;
        end
    end

    for (genvar i = 0; i < CcuCfg.u.MaxTransactions; i++) begin
        // A TID is set to be cleared the cycle all pending responses on its entry are cleared
        assign tid_push_set[i] = |{inflight_valid_b_q[i], inflight_valid_r_q[i]} &&
            ~|{inflight_valid_b_d[i], inflight_valid_r_d[i]};
    end

    assign tid_push_d = ~tid_push_clr & (tid_push_set | tid_push_q);

    rr_arb_tree #(
        .NumIn    (CcuCfg.u.MaxTransactions),
        .DataType (logic),
        .ExtPrio  (1'b1),
        .AxiVldRdy(1'b1),
        .LockIn   (1'b0)
    ) u_tid_push_arbiter (
        .clk_i,
        .rst_ni,
        .flush_i(1'b0),
        .rr_i   ('0),
        .req_i  (tid_push_q),
        .gnt_o  (tid_push_clr),
        .data_i ('0),
        .req_o  (tid_push),
        .gnt_i  (1'b1),
        .data_o (),
        .idx_o  (arb_tid)
    );

    //--------------------
    //  Addr tracker
    //--------------------

    always_comb begin
        inflight_addr_d      = inflight_addr_q;

        inflight_valid_r_set = '0;
        inflight_valid_b_set = '0;

        if (midend_valid && midend_ready) begin
            // The midend register is being written into
            // An R response is expected upon a AR transaction or a AW ATOP with R response
            inflight_valid_r_set[ax_block_tid] = !ax_block_is_write ||
                ax_block.atop[axi_pkg::ATOP_R_RESP];
            // A B response is expected upon a AW transaction
            inflight_valid_b_set[ax_block_tid] = ax_block_is_write;
            // Save only the bits of the cacheline address
            inflight_addr_d[ax_block_tid] = ax_block.addr >> CcuCfg.CachelineBytesIdxWidth;
        end
    end

    assign
        inflight_valid_b_d = ~inflight_valid_b_clr_i & (inflight_valid_b_set | inflight_valid_b_q);
    assign
        inflight_valid_r_d = ~inflight_valid_r_clr_i & (inflight_valid_r_set | inflight_valid_r_q);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            inflight_addr_q    <= '0;
            inflight_valid_b_q <= '0;
            inflight_valid_r_q <= '0;
        end else begin
            inflight_addr_q    <= inflight_addr_d;
            inflight_valid_b_q <= inflight_valid_b_d;
            inflight_valid_r_q <= inflight_valid_r_d;
        end
    end

    always_comb begin
        inflight_addr_hit = 1'b0;

        for (int unsigned i = 0; i < CcuCfg.u.MaxTransactions; i++) begin
            if (inflight_valid_r_q[i] || inflight_valid_b_q[i]) begin
                inflight_addr_hit |= (ax_block.addr >> CcuCfg.CachelineBytesIdxWidth) ==
                    inflight_addr_q[i];
            end
        end
    end

endmodule
