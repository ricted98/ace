module ace_domain_decoder import ace_pkg::*; #(
    parameter int unsigned  NumRules = 0,
    localparam int unsigned IdxBits  = $clog2(NumRules),
    localparam type idx_t            = logic [IdxBits-1:0]
) (
    input domain_rule_t [NumRules-1:0] rules_i,
    input axdomain_t    [NumRules-1:0] domains_i,
    input idx_t                        idx_i,

    output logic [NumRules-1:0]        sel_mask_o
);

logic [NumRules-1:0] inner_mask, outer_mask;

domain_rule_t rule;
axdomain_t    domain;

assign rule   = rules_i[idx_i];
assign domain = domains_i[idx_i];

always_comb begin
    inner_mask = '0;
    for (int unsigned i = 0; i < rule.InnerShareableNum; i++) begin
        inner_mask |= NumRules'(1 << rule.InnerShareableList[i][IdxBits-1:0]);
    end
end

always_comb begin
    outer_mask = '0;
    for (int unsigned i = 0; i < rule.InnerShareableNum; i++) begin
        outer_mask |= NumRules'(1 << rule.InnerShareableList[i][IdxBits-1:0]);
    end
end

always_comb begin
    sel_mask_o = '0;
    case (domain)
        NonShareable:   sel_mask_o = NumRules'(0);
        InnerShareable: sel_mask_o = NumRules'(inner_mask);
        OuterShareable: sel_mask_o = NumRules'(inner_mask | outer_mask);
        System:         sel_mask_o = NumRules'(~(1 << idx_i));
    endcase
end

endmodule