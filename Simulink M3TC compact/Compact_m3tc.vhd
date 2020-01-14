-- Copyright (C) 2016  Intel Corporation. All rights reserved.
-- Your use of Intel Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Intel Program License 
-- Subscription Agreement, the Intel Quartus Prime License Agreement,
-- the Intel MegaCore Function License Agreement, or other 
-- applicable license agreement, including, without limitation, 
-- that your use is for the sole purpose of programming logic 
-- devices manufactured by Intel and sold by Intel or its 
-- authorized distributors.  Please refer to the applicable 
-- agreement for further details.

-- PROGRAM		"Quartus Prime"
-- VERSION		"Version 16.1.0 Build 196 10/24/2016 SJ Standard Edition"
-- CREATED		"Fri Dec 07 10:54:07 2018"

LIBRARY ieee;
USE ieee.std_logic_1164.all; 

LIBRARY work;

ENTITY Compact_m3tc IS 
	PORT
	(
		CLK_Master :  IN  STD_LOGIC;
		optical_Clk_1 :  IN  STD_LOGIC;
		nreset :  IN  STD_LOGIC;
		HIGH_Input :  IN  STD_LOGIC;
		masterCurrentMeas :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		masterCurrentRef :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		masterVOLT :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		MODE_put_to_3 :  IN  STD_LOGIC_VECTOR(2 DOWNTO 0);
		Number_12_bit3 :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		Number_8_bit :  IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		optical_fault_1 :  OUT  STD_LOGIC;
		gate_c_1 :  OUT  STD_LOGIC;
		gate_d_1 :  OUT  STD_LOGIC;
		gate_1_1 :  OUT  STD_LOGIC;
		gate_2_1 :  OUT  STD_LOGIC;
		gate_3_1 :  OUT  STD_LOGIC;
		gate_4_1 :  OUT  STD_LOGIC;
		rst_c_1 :  OUT  STD_LOGIC;
		rst_d_1 :  OUT  STD_LOGIC;
		rst_overall_1 :  OUT  STD_LOGIC;
		optical_fault_2 :  OUT  STD_LOGIC;
		gate_c_2 :  OUT  STD_LOGIC;
		gate_d_2 :  OUT  STD_LOGIC;
		gate_1_2 :  OUT  STD_LOGIC;
		gate_2_2 :  OUT  STD_LOGIC;
		gate_3_2 :  OUT  STD_LOGIC;
		gate_4_2 :  OUT  STD_LOGIC;
		rst_c_2 :  OUT  STD_LOGIC;
		rst_d_2 :  OUT  STD_LOGIC;
		rst_overall_2 :  OUT  STD_LOGIC;
		outFAULT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outFAULT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempHS_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempHS_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempIGBT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outTempIGBT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outOpticalSIGNAL_1 : OUT STD_LOGIC_VECTOR(4 downto 0);
		outOpticalSIGNAL_2 : OUT STD_LOGIC_VECTOR(4 downto 0);
		outVOLT_1 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		outVOLT_2 :  OUT  STD_LOGIC_VECTOR(11 DOWNTO 0);
		sw_Vprecontrol_o :  OUT  STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END Compact_m3tc;

ARCHITECTURE bdf_type OF Compact_m3tc IS 

COMPONENT m3tc_local
GENERIC (N_VDC_HIGH_G : INTEGER;
			N_VDC_LOW_G : INTEGER;
			T_DELAY_G : INTEGER;
			T_INTERLOCKING_G : INTEGER
			);
	PORT(nreset_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 opt_gate1_i : IN STD_LOGIC;
		 opt_gate2_i : IN STD_LOGIC;
		 fault_i : IN STD_LOGIC;
		 fault_gate_i : IN STD_LOGIC;
		 fault_c_i : IN STD_LOGIC;
		 fault_d_i : IN STD_LOGIC;
		 opt_mode_i : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
		 VoltMeas_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 reset_gates_o : OUT STD_LOGIC;
		 reset_c_o : OUT STD_LOGIC;
		 reset_d_o : OUT STD_LOGIC;
		 reset_Ready_o : OUT STD_LOGIC;
		 gate1_o : OUT STD_LOGIC;
		 gate2_o : OUT STD_LOGIC;
		 gate3_o : OUT STD_LOGIC;
		 gate4_o : OUT STD_LOGIC;
		 gateC_o : OUT STD_LOGIC;
		 gateD_o : OUT STD_LOGIC
	);
END COMPONENT;

COMPONENT modedetection
	PORT(nreset_i : IN STD_LOGIC;
		 opt_mode_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 ov_mode_o : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
	);
END COMPONENT;

COMPONENT master_serrializecommand
	PORT(clk_i : IN STD_LOGIC;
		 nreset_i : IN STD_LOGIC;
		 gate1_i : IN STD_LOGIC;
		 gate2_i : IN STD_LOGIC;
		 parallel_data_i : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		 gate1_o : OUT STD_LOGIC;
		 gate2_o : OUT STD_LOGIC;
		 serial_data_o : OUT STD_LOGIC
	);
END COMPONENT;

COMPONENT m3tc_master
GENERIC (MODE_CHARGE_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			MODE_DISCHARGE_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			MODE_IDLE_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			MODE_OP_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			MODE_RESET_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			MODE_BYPASS_G : STD_LOGIC_VECTOR(3 DOWNTO 0);
			N_CURRENTHIGH_G : INTEGER;
			N_CURRENTLOW_G : INTEGER;
			N_HIGHVOLT_S1_G : INTEGER;
			N_HIGHVOLT_SX_G : INTEGER;
			N_NUMBERMODULES_G : INTEGER;
			N_MODULES_STEP_G : INTEGER;
			N_VOLTHIGH_G : INTEGER;
			N_VOLTLOW_G : INTEGER;
			T_DELAY_G : INTEGER;
            T_VOLT_G  : INTEGER;
			T_INT_1200_G : INTEGER;
			T_INT_1700_G : INTEGER
			);
	PORT(nreset_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 fault_i : IN STD_LOGIC;
		 current_con_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 current_ref_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 mode_i : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
		 volt_S1_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 volt_S2_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 voltage_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 modules_o : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 sw_Vprecontrol_o : OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END COMPONENT;

COMPONENT sendingdata
GENERIC (N_BITS_G : INTEGER;
			N_BITS_TOTAL_G : INTEGER;
			START_SYMBOL_ERROR_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_TEMPHS_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_TEMPIGBT_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_VOLTAGE_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_MODE_G	: std_logic_vector(7 downto 0)
			);
	PORT(nreset_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 faultReport_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 tempHeatsink_i : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 tempIGBT_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 volt_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 mode_i		: in std_logic_vector(2 downto 0);
		 gate1_i	: in std_logic;
		 gate2_i	: in std_logic;
		 optical_o : OUT STD_LOGIC
	);
END COMPONENT;

COMPONENT faultdetection
GENERIC (ERROR_FAULT_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_READY_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_TEMPHS_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_TEMPIGBT_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_VOLT_G : STD_LOGIC_VECTOR(2 DOWNTO 0)
			);
	PORT(nreset_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 ready1_i : IN STD_LOGIC;
		 ready2_i : IN STD_LOGIC;
		 ready3_i : IN STD_LOGIC;
		 ready4_i : IN STD_LOGIC;
		 readyC_i : IN STD_LOGIC;
		 readyD_i : IN STD_LOGIC;
		 faultGates_i : IN STD_LOGIC;
		 faultC_i : IN STD_LOGIC;
		 faultD_i : IN STD_LOGIC;
		 tempHeatsink_i : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 temptIGBT_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 volt_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 fault_gate_o : OUT STD_LOGIC;
		 fault_c_o : OUT STD_LOGIC;
		 fault_d_o : OUT STD_LOGIC;
		 fault_o : OUT STD_LOGIC;
		 faultReport_o : OUT STD_LOGIC_VECTOR(11 DOWNTO 0)
	);
END COMPONENT;

COMPONENT receivedata
GENERIC (ERROR_FAULT_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_READY_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_TEMP_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_TEMPHS_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			ERROR_VOLT_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			START_SYMBOL_ERROR_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_TEMPHS_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_TEMPIGBT_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_VOLTAGE_G : STD_LOGIC_VECTOR(7 DOWNTO 0);
			START_SYMBOL_MODE_G		: std_logic_vector(7 downto 0)
			);
	PORT(nreset_i : IN STD_LOGIC;
		 clk_i : IN STD_LOGIC;
		 fault_i : IN STD_LOGIC;
		 data_i : IN STD_LOGIC;
		 fault_o : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
		 tempHS_o : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
		 tempIGBT_o : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
		 voltage_o : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
		 optical_signals_o 	: out std_logic_vector(4 downto 0)
	);
END COMPONENT;

SIGNAL	modul :  STD_LOGIC_VECTOR(7 DOWNTO 0);
SIGNAL	nreset_s :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_0 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_1 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_27 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_3 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_4 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_5 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_6 :  STD_LOGIC_VECTOR(2 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_7 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_28 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_10 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_11 :  STD_LOGIC_VECTOR(11 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_12 :  STD_LOGIC_VECTOR(11 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_13 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_14 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_15 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_17 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_18 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_19 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_20 :  STD_LOGIC_VECTOR(2 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_21 :  STD_LOGIC_VECTOR(11 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_23 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_24 :  STD_LOGIC_VECTOR(11 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_26 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_29 :  STD_LOGIC_VECTOR(4 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_30 :  STD_LOGIC_VECTOR(4 DOWNTO 0);

BEGIN 
optical_fault_1 <= SYNTHESIZED_WIRE_3; 
optical_fault_2 <= SYNTHESIZED_WIRE_17; 
outVOLT_1 <= SYNTHESIZED_WIRE_11;
outVOLT_2 <= SYNTHESIZED_WIRE_12;



b2v_inst : m3tc_local
GENERIC MAP(N_VDC_HIGH_G => 550,
			N_VDC_LOW_G => 0,
			T_DELAY_G => 40,
			T_INTERLOCKING_G => 250
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 opt_gate1_i => SYNTHESIZED_WIRE_0,
		 opt_gate2_i => SYNTHESIZED_WIRE_1,
		 fault_i => SYNTHESIZED_WIRE_3,
		 fault_gate_i => SYNTHESIZED_WIRE_27,
		 fault_c_i => SYNTHESIZED_WIRE_4,
		 fault_d_i => SYNTHESIZED_WIRE_5,
		 opt_mode_i => SYNTHESIZED_WIRE_6,
		 VoltMeas_i => Number_12_bit3,
		 reset_gates_o => rst_overall_1,
		 reset_c_o => rst_c_1,
		 reset_d_o => rst_d_1,
		 gate1_o => gate_1_1,
		 gate2_o => gate_2_1,
		 gate3_o => gate_3_1,
		 gate4_o => gate_4_1,
		 gateC_o => gate_c_1,
		 gateD_o => gate_d_1);


b2v_inst1 : modedetection
PORT MAP(nreset_i => nreset_s,
		 opt_mode_i => SYNTHESIZED_WIRE_7,
		 clk_i => optical_Clk_1,
		 ov_mode_o => SYNTHESIZED_WIRE_6);


SYNTHESIZED_WIRE_10 <= SYNTHESIZED_WIRE_3 OR SYNTHESIZED_WIRE_17;

b2v_inst16 : master_serrializecommand
PORT MAP(clk_i => CLK_Master,
		 nreset_i => nreset_s,
		 gate1_i => modul(2),
		 gate2_i => modul(3),
		 parallel_data_i => modul(7 DOWNTO 4),
		 gate1_o => SYNTHESIZED_WIRE_14,
		 gate2_o => SYNTHESIZED_WIRE_15,
		 serial_data_o => SYNTHESIZED_WIRE_13);


b2v_inst17 : master_serrializecommand
PORT MAP(clk_i => CLK_Master,
		 nreset_i => nreset_s,
		 gate1_i => modul(0),
		 gate2_i => modul(1),
		 parallel_data_i => modul(7 DOWNTO 4),
		 gate1_o => SYNTHESIZED_WIRE_0,
		 gate2_o => SYNTHESIZED_WIRE_1,
		 serial_data_o => SYNTHESIZED_WIRE_7);


b2v_inst18 : m3tc_master
GENERIC MAP(MODE_CHARGE_G => "0001",
			MODE_DISCHARGE_G => "0010",
			MODE_IDLE_G => "0000",
			MODE_OP_G => "0011",
			MODE_RESET_G => "0100",
			MODE_BYPASS_G => "0101",
			N_CURRENTHIGH_G => 300,
			N_CURRENTLOW_G => 10,
			N_HIGHVOLT_S1_G => 550,
			N_HIGHVOLT_SX_G => 1100,
			N_NUMBERMODULES_G => 2,
			N_MODULES_STEP_G => 1,
			N_VOLTHIGH_G => 585, 
			N_VOLTLOW_G => -20, -- it was -20 before...
			T_DELAY_G => 250, -- 200 before This is the amount of time that you wait till you sample the voltage again. This has to obviously be more than the interlocking time! Maybe PLUS the measurement delay PLUS an extra time for the capacitor discharge
            T_VOLT_G => 400,
            T_INT_1200_G => 250,
			T_INT_1700_G => 250
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => CLK_Master,
		 fault_i => SYNTHESIZED_WIRE_10,
		 current_con_i => masterCurrentMeas,
		 current_ref_i => masterCurrentRef,
		 mode_i => MODE_put_to_3,
		 volt_S1_i => SYNTHESIZED_WIRE_11,
		 volt_S2_i => SYNTHESIZED_WIRE_12,
		 voltage_i => masterVOLT,
		 modules_o => modul,
		 sw_Vprecontrol_o => sw_Vprecontrol_o);


b2v_inst2 : modedetection
PORT MAP(nreset_i => nreset_s,
		 opt_mode_i => SYNTHESIZED_WIRE_13,
		 clk_i => optical_Clk_1,
		 ov_mode_o => SYNTHESIZED_WIRE_20);


b2v_inst22 : m3tc_local
GENERIC MAP(N_VDC_HIGH_G => 550,
			N_VDC_LOW_G => 0,
			T_DELAY_G => 40,
			T_INTERLOCKING_G => 250
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 opt_gate1_i => SYNTHESIZED_WIRE_14,
		 opt_gate2_i => SYNTHESIZED_WIRE_15,
		 fault_i => SYNTHESIZED_WIRE_17, 
		 fault_gate_i => SYNTHESIZED_WIRE_28, 
		 fault_c_i => SYNTHESIZED_WIRE_18,
		 fault_d_i => SYNTHESIZED_WIRE_19,
		 opt_mode_i => SYNTHESIZED_WIRE_20,
		 VoltMeas_i => Number_12_bit3,
		 reset_gates_o => rst_overall_2,
		 reset_c_o => rst_c_2,
		 reset_d_o => rst_d_2,
		 gate1_o => gate_1_2,
		 gate2_o => gate_2_2,
		 gate3_o => gate_3_2,
		 gate4_o => gate_4_2,
		 gateC_o => gate_c_2,
		 gateD_o => gate_d_2);


b2v_inst3 : sendingdata
GENERIC MAP(N_BITS_G => 12,
			N_BITS_TOTAL_G => 20,
			START_SYMBOL_ERROR_G => "10011001",
			START_SYMBOL_TEMPHS_G => "11000011",
			START_SYMBOL_TEMPIGBT_G => "10000001",
			START_SYMBOL_VOLTAGE_G => "11100111",
			START_SYMBOL_MODE_G => "11011011"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 faultReport_i => SYNTHESIZED_WIRE_21,
		 tempHeatsink_i => Number_8_bit,
		 tempIGBT_i => Number_12_bit3,
		 volt_i => Number_12_bit3,
		 mode_i	=> SYNTHESIZED_WIRE_6, -- mode input
		 gate1_i => SYNTHESIZED_WIRE_0, -- gate 1
		 gate2_i => SYNTHESIZED_WIRE_1, -- gate 2
		 optical_o => SYNTHESIZED_WIRE_23);


b2v_inst4 : faultdetection
GENERIC MAP(ERROR_FAULT_G => "100",
			ERROR_READY_G => "101",
			ERROR_TEMPHS_G => "010",
			ERROR_TEMPIGBT_G => "011",
			ERROR_VOLT_G => "001"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 ready1_i => HIGH_Input,
		 ready2_i => HIGH_Input,
		 ready3_i => HIGH_Input,
		 ready4_i => HIGH_Input,
		 readyC_i => HIGH_Input,
		 readyD_i => HIGH_Input,
		 faultGates_i => HIGH_Input,
		 faultC_i => HIGH_Input,
		 faultD_i => HIGH_Input,
		 tempHeatsink_i => Number_8_bit,
		 temptIGBT_i => Number_12_bit3,
		 volt_i => Number_12_bit3,
		 fault_gate_o => SYNTHESIZED_WIRE_27,
		 fault_c_o => SYNTHESIZED_WIRE_4,
		 fault_d_o => SYNTHESIZED_WIRE_5,
		 fault_o => SYNTHESIZED_WIRE_3,
		 faultReport_o => SYNTHESIZED_WIRE_21);


b2v_inst5 : receivedata
GENERIC MAP(ERROR_FAULT_G => "100",
			ERROR_READY_G => "101",
			ERROR_TEMP_G => "011",
			ERROR_TEMPHS_G => "010",
			ERROR_VOLT_G => "001",
			START_SYMBOL_ERROR_G => "10011001",
			START_SYMBOL_TEMPHS_G => "11000011",
			START_SYMBOL_TEMPIGBT_G => "10000001",
			START_SYMBOL_VOLTAGE_G => "11100111",
			START_SYMBOL_MODE_G	=> "11011011"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => CLK_Master,
		 fault_i => SYNTHESIZED_WIRE_27,
		 data_i => SYNTHESIZED_WIRE_23,
		 fault_o => outFAULT_1,
		 tempHS_o => outTempHS_1,
		 tempIGBT_o => outTempIGBT_1,
		 voltage_o => SYNTHESIZED_WIRE_11,
		 --optical_signals_o => SYNTHESIZED_WIRE_29); -- where to save???
		optical_signals_o => outOpticalSIGNAL_1);

b2v_inst7 : sendingdata
GENERIC MAP(N_BITS_G => 12,
			N_BITS_TOTAL_G => 20,
			START_SYMBOL_ERROR_G => "10011001",
			START_SYMBOL_TEMPHS_G => "11000011",
			START_SYMBOL_TEMPIGBT_G => "10000001",
			START_SYMBOL_VOLTAGE_G => "11100111",
			START_SYMBOL_MODE_G => "11011011"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 faultReport_i => SYNTHESIZED_WIRE_24,
		 tempHeatsink_i => Number_8_bit,
		 tempIGBT_i => Number_12_bit3,
		 volt_i => Number_12_bit3,
		 mode_i	=> SYNTHESIZED_WIRE_6, -- mode input
		 gate1_i => SYNTHESIZED_WIRE_14, -- gate 1
		 gate2_i => SYNTHESIZED_WIRE_15, -- gate 2
		 optical_o => SYNTHESIZED_WIRE_26);


b2v_inst8 : faultdetection
GENERIC MAP(ERROR_FAULT_G => "100",
			ERROR_READY_G => "101",
			ERROR_TEMPHS_G => "010",
			ERROR_TEMPIGBT_G => "011",
			ERROR_VOLT_G => "001"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => optical_Clk_1,
		 ready1_i => HIGH_Input,
		 ready2_i => HIGH_Input,
		 ready3_i => HIGH_Input,
		 ready4_i => HIGH_Input,
		 readyC_i => HIGH_Input,
		 readyD_i => HIGH_Input,
		 faultGates_i => HIGH_Input,
		 faultC_i => HIGH_Input,
		 faultD_i => HIGH_Input,
		 tempHeatsink_i => Number_8_bit,
		 temptIGBT_i => Number_12_bit3,
		 volt_i => Number_12_bit3,
		 fault_gate_o => SYNTHESIZED_WIRE_28,
		 fault_c_o => SYNTHESIZED_WIRE_18,
		 fault_d_o => SYNTHESIZED_WIRE_19,
		 fault_o => SYNTHESIZED_WIRE_17,
		 faultReport_o => SYNTHESIZED_WIRE_24);


b2v_inst9 : receivedata
GENERIC MAP(ERROR_FAULT_G => "100",
			ERROR_READY_G => "101",
			ERROR_TEMP_G => "011",
			ERROR_TEMPHS_G => "010",
			ERROR_VOLT_G => "001",
			START_SYMBOL_ERROR_G => "10011001",
			START_SYMBOL_TEMPHS_G => "11000011",
			START_SYMBOL_TEMPIGBT_G => "10000001",
			START_SYMBOL_VOLTAGE_G => "11100111",
			START_SYMBOL_MODE_G	=> "11011011"
			)
PORT MAP(nreset_i => nreset_s,
		 clk_i => CLK_Master,
		 fault_i => SYNTHESIZED_WIRE_28,
		 data_i => SYNTHESIZED_WIRE_26,
		 fault_o => outFAULT_2,
		 tempHS_o => outTempHS_2,
		 tempIGBT_o => outTempIGBT_2,
		 voltage_o => SYNTHESIZED_WIRE_12,
		 --optical_signals_o => SYNTHESIZED_WIRE_30); -- where to save???
		optical_signals_o => outOpticalSIGNAL_2);
nreset_s <= nreset;

END bdf_type;