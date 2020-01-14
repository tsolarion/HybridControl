# Create design library
vlib work
# Create and open project
project new . compile_project
project open compile_project
# Add source files to project
project addfile "C:/repositories/Michael/Code/Hybrid_Control/quartus_1module/schem_toplevel.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/16b_array.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/and_reduce_edge.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_deltaH_bound2.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_hyst_bounds.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_var_L.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/clk_div.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/dk_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/dutycycle_calc.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/fp_conversion.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hybrid_control.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hybrid_top_6.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hybrid_top1.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hybrid_top2.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hysteresis_calc.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/hysteresis_control.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/interlocking.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/m3tc_hybrid.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/median_conversion.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/median_filt.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/module_start.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/moving_avg.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/phase_shift_control.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/pi_control_bw_euler.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/pwm_st.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/ramp_table.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/runtime_limiter.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/schem_toplevel.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/signal_generator.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/signed_limiter.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/sin_table.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/startup.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/sync.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/sync_vec.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/enable_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/fp32_signed16_conv.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/fp32_signed16_conv_inst.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/iset_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/kixts_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/kp_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_16_11_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_16_12_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_16_18_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_16_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_17_16_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_17_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_18_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_26_divider.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_31b_divider.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_36_17_div.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_37_17_div.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_37_mult.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/my_46_33_div.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/vbush_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_ip/vbusl_const.vhd"
project addfile "C:/repositories/Michael/Code/Hybrid_Control/VHDL/calc_own/arithmetic.vhd"
# Calculate compilation order
project calculateorder
set compcmd [project compileall -n]
# Close project
project close
# Compile all files and report error
if [catch {eval $compcmd}] {
    exit -code 1
}