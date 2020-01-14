## Generated SDC file "m3tc_compact.sdc"

## Copyright (C) 2016  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel MegaCore Function License Agreement, or other 
## applicable license agreement, including, without limitation, 
## that your use is for the sole purpose of programming logic 
## devices manufactured by Intel and sold by Intel or its 
## authorized distributors.  Please refer to the applicable 
## agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 16.1.0 Build 196 10/24/2016 SJ Standard Edition"

## DATE    "Wed Dec 05 12:37:17 2018"

##
## DEVICE  "5CGXFC7C7F23C8"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {CLK_Master} -period 10.000 -waveform { 0.000 5.000 } [get_ports {CLK_Master}]
create_clock -name {optical_Clk_1} -period 10.000 -waveform { 0.000 5.000 } [get_ports {optical_Clk_1}]


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {optical_Clk_1}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {optical_Clk_1}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {optical_Clk_1}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {optical_Clk_1}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {CLK_Master}]  0.100  
set_clock_uncertainty -rise_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {CLK_Master}]  0.100  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {optical_Clk_1}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {optical_Clk_1}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {optical_Clk_1}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {optical_Clk_1}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -rise_to [get_clocks {CLK_Master}]  0.100  
set_clock_uncertainty -fall_from [get_clocks {optical_Clk_1}] -fall_to [get_clocks {CLK_Master}]  0.100  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -rise_to [get_clocks {optical_Clk_1}]  0.100  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -fall_to [get_clocks {optical_Clk_1}]  0.100  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -rise_to [get_clocks {CLK_Master}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -rise_to [get_clocks {CLK_Master}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -fall_to [get_clocks {CLK_Master}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {CLK_Master}] -fall_to [get_clocks {CLK_Master}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -rise_to [get_clocks {optical_Clk_1}]  0.100  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -fall_to [get_clocks {optical_Clk_1}]  0.100  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -rise_to [get_clocks {CLK_Master}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -rise_to [get_clocks {CLK_Master}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -fall_to [get_clocks {CLK_Master}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {CLK_Master}] -fall_to [get_clocks {CLK_Master}] -hold 0.060  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

