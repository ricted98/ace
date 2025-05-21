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

module ace_ccu_midend
    import ace_pkg::*;
    import ace_ccu_pkg::*;
#(
    parameter ace_ccu_cfg_t CcuCfg    = '{default: '0},
    parameter type          cr_t      = logic,
    parameter type          midend_t  = logic,
    parameter type          cd_sel_t  = logic,
    parameter type          backend_t = logic
) (
    input  logic                             clk_i,
    input  logic                             rst_ni,
    // Piped signals from frontend
    input  logic                             midend_valid_i,
    output logic                             midend_ready_o,
    input  midend_t                          midend_i,
    // CR snoop channel
    input  cr_t      [CcuCfg.u.SlvPorts-1:0] cr_i,
    input  logic     [CcuCfg.u.SlvPorts-1:0] cr_valid_i,
    output logic     [CcuCfg.u.SlvPorts-1:0] cr_ready_o,
    // Piped signals to backend
    output logic                             backend_valid_o,
    input  logic                             backend_ready_i,
    output backend_t                         backend_o
);

    // Internal signals
    logic                             backend_pipe_in_valid;
    logic                             backend_pipe_in_ready;
    backend_t                         backend_pipe_in;

    logic                             r_resp_shared;
    logic                             r_resp_dirty;

    logic                             aw_sel;
    logic                             ar_sel;
    cd_sel_t                          cd_sel;

    logic     [CcuCfg.u.SlvPorts-1:0] cr_data_transfer_bv;
    cr_t                              cr_merged;

    // Merge responses in a unified CR struct
    always_comb begin
        cr_merged = '0;
        for (int unsigned i = 0; i < CcuCfg.u.SlvPorts; i++) begin
            if (midend_i.cr_sel_bv[i]) begin
                cr_merged.WasUnique |= cr_i[i].WasUnique;
                cr_merged.IsShared |= cr_i[i].IsShared;
                cr_merged.PassDirty |= cr_i[i].PassDirty;
                cr_merged.Error |= cr_i[i].Error;
                cr_merged.DataTransfer |= cr_i[i].DataTransfer;
            end
        end
    end

    for (genvar i = 0; i < CcuCfg.u.SlvPorts; i++) begin
        assign cr_data_transfer_bv[i] = midend_i.cr_sel_bv[i] && cr_i[i].DataTransfer;
    end

    // Wait for all CR responses selected if the request is shareable
    stream_join_dynamic #(
        .N_INP(1 + CcuCfg.u.SlvPorts)
    ) u_ax_join (
        .inp_valid_i({midend_valid_i, cr_valid_i}),
        .inp_ready_o({midend_ready_o, cr_ready_o}),
        .sel_i      ({1'b1, midend_i.cr_sel_bv}),
        .oup_valid_o(backend_pipe_in_valid),
        .oup_ready_i(backend_pipe_in_ready)
    );

    assign r_resp_shared = cr_merged.IsShared;
    assign r_resp_dirty  = cr_merged.PassDirty && midend_i.ar_accepts_dirty;

    always_comb begin
        aw_sel = 1'b0;
        ar_sel = 1'b0;

        cd_sel = '0;

        if (!midend_i.ax_snooping) begin
            // The transactions is not shareable
            if (midend_i.ax_is_write) begin
                // The transactions is a write
                // ~> forward to backend (AW)
                aw_sel = 1'b1;
            end else begin
                // The transactions is a read
                // ~> forward to backend (AR)
                ar_sel = 1'b1;
            end
        end else if (midend_i.ax_is_write) begin
            // The transactions is a shareable write
            // ~> forward to backend (AW)
            aw_sel = 1'b1;
            if (cr_merged.DataTransfer) begin
                // A writeback is expected
                // ~> forward to CD controller
                cd_sel.write = cr_merged.PassDirty;
                cd_sel.drop  = !cr_merged.PassDirty;
            end
        end else begin
            // The transactions is a shareable read
            if (cr_merged.DataTransfer) begin
                // A cacheline is expected on CD
                // ~> forward to CD controller
                cd_sel.read = 1'b1;
                if (cr_merged.PassDirty && !midend_i.ar_accepts_dirty) begin
                    // The cacheline is dirty but the initiator cannot accept it
                    // ~> forward to backed (AW)
                    aw_sel       = 1'b1;
                    cd_sel.write = 1'b1;
                end
            end else begin
                // The cacheline must be obtained from memory
                // ~> forward to backend (AR)
                ar_sel = 1'b1;
            end
        end
    end

    assign backend_pipe_in = '{
            cd_sel: cd_sel,
            aw_sel: aw_sel,
            ar_sel: ar_sel,
            r_resp_shared: r_resp_shared,
            r_resp_dirty: r_resp_dirty,
            ax_is_write: midend_i.ax_is_write,
            cd_sel_bv: cr_data_transfer_bv,
            tid: midend_i.tid,
            ax: midend_i.ax
        };

    spill_register #(
        .T     (backend_t),
        .Bypass(1'b0)
    ) u_backend_pipe_register (
        .clk_i,
        .rst_ni,
        .valid_i(backend_pipe_in_valid),
        .ready_o(backend_pipe_in_ready),
        .data_i (backend_pipe_in),
        .valid_o(backend_valid_o),
        .ready_i(backend_ready_i),
        .data_o (backend_o)
    );

endmodule
