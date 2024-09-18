log -r *
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/clk_i
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/rst_ni
add wave -divider "Snoop ports"
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/snoop_reqs
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/snoop_resps
add wave -divider "Master port"
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/mst_ace_reqs
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/mst_ace_resps
add wave -divider "Slave ports"
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/slv_ace_reqs
add wave -position end  sim:/tb_ace_ccu_top/i_ccu_dut/slv_ace_resps
onfinish stop
run -all
view wave
wave zoom full