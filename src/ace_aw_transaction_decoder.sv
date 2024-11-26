module ace_aw_transaction_decoder import ace_pkg::*; #(
    parameter bit LEGACY     = 0,
    parameter type aw_chan_t = logic
)(
    // Input channel
    input  aw_chan_t aw_i,
    // Control signals
    output acsnoop_t    acsnoop_o,
    output logic        snooping_o,
    output snoop_info_t snoop_info_o,
    output logic        illegal_trs_o
);

awsnoop_t awsnoop;

logic     is_shareable;
logic     is_system;
logic     is_barrier;

logic write_no_snoop;
logic write_unique;
logic write_line_unique;
logic write_clean;
logic write_back;
logic evict;
logic write_evict;
logic barrier;
logic lock;

assign awsnoop      = aw_i.snoop;
// Locks are used ONLY in legacy setup
// ACE doesn't support aw_lock to shareable regions
assign lock         = aw_i.lock;

assign is_shareable = aw_i.domain inside {InnerShareable, OuterShareable};
assign is_system    = aw_i.domain inside {System};
assign is_barrier   = aw_i.bar inside {MemoryBarrier, SynchronizationBarrier};

assign write_no_snoop    = !is_barrier && !is_shareable && awsnoop == awsnoop_t'(WriteNoSnoop);
assign write_unique      = !is_barrier &&  is_shareable && awsnoop == awsnoop_t'(WriteUnique);
assign write_line_unique = !is_barrier &&  is_shareable && awsnoop == awsnoop_t'(WriteLineUnique);
assign write_clean       = !is_barrier && !is_system    && awsnoop == awsnoop_t'(WriteClean);
assign write_back        = !is_barrier && !is_system    && awsnoop == awsnoop_t'(WriteBack);
assign evict             = !is_barrier &&  is_shareable && awsnoop == awsnoop_t'(Evict);
assign write_evict       = !is_barrier && !is_system    && awsnoop == awsnoop_t'(WriteEvict);
assign barrier           =  is_barrier                  && awsnoop == awsnoop_t'(Barrier);

always_comb begin
    illegal_trs_o = 1'b0;
    snooping_o    = 1'b0;
    snoop_info_o.snoop_trs            = acsnoop_t'(awsnoop);
    snoop_info_o.accepts_dirty        = 1'b0;
    snoop_info_o.accepts_dirty_shared = 1'b0;
    snoop_info_o.accepts_shared       = 1'b0;
    snoop_info_o.excl_load            = 1'b0;
    snoop_info_o.excl_store           = 1'b0;
    unique case (1'b1)
        write_no_snoop: begin

        end
        write_unique: begin
            snoop_info_o.snoop_trs  = acsnoop_t'(CleanInvalid);
            snooping_o = 1'b1;
            if (LEGACY)
                snoop_info_o.excl_store = lock;
        end
        write_line_unique: begin
            snoop_info_o.snoop_trs  = acsnoop_t'(MakeInvalid);
            snooping_o = 1'b1;
        end
        write_clean: begin

        end
        write_back: begin

        end
        evict: begin

        end
        write_evict: begin

        end
        barrier: begin

        end
        default: illegal_trs_o = 1'b1;
    endcase
end


endmodule
