module ace_ccu_snoop_port import ace_pkg::*; #(
    parameter int unsigned NumInp     = 0,
    parameter int unsigned NumOup     = 0,
    parameter bit          BufferResp = 0,
    parameter type         ac_chan_t  = logic,
    parameter type         cr_chan_t  = logic,
    parameter type         cd_chan_t  = logic,

    localparam type inp_idx_t = logic [$clog2(NumInp)-1:0]
) (

    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic                  inp_ac_valid_i,
    output logic                  inp_ac_ready_o,
    input  ac_chan_t              inp_ac_chan_i,

    output logic     [NumInp-1:0] inp_cr_valids_o,
    input  logic     [NumInp-1:0] inp_cr_readies_i,
    output cr_chan_t [NumInp-1:0] inp_cr_chans_o,

    output logic     [NumInp-1:0] inp_cd_valids_o,
    input  logic     [NumInp-1:0] inp_cd_readies_i,
    output cd_chan_t [NumInp-1:0] inp_cd_chans_o,

    input  inp_idx_t              inp_idx_i,

    output logic                  oup_ac_valid_o,
    input  logic                  oup_ac_ready_i,
    output ac_chan_t              oup_ac_chan_o,
    input  logic                  oup_cr_valid_i,
    output logic                  oup_cr_ready_o,
    input  cr_chan_t              oup_cr_chan_i,
    input  logic                  oup_cd_valid_i,
    output logic                  oup_cd_ready_o,
    input  cd_chan_t              oup_cd_chan_i
);
    logic inp_idx_valid, inp_idx_ready;

    logic     cr_sel_valid, cr_sel_ready;
    inp_idx_t cr_sel;

    logic     cd_sel_in_valid, cd_sel_in_ready;
    logic     cd_sel_valid, cd_sel_ready;
    inp_idx_t cd_sel;

    logic cr_valid, cr_ready;
    logic cd_valid, cd_ready;

    logic cr_data_transfer, cd_last;

    assign cr_data_transfer = oup_cr_chan_i.DataTransfer;
    assign cd_last          = oup_cd_chan_i.last;

    stream_fork #(
        .N_OUP (2)
    ) i_oup_ac_handshake (
        .clk_i,
        .rst_ni,
        .valid_i     (inp_ac_valid_i),
        .ready_o     (inp_ac_ready_o),
        .valid_o     ({inp_idx_valid, oup_ac_valid_o}),
        .ready_i     ({inp_idx_ready, oup_ac_ready_i})
    );

    assign oup_ac_chan_o  = inp_ac_chan_i;

    stream_fifo_optimal_wrap #(
        .Depth (2),
        .type_t (inp_idx_t)
    ) i_cr_idx_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    (1'b0),
        .testmode_i (1'b0),
        .usage_o    (),
        .valid_i    (inp_idx_valid),
        .ready_o    (inp_idx_ready),
        .data_i     (inp_idx_i),
        .valid_o    (cr_sel_valid),
        .ready_i    (cr_sel_ready),
        .data_o     (cr_sel)
    );

    stream_fork_dynamic #(
        .N_OUP (2)
    ) i_cr_fork (
        .clk_i,
        .rst_ni,
        .valid_i     (cr_sel_valid),
        .ready_o     (cr_sel_ready),
        .sel_i       ({1'b1, cr_data_transfer}),
        .sel_valid_i (oup_cr_valid_i),
        .sel_ready_o (oup_cr_ready_o),
        .valid_o     ({cr_valid, cd_sel_in_valid}),
        .ready_i     ({cr_ready, cd_sel_in_ready})
    );

    typedef struct packed {
        inp_idx_t idx;
        cr_chan_t cr;
    } cr_fifo_entry_t;

    logic cr_fifo_valid, cr_fifo_ready;
    cr_fifo_entry_t cr_fifo_in, cr_fifo_out;
    assign cr_fifo_in.idx  = cr_sel;
    assign cr_fifo_in.cr   = oup_cr_chan_i;

    if (BufferResp) begin
        stream_fifo_optimal_wrap #(
            .Depth (2),
            .type_t (cr_fifo_entry_t)
        ) i_cr_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .valid_i    (cr_valid),
            .ready_o    (cr_ready),
            .data_i     (cr_fifo_in),
            .valid_o    (cr_fifo_valid),
            .ready_i    (cr_fifo_ready),
            .data_o     (cr_fifo_out)
        );
    end else begin
        assign cr_fifo_out   = cr_fifo_in;
        assign cr_fifo_valid = cr_valid;
        assign cr_ready      = cr_fifo_ready;
    end

    assign inp_cr_chans_o = {NumInp{cr_fifo_out.cr}};

    stream_demux #(
        .N_OUP (NumInp)
    ) i_inp_cr_demux (
        .inp_valid_i (cr_fifo_valid),
        .inp_ready_o (cr_fifo_ready),
        .oup_sel_i   (cr_fifo_out.idx),
        .oup_valid_o (inp_cr_valids_o),
        .oup_ready_i (inp_cr_readies_i)
    );

    // A sequential element can be easily inserted here
    assign cd_sel_valid    = cd_sel_in_valid;
    assign cd_sel_in_ready = cd_sel_ready && cd_last;
    assign cd_sel          = cr_sel;

    stream_join #(
        .N_INP (2)
    ) i_cd_handshake (
        .inp_valid_i ({cd_sel_valid, oup_cd_valid_i}),
        .inp_ready_o ({cd_sel_ready, oup_cd_ready_o}),
        .oup_valid_o (cd_valid),
        .oup_ready_i (cd_ready)
    );

    typedef struct packed {
        inp_idx_t idx;
        cd_chan_t cd;
    } cd_fifo_entry_t;

    logic cd_fifo_valid, cd_fifo_ready;
    cd_fifo_entry_t cd_fifo_in, cd_fifo_out;
    assign cd_fifo_in.idx  = cd_sel;
    assign cd_fifo_in.cd   = oup_cd_chan_i;

    if (BufferResp) begin
        stream_fifo_optimal_wrap #(
            .Depth (2),
            .type_t (cd_fifo_entry_t)
        ) i_cd_fifo (
            .clk_i,
            .rst_ni,
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .usage_o    (),
            .valid_i    (cd_valid),
            .ready_o    (cd_ready),
            .data_i     (cd_fifo_in),
            .valid_o    (cd_fifo_valid),
            .ready_i    (cd_fifo_ready),
            .data_o     (cd_fifo_out)
        );
    end else begin
        assign cd_fifo_out   = cd_fifo_in;
        assign cd_fifo_valid = cd_valid;
        assign cd_ready      = cd_fifo_ready;
    end

    assign inp_cd_chans_o = {NumInp{cd_fifo_out.cd}};

    stream_demux #(
        .N_OUP (NumInp)
    ) i_inp_cd_demux (
        .inp_valid_i (cd_fifo_valid),
        .inp_ready_o (cd_fifo_ready),
        .oup_sel_i   (cd_fifo_out.idx),
        .oup_valid_o (inp_cd_valids_o),
        .oup_ready_i (inp_cd_readies_i)
    );

endmodule