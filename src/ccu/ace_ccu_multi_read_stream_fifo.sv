module ace_ccu_multi_read_stream_fifo #(
    parameter int unsigned Depth     = 1,
    parameter int unsigned ReadPorts = 2,
    parameter int unsigned DataWidth = 1,
    parameter type data_t            = logic [DataWidth-1:0]
)(
    input  logic  clk_i,
    input  logic  rst_ni,

    input  logic  valid_i,
    output logic  ready_o,
    input  data_t data_i,

    input  logic  [ReadPorts-1:0] sel_i,
    input  logic                  sel_valid_i,
    output logic                  sel_ready_o,

    output logic  [ReadPorts-1:0] valid_o,
    input  logic  [ReadPorts-1:0] ready_i,
    output data_t [ReadPorts-1:0] data_o
);

    localparam int unsigned AddrWidth      = $clog2(Depth);
    localparam int unsigned UsageCntWidth  = AddrWidth+1;

    typedef logic [AddrWidth-1:0]      ptr_t;
    typedef logic [UsageCntWidth-1:0]  ucnt_t;
    typedef logic [Depth-1:0]          rmsk_t;

    data_t [Depth-1:0] data_q, data_d;

    ucnt_t                 ucnt_q, ucnt_d;
    rmsk_t [ReadPorts-1:0] rmsk_q, rmsk_d;
    ptr_t                  wptr_q, wptr_d;
    ptr_t [ReadPorts-1:0]  rptr_q, rptr_d;
    ptr_t                  tptr_q, tptr_d;

    logic                 full;
    logic                 empty;
    logic                 push;
    logic                 pop;
    logic [ReadPorts-1:0] peek;
    logic [ReadPorts-1:0] masked;
    logic                 data_en;

    assign full  = (ucnt_q == Depth);
    assign empty = (ucnt_q == '0);

    assign ready_o     = ~full & sel_valid_i;
    assign push        = valid_i & ready_o;
    assign sel_ready_o = valid_i & ready_o;

    for (genvar i = 0; i < ReadPorts; i++) begin
        assign valid_o[i] = ~rmsk_q[i][rptr_q[i]] & ~empty;
        assign data_o[i]  = data_q[rptr_q[i]];
        assign peek[i]    = ready_i[i] & valid_o[i];
        assign masked[i]  = rmsk_q[i][rptr_q[i]] & ~empty;
    end

    always_comb begin
        pop = ~empty;
        for (int unsigned i = 0; i < ReadPorts; i++)
            pop &= (rmsk_q[i][tptr_q] | peek[i]);
    end

    always_comb begin
        wptr_d  = wptr_q;
        rptr_d  = rptr_q;
        tptr_d  = tptr_q;
        ucnt_d  = ucnt_q;
        data_d  = data_q;
        rmsk_d  = rmsk_q;

        data_en = 1'b0;

        if (push) begin
            data_d[wptr_q] = data_i;
            data_en        = 1'b1;
            wptr_d         = (wptr_q == Depth - 1) ? '0 : wptr_q + ptr_t'(1);
            ucnt_d         = ucnt_q + ucnt_t'(1);
            for (int unsigned i = 0; i < ReadPorts; i++)
                rmsk_d[i][wptr_q] = ~sel_i[i];
        end

        for (int unsigned i = 0; i < ReadPorts; i++) begin
            if (peek[i]) begin
                rptr_d[i] = (rptr_q[i] == Depth - 1) ? '0 : rptr_q[i] + ptr_t'(1);
                rmsk_d[i][rptr_q[i]] = 1'b1;
            end else if (masked[i]) begin
                rptr_d[i] = (rptr_q[i] == Depth - 1) ? '0 : rptr_q[i] + ptr_t'(1);
            end
        end

        if (pop) begin
            ucnt_d = ucnt_q - ucnt_t'(1);
            tptr_d = (tptr_q == Depth - 1) ? '0 : tptr_q + ptr_t'(1);
        end

        if (push & pop)
            ucnt_d = ucnt_q;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            ucnt_q <= '0;
            wptr_q <= '0;
            rptr_q <= '0;
            tptr_q <= '0;
            rmsk_q <= '0;
        end else begin
            ucnt_q <= ucnt_d;
            wptr_q <= wptr_d;
            rptr_q <= rptr_d;
            tptr_q <= tptr_d;
            rmsk_q <= rmsk_d;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            data_q <= '0;
        end else if (data_en) begin
            data_q <= data_d;
        end
    end

    `ifndef SYNTHESIS
    `ifndef COMMON_CELLS_ASSERTS_OFF
        initial begin
            if (Depth <= 0) begin
                $error("Depth must be greater than 0.");
            end
        end

        full_write: assert property (
            @(posedge clk_i)
            disable iff (~rst_ni)
            (full |-> ~(valid_i & ready_o))
        ) else $fatal("Trying to push new data although the FIFO is full.");

        empty_read: assert property (
            @(posedge clk_i)
            disable iff (~rst_ni)
            (empty |-> ~|(valid_o & ready_i))
        ) else $fatal("Trying to pop data although the FIFO is empty.");
    `endif
    `endif

endmodule
