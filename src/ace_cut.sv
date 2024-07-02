// Copyright (c) 2014-2018 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Yvan Tortorella <yvan.tortorella@unibio.it>

/// ACE protocol cut.
///
/// Breaks all combinatorial paths between its input and output.
module ace_cut #(
  // bypass enable
  parameter bit  Bypass     = 1'b0,
  // AXI channel structs
  parameter type  aw_chan_t = logic,
  parameter type   w_chan_t = logic,
  parameter type   b_chan_t = logic,
  parameter type  ar_chan_t = logic,
  parameter type   r_chan_t = logic,
  parameter type  ac_chan_t = logic,
  parameter type  cd_chan_t = logic,
  parameter type  cr_chan_t = logic,
  // AXI request & response structs
  parameter type  ace_req_t = logic,
  parameter type ace_resp_t = logic
) (
  input logic       clk_i,
  input logic       rst_ni,
  // salve port
  input  ace_req_t  slv_req_i,
  output ace_resp_t slv_resp_o,
  // master port
  output ace_req_t  mst_req_o,
  input  ace_resp_t mst_resp_i
);

  // a spill register for each channel
  // AXI channels cut
  spill_register #(
    .T       ( aw_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_aw (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.aw_valid  ),
    .ready_o ( slv_resp_o.aw_ready ),
    .data_i  ( slv_req_i.aw        ),
    .valid_o ( mst_req_o.aw_valid  ),
    .ready_i ( mst_resp_i.aw_ready ),
    .data_o  ( mst_req_o.aw        )
  );

  spill_register #(
    .T       ( w_chan_t ),
    .Bypass  ( Bypass   )
  ) i_reg_w  (
    .clk_i   ( clk_i              ),
    .rst_ni  ( rst_ni             ),
    .valid_i ( slv_req_i.w_valid  ),
    .ready_o ( slv_resp_o.w_ready ),
    .data_i  ( slv_req_i.w        ),
    .valid_o ( mst_req_o.w_valid  ),
    .ready_i ( mst_resp_i.w_ready ),
    .data_o  ( mst_req_o.w        )
  );

  spill_register #(
    .T       ( b_chan_t ),
    .Bypass  ( Bypass   )
  ) i_reg_b  (
    .clk_i   ( clk_i              ),
    .rst_ni  ( rst_ni             ),
    .valid_i ( mst_resp_i.b_valid ),
    .ready_o ( mst_req_o.b_ready  ),
    .data_i  ( mst_resp_i.b       ),
    .valid_o ( slv_resp_o.b_valid ),
    .ready_i ( slv_req_i.b_ready  ),
    .data_o  ( slv_resp_o.b       )
  );

  spill_register #(
    .T       ( ar_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_ar (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.ar_valid  ),
    .ready_o ( slv_resp_o.ar_ready ),
    .data_i  ( slv_req_i.ar        ),
    .valid_o ( mst_req_o.ar_valid  ),
    .ready_i ( mst_resp_i.ar_ready ),
    .data_o  ( mst_req_o.ar        )
  );

  spill_register #(
    .T       ( r_chan_t ),
    .Bypass  ( Bypass   )
  ) i_reg_r  (
    .clk_i   ( clk_i              ),
    .rst_ni  ( rst_ni             ),
    .valid_i ( mst_resp_i.r_valid ),
    .ready_o ( mst_req_o.r_ready  ),
    .data_i  ( mst_resp_i.r       ),
    .valid_o ( slv_resp_o.r_valid ),
    .ready_i ( slv_req_i.r_ready  ),
    .data_o  ( slv_resp_o.r       )
  );

  // Snoop channels cut
  spill_register #(
    .T       ( ac_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_ac (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( mst_resp_i.ac_valid ),
    .ready_o ( mst_req_o.ac_ready  ),
    .data_i  ( mst_resp_i.ac       ),
    .valid_o ( slv_resp_o.ac_valid ),
    .ready_i ( slv_req_i.ac_ready  ),
    .data_o  ( slv_resp_o.ac       )
  );

  spill_register #(
    .T       ( cd_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_cd (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.cd_valid  ),
    .ready_o ( slv_resp_o.cd_ready ),
    .data_i  ( slv_req_i.cd        ),
    .valid_o ( mst_req_o.cd_valid  ),
    .ready_i ( mst_resp_i.cd_ready ),
    .data_o  ( mst_req_o.cd        )
  );

  spill_register #(
    .T       ( cr_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_cr (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.cr_valid  ),
    .ready_o ( slv_resp_o.cr_ready ),
    .data_i  ( slv_req_i.cr_resp   ),
    .valid_o ( mst_req_o.cr_valid  ),
    .ready_i ( mst_resp_i.cr_ready ),
    .data_o  ( mst_req_o.cr_resp   )
  );
endmodule

// TODO: add interface-based cut (needs definition of new
// __ASSIGN macros or extension of the existing ones with
// snoop buses.

// `include "ace/assign.svh"
// `include "ace/typedef.svh"
// `include "axi/typedef.svh"
// 
// // interface wrapper
// module axi_cut_intf #(
//   // Bypass eneable
//   parameter bit          BYPASS     = 1'b0,
//   // The address width.
//   parameter int unsigned ADDR_WIDTH = 0,
//   // The data width.
//   parameter int unsigned DATA_WIDTH = 0,
//   // The ID width.
//   parameter int unsigned ID_WIDTH   = 0,
//   // The user data width.
//   parameter int unsigned USER_WIDTH = 0
// ) (
//   input logic     clk_i  ,
//   input logic     rst_ni ,
//   AXI_BUS.Slave   in     ,
//   AXI_BUS.Master  out
// );
// 
//   typedef logic [ID_WIDTH-1:0]     id_t;
//   typedef logic [ADDR_WIDTH-1:0]   addr_t;
//   typedef logic [DATA_WIDTH-1:0]   data_t;
//   typedef logic [DATA_WIDTH/8-1:0] strb_t;
//   typedef logic [USER_WIDTH-1:0]   user_t;
// 
//   `ACE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)
//   `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
//   `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)
//   `ACE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)
//   `ACE_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)
//   `SNOOP_TYPEDEF_AC_CHAN_T(ac_chan_t, addr_t)
//   `SNOOP_TYPEDEF_CD_CHAN_T(cd_chan_t, data_t)
//   `SNOOP_TYPEDEF_CR_CHAN_T(cr_chan_t)
//   `ACE_TYPEDEF_SNOOP_REQ_T(ace_req_t, aw_chan_t, w_chan_t, ar_chan_t, cr_chan_t, cd_chan_t)
//   `ACE_TYPEDEF_SNOOP_RESP_T(ace_resp_t, b_chan_t, r_chan_t, ac_chan_t)
// 
//   ace_req_t  slv_req,  mst_req;
//   ace_resp_t slv_resp, mst_resp;
// 
//   `ACE_ASSIGN_TO_REQ(slv_req, in)
//   `ACE_ASSIGN_FROM_RESP(in, slv_resp)
// 
//   `ACE_ASSIGN_FROM_REQ(out, mst_req)
//   `ACE_ASSIGN_TO_RESP(mst_resp, out)
// 
//   ace_cut #(
//     .Bypass     (     BYPASS ),
//     .aw_chan_t  (  aw_chan_t ),
//     .w_chan_t   (   w_chan_t ),
//     .b_chan_t   (   b_chan_t ),
//     .ar_chan_t  (  ar_chan_t ),
//     .r_chan_t   (   r_chan_t ),
//     .axi_req_t  (  ace_req_t ),
//     .axi_resp_t ( ace_resp_t )
//   ) i_ace_cut (
//     .clk_i,
//     .rst_ni,
//     .slv_req_i  ( slv_req  ),
//     .slv_resp_o ( slv_resp ),
//     .mst_req_o  ( mst_req  ),
//     .mst_resp_i ( mst_resp )
//   );
// 
//   // Check the invariants.
//   // pragma translate_off
//   `ifndef VERILATOR
//   initial begin
//     assert (ADDR_WIDTH > 0) else $fatal(1, "Wrong addr width parameter");
//     assert (DATA_WIDTH > 0) else $fatal(1, "Wrong data width parameter");
//     assert (ID_WIDTH   > 0) else $fatal(1, "Wrong id   width parameter");
//     assert (USER_WIDTH > 0) else $fatal(1, "Wrong user width parameter");
//     assert (in.AXI_ADDR_WIDTH  == ADDR_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (in.AXI_DATA_WIDTH  == DATA_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (in.AXI_ID_WIDTH    == ID_WIDTH)   else $fatal(1, "Wrong interface definition");
//     assert (in.AXI_USER_WIDTH  == USER_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_ADDR_WIDTH == ADDR_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_DATA_WIDTH == DATA_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_ID_WIDTH   == ID_WIDTH)   else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_USER_WIDTH == USER_WIDTH) else $fatal(1, "Wrong interface definition");
//   end
//   `endif
//   // pragma translate_on
// endmodule
// 
// module axi_lite_cut_intf #(
//   // bypass enable
//   parameter bit          BYPASS     = 1'b0,
//   /// The address width.
//   parameter int unsigned ADDR_WIDTH = 0,
//   /// The data width.
//   parameter int unsigned DATA_WIDTH = 0
// ) (
//   input logic     clk_i  ,
//   input logic     rst_ni ,
//   AXI_LITE.Slave  in     ,
//   AXI_LITE.Master out
// );
// 
//   typedef logic [ADDR_WIDTH-1:0]   addr_t;
//   typedef logic [DATA_WIDTH-1:0]   data_t;
//   typedef logic [DATA_WIDTH/8-1:0] strb_t;
// 
//   `AXI_LITE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t)
//   `AXI_LITE_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t)
//   `AXI_LITE_TYPEDEF_B_CHAN_T(b_chan_t)
//   `AXI_LITE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t)
//   `AXI_LITE_TYPEDEF_R_CHAN_T(r_chan_t, data_t)
//   `AXI_LITE_TYPEDEF_REQ_T(axi_req_t, aw_chan_t, w_chan_t, ar_chan_t)
//   `AXI_LITE_TYPEDEF_RESP_T(axi_resp_t, b_chan_t, r_chan_t)
// 
//   axi_req_t   slv_req,  mst_req;
//   axi_resp_t  slv_resp, mst_resp;
// 
//   `AXI_LITE_ASSIGN_TO_REQ(slv_req, in)
//   `AXI_LITE_ASSIGN_FROM_RESP(in, slv_resp)
// 
//   `AXI_LITE_ASSIGN_FROM_REQ(out, mst_req)
//   `AXI_LITE_ASSIGN_TO_RESP(mst_resp, out)
// 
//   axi_cut #(
//     .Bypass     (     BYPASS ),
//     .aw_chan_t  (  aw_chan_t ),
//     .w_chan_t   (   w_chan_t ),
//     .b_chan_t   (   b_chan_t ),
//     .ar_chan_t  (  ar_chan_t ),
//     .r_chan_t   (   r_chan_t ),
//     .axi_req_t  (  axi_req_t ),
//     .axi_resp_t ( axi_resp_t )
//   ) i_axi_cut (
//     .clk_i,
//     .rst_ni,
//     .slv_req_i  ( slv_req  ),
//     .slv_resp_o ( slv_resp ),
//     .mst_req_o  ( mst_req  ),
//     .mst_resp_i ( mst_resp )
//   );
// 
//   // Check the invariants.
//   // pragma translate_off
//   `ifndef VERILATOR
//   initial begin
//     assert (ADDR_WIDTH > 0) else $fatal(1, "Wrong addr width parameter");
//     assert (DATA_WIDTH > 0) else $fatal(1, "Wrong data width parameter");
//     assert (in.AXI_ADDR_WIDTH == ADDR_WIDTH)  else $fatal(1, "Wrong interface definition");
//     assert (in.AXI_DATA_WIDTH == DATA_WIDTH)  else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_ADDR_WIDTH == ADDR_WIDTH) else $fatal(1, "Wrong interface definition");
//     assert (out.AXI_DATA_WIDTH == DATA_WIDTH) else $fatal(1, "Wrong interface definition");
//   end
//   `endif
//   // pragma translate_on
// endmodule
