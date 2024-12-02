module ace_demux #(
  parameter int unsigned AxiIdWidth     = 32'd0,
  parameter bit          AtopSupport    = 1'b1,
  parameter type         aw_chan_t      = logic,
  parameter type         w_chan_t       = logic,
  parameter type         b_chan_t       = logic,
  parameter type         ar_chan_t      = logic,
  parameter type         r_chan_t       = logic,
  parameter type         axi_req_t      = logic,
  parameter type         axi_resp_t     = logic,
  parameter int unsigned NoMstPorts     = 32'd0,
  parameter int unsigned MaxTrans       = 32'd8,
  parameter int unsigned AxiLookBits    = 32'd3,
  parameter bit          UniqueIds      = 1'b0,
  parameter bit          SpillAw        = 1'b1,
  parameter bit          SpillW         = 1'b0,
  parameter bit          SpillB         = 1'b0,
  parameter bit          SpillAr        = 1'b1,
  parameter bit          SpillR         = 1'b0,
  parameter bit          AceRegAck      = 1'b0,
  // Dependent parameters, DO NOT OVERRIDE!
  parameter int unsigned SelectWidth    = (NoMstPorts > 32'd1) ? $clog2(NoMstPorts) : 32'd1,
  parameter type         select_t       = logic [SelectWidth-1:0]
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          test_i,
  // Slave Port
  input  axi_req_t                      slv_req_i,
  input  select_t                       slv_aw_select_i,
  input  select_t                       slv_ar_select_i,
  output axi_resp_t                     slv_resp_o,
  // Master Ports
  output axi_req_t    [NoMstPorts-1:0]  mst_reqs_o,
  input  axi_resp_t   [NoMstPorts-1:0]  mst_resps_i
);

    axi_demux #(
        .AxiIdWidth  (AxiIdWidth ),
        .AtopSupport (AtopSupport),
        .aw_chan_t   (aw_chan_t  ),
        .w_chan_t    (w_chan_t   ),
        .b_chan_t    (b_chan_t   ),
        .ar_chan_t   (ar_chan_t  ),
        .r_chan_t    (r_chan_t   ),
        .axi_req_t   (axi_req_t  ),
        .axi_resp_t  (axi_resp_t ),
        .NoMstPorts  (NoMstPorts ),
        .MaxTrans    (MaxTrans   ),
        .AxiLookBits (AxiLookBits),
        .UniqueIds   (UniqueIds  ),
        .Ace         (1'b1       ),
        .SpillAw     (SpillAw    ),
        .SpillW      (SpillW     ),
        .SpillB      (SpillB     ),
        .SpillAr     (SpillAr    ),
        .SpillR      (SpillR     ),
        .AceRegAck   (AceRegAck  )
    ) __ace_demux (
        .*
    );

endmodule

// interface wrapper
`include "ace/assign.svh"
`include "ace/typedef.svh"
module ace_demux_intf #(
  parameter int unsigned AXI_ID_WIDTH     = 32'd0, // Synopsys DC requires default value for params
  parameter bit          ATOP_SUPPORT     = 1'b1,
  parameter int unsigned AXI_ADDR_WIDTH   = 32'd0,
  parameter int unsigned AXI_DATA_WIDTH   = 32'd0,
  parameter int unsigned AXI_USER_WIDTH   = 32'd0,
  parameter int unsigned NO_MST_PORTS     = 32'd3,
  parameter int unsigned MAX_TRANS        = 32'd8,
  parameter int unsigned AXI_LOOK_BITS    = 32'd3,
  parameter bit          UNIQUE_IDS       = 1'b0,
  parameter bit          SPILL_AW         = 1'b1,
  parameter bit          SPILL_W          = 1'b0,
  parameter bit          SPILL_B          = 1'b0,
  parameter bit          SPILL_AR         = 1'b1,
  parameter bit          SPILL_R          = 1'b0,
  parameter bit          ACE_REG_ACK      = 1'b0,
  // Dependent parameters, DO NOT OVERRIDE!
  parameter int unsigned SELECT_WIDTH   = (NO_MST_PORTS > 32'd1) ? $clog2(NO_MST_PORTS) : 32'd1,
  parameter type         select_t       = logic [SELECT_WIDTH-1:0] // MST port select type
) (
  input  logic    clk_i,                 // Clock
  input  logic    rst_ni,                // Asynchronous reset active low
  input  logic    test_i,                // Testmode enable
  input  select_t slv_aw_select_i,       // has to be stable, when aw_valid
  input  select_t slv_ar_select_i,       // has to be stable, when ar_valid
  ACE_BUS.Slave   slv,                   // slave port
  ACE_BUS.Master  mst [NO_MST_PORTS-1:0] // master ports
);

  typedef logic [AXI_ID_WIDTH-1:0]       id_t;
  typedef logic [AXI_ADDR_WIDTH-1:0]   addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0]   data_t;
  typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
  typedef logic [AXI_USER_WIDTH-1:0]   user_t;
  `ACE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)
  `ACE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)
  `ACE_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)
  `ACE_TYPEDEF_REQ_T(axi_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `ACE_TYPEDEF_RESP_T(axi_resp_t, b_chan_t, r_chan_t)

  axi_req_t                     slv_req;
  axi_resp_t                    slv_resp;
  axi_req_t  [NO_MST_PORTS-1:0] mst_req;
  axi_resp_t [NO_MST_PORTS-1:0] mst_resp;

  `ACE_ASSIGN_TO_REQ(slv_req, slv)
  `ACE_ASSIGN_FROM_RESP(slv, slv_resp)

  for (genvar i = 0; i < NO_MST_PORTS; i++) begin : gen_assign_mst_ports
    `ACE_ASSIGN_FROM_REQ(mst[i], mst_req[i])
    `ACE_ASSIGN_TO_RESP(mst_resp[i], mst[i])
  end

  axi_demux #(
    .AxiIdWidth     ( AXI_ID_WIDTH  ), // ID Width
    .AtopSupport    ( ATOP_SUPPORT  ),
    .aw_chan_t      (  aw_chan_t    ), // AW Channel Type
    .w_chan_t       (   w_chan_t    ), //  W Channel Type
    .b_chan_t       (   b_chan_t    ), //  B Channel Type
    .ar_chan_t      (  ar_chan_t    ), // AR Channel Type
    .r_chan_t       (   r_chan_t    ), //  R Channel Type
    .axi_req_t      (  axi_req_t    ),
    .axi_resp_t     ( axi_resp_t    ),
    .NoMstPorts     ( NO_MST_PORTS  ),
    .MaxTrans       ( MAX_TRANS     ),
    .AxiLookBits    ( AXI_LOOK_BITS ),
    .UniqueIds      ( UNIQUE_IDS    ),
    .Ace            (1'b1           ),
    .SpillAw        ( SPILL_AW      ),
    .SpillW         ( SPILL_W       ),
    .SpillB         ( SPILL_B       ),
    .SpillAr        ( SPILL_AR      ),
    .SpillR         ( SPILL_R       ),
    .AceRegAck      ( ACE_REG_ACK   )
  ) __ace_demux (
    .clk_i,   // Clock
    .rst_ni,  // Asynchronous reset active low
    .test_i,  // Testmode enable
    // slave port
    .slv_req_i       ( slv_req         ),
    .slv_aw_select_i ( slv_aw_select_i ),
    .slv_ar_select_i ( slv_ar_select_i ),
    .slv_resp_o      ( slv_resp        ),
    // master port
    .mst_reqs_o      ( mst_req         ),
    .mst_resps_i     ( mst_resp        )
  );
endmodule
