// Manager for monitoring Exclusive sequences
// Similar to the PoS monitor defined in the ACE spec
module ace_ccu_atomic_manager #(
    parameter int unsigned AmIdxWidth    = 0,
    parameter type mst_idx_t             = logic,

    localparam type am_idx_t             = logic [AmIdxWidth-1:0]
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  logic                      am_ex_req_i,
    /// 0 - Exclusive Load, 1 - Exclusive Store
    input  logic                      am_ex_type_i,
    input  am_idx_t                   am_ex_addr_i,
    /// Master ID
    input  mst_idx_t                  am_ex_id_i,
    output logic                      am_ex_okay_o,
);

localparam int unsigned NumEntries = 2**CmIdxWidth;

mst_idx_t id_mask_q, id_mask_d;

always_comb begin
    id_mask_d    = id_mask_q;
    am_ex_okay_o = 1'b0;
    if (am_req_i) begin
        if (am_ex_type_i) begin
            // Exclusive Store
            logic new_mask          = id_mask_q[am_ex_addr_i] & am_ex_id_i;
            id_mask_d[am_ex_addr_i] = new_mask;
            am_ex_okay_o            = !(new_mask == 0);
        end else begin
            // Exclusive Load
            id_mask_d[am_ex_addr_i] = id_mask_q[am_ex_addr_i] | am_ex_id_i;
        end
    end
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        id_mask_q <= '0;
    end else begin
        id_mask_q <= id_mask_d;
    end
end

endmodule
