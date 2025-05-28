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

module ace_ccu_stack #(
    // When set to 1, the stack is initialized as full
    // and each entry contains its index
    parameter  bit          FREE_LIST  = 1'b0,
    parameter  int unsigned DEPTH      = 8,
    parameter  int unsigned DATA_WIDTH = FREE_LIST ? $clog2(DEPTH) : 32,
    parameter  type         dtype      = logic [DATA_WIDTH-1:0],
    localparam int unsigned ADDR_DEPTH = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  logic                  clk_i,    // Clock
    input  logic                  rst_ni,   // Asynchronous reset active low
    input  logic                  flush_i,  // flush the queue
    // status flags
    output logic                  full_o,   // queue is full
    output logic                  empty_o,  // queue is empty
    output logic [ADDR_DEPTH-1:0] usage_o,  // fill pointer
    // as long as the queue is not full we can push new data
    input  dtype                  data_i,   // data to push into the queue
    input  logic                  push_i,   // data is valid and can be pushed to the queue
    // as long as the queue is not empty we can pop new elements
    output dtype                  data_o,   // output data
    input  logic                  pop_i     // pop head from queue
);

    logic                not_empty;
    dtype [   DEPTH-1:0] stack_q;
    dtype [   DEPTH-1:0] stack_d;

    logic [ADDR_DEPTH:0] usage;
    logic [ADDR_DEPTH:0] pop_ptr;
    logic [ADDR_DEPTH:0] push_ptr;

    assign empty_o = !not_empty;
    assign usage_o = usage[ADDR_DEPTH-1:0];

    // Use a credit counter to track the status of the stack
    credit_counter #(
        .NumCredits     (DEPTH),
        .InitCreditEmpty(!FREE_LIST)
    ) u_stack_credit_cnt (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .credit_o     (usage),
        .credit_give_i(push_i),
        .credit_take_i(pop_i),
        .credit_init_i(flush_i),
        .credit_left_o(not_empty),
        .credit_crit_o(  /* unused */),
        .credit_full_o(full_o)
    );

    for (genvar i = 0; i < DEPTH; i++) begin : gen_stack_regs
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                stack_q[i] <= FREE_LIST ? DATA_WIDTH'(i) : '0;
            end else begin
                stack_q[i] <= stack_d[i];
            end
        end
    end

    always_comb begin
        // Normal condition
        // ~> pop highest valid entry
        pop_ptr  = usage - 1;
        // ~> push into the first non valid entry
        push_ptr = usage;

        if (pop_i && push_i) begin
            // Concurrent push and pop
            // ~> replace the highest valid entry
            push_ptr = usage - 1;
        end

        if (empty_o) begin
            // Empty stack
            // ~> avoid underflowing with the pop pointer
            pop_ptr = '0;
        end
    end

    // Push logic
    // ~> decoder based on push pointer
    always_comb begin
        stack_d = stack_q;

        if (push_i) begin
            stack_d[push_ptr] = data_i;
        end
    end

    // Pop logic
    // ~> mux based on pop pointer
    assign data_o = stack_q[pop_ptr];

endmodule
