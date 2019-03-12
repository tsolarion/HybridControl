-- Copyright (C) 2017  Intel Corporation. All rights reserved.
-- Your use of Intel Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Intel Program License 
-- Subscription Agreement, the Intel Quartus Prime License Agreement,
-- the Intel FPGA IP License Agreement, or other applicable license
-- agreement, including, without limitation, that your use is for
-- the sole purpose of programming logic devices manufactured by
-- Intel and sold by Intel or its authorized distributors.  Please
-- refer to the applicable agreement for further details.

-- PROGRAM		"Quartus Prime"
-- VERSION		"Version 17.1.0 Build 590 10/25/2017 SJ Standard Edition"
-- CREATED		"Fri Jan 18 11:49:44 2019"

LIBRARY ieee;
USE ieee.std_logic_1164.all; 

LIBRARY work;

PACKAGE ARRAY2D IS
TYPE ARRAY2D0 IS ARRAY (0 TO 0,12 DOWNTO 0) OF STD_LOGIC;
END ARRAY2D;

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE work.ARRAY2D.all;

ENTITY schem_toplevel IS 
	PORT
	(
		Clk_Main :  IN  STD_LOGIC;
		nreset :  IN  STD_LOGIC;
		Ena_Signal :  IN  STD_LOGIC;
		Signal_Select :  IN  STD_LOGIC;
		soft_reset :  IN  STD_LOGIC;
		data_clk :  IN  STD_LOGIC;
		sample_clk :  IN  STD_LOGIC;
		hyst_ena :  IN  STD_LOGIC;
		amp_i :  IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
		fcw_i :  IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
		iL :  IN  ARRAY2D0;
		ki :  IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
		kp :  IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
		switch :  IN  STD_LOGIC_VECTOR(1 DOWNTO 0);
		V1 :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		V2 :  IN  STD_LOGIC_VECTOR(11 DOWNTO 0);
		Vc :  IN  STD_LOGIC_VECTOR(12 DOWNTO 0);
		PWM :  OUT  STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END schem_toplevel;

ARCHITECTURE bdf_type OF schem_toplevel IS 

COMPONENT signal_generator
GENERIC (CNT_BIT_G : INTEGER;
			MAX_DIV_CNT_G : INTEGER;
			OUTW_G : INTEGER
			);
	PORT(clk_i : IN STD_LOGIC;
		 nreset_i : IN STD_LOGIC;
		 enable_i : IN STD_LOGIC;
		 sig_select_i : IN STD_LOGIC;
		 amp_i : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		 fcw_i : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 sig_o : OUT STD_LOGIC_VECTOR(10 DOWNTO 0)
	);
END COMPONENT;

COMPONENT fp_conversion
GENERIC (MEAS_I_DATAWIDTH_G : INTEGER;
			NO_CONTROLER_G : INTEGER
			);
	PORT(clk_i : IN STD_LOGIC;
		 nreset_i : IN STD_LOGIC;
		 iset_i : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
		 kixts_fp_i : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		 kp_fp_i : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		 iset_o : OUT ARRAY2D0;
		 kixts_o : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		 kp_o : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
	);
END COMPONENT;

COMPONENT hybrid_top
GENERIC (A1_G : REAL;
			A2_G : REAL;
			A3_G : REAL;
			ANTI_WINDUP_G : INTEGER;
			CMAX_G : INTEGER;
			CORR_DELTA_G : INTEGER;
			D_IOUT_MAX_G : INTEGER;
			DATAWIDTH_G : INTEGER;
			DELTA_I_REF_G : INTEGER;
			DELTA_I_THR_G : INTEGER;
			DELTA_VC_G : INTEGER;
			F_CLK_G : REAL;
			FS_G : REAL;
			GAINBM_G : INTEGER;
			GAINBP_G : INTEGER;
			HYST_COND_SEL_G : STD_LOGIC_VECTOR(2 DOWNTO 0);
			L1_G : REAL;
			L2_G : REAL;
			L3_G : REAL;
			MAX_DELTA_G : INTEGER;
			MEAS_I_DATAWIDTH_G : INTEGER;
			MEAS_V_DATAWIDTH_G : INTEGER;
			N_CYCLE_REST_G : INTEGER;
			NINTERLOCK_G : INTEGER;
			NO_CONTROLER_G : INTEGER
			);
	PORT(clk_i : IN STD_LOGIC;
		 nreset_i : IN STD_LOGIC;
		 nsoftreset_i : IN STD_LOGIC;
		 data_clk_i : IN STD_LOGIC;
		 sample_clk_i : IN STD_LOGIC;
		 hyst_enable_i : IN STD_LOGIC;
		 imeas_i : IN ARRAY2D0;
		 iset_i : IN ARRAY2D0;
		 kixts_i : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		 kprop_i : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		 switch_i : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
		 vbush_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 vbusl_i : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		 vc_i : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 vc_switch_i : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 count_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 d_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 i_lower_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 i_upper_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 ierr_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 pi_o : OUT STD_LOGIC_VECTOR(0 TO 0 , 15 DOWNTO 0);
		 pwm_o : OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
	);
END COMPONENT;

SIGNAL	SYNTHESIZED_WIRE_0 :  STD_LOGIC_VECTOR(10 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_1 :  STD_LOGIC_VECTOR(0 TO 31);
SIGNAL	SYNTHESIZED_WIRE_2 :  STD_LOGIC_VECTOR(0 TO 31);
SIGNAL	SYNTHESIZED_WIRE_3 :  ARRAY2D0;


BEGIN 
SYNTHESIZED_WIRE_1 <= "00000000000000000000000000000000";
SYNTHESIZED_WIRE_2 <= "00000000000000000000000000000000";



b2v_inst1 : signal_generator
GENERIC MAP(CNT_BIT_G => 8,
			MAX_DIV_CNT_G => 10000000,
			OUTW_G => 11
			)
PORT MAP(clk_i => Clk_Main,
		 nreset_i => nreset,
		 enable_i => Ena_Signal,
		 sig_select_i => Signal_Select,
		 amp_i => amp_i,
		 fcw_i => fcw_i,
		 sig_o => SYNTHESIZED_WIRE_0);



b2v_instFP : fp_conversion
GENERIC MAP(MEAS_I_DATAWIDTH_G => 13,
			NO_CONTROLER_G => 1
			)
PORT MAP(clk_i => Clk_Main,
		 nreset_i => nreset,
		 iset_i => SYNTHESIZED_WIRE_0,
		 kixts_fp_i => SYNTHESIZED_WIRE_1,
		 kp_fp_i => SYNTHESIZED_WIRE_2,
		 iset_o => SYNTHESIZED_WIRE_3);



b2v_instHybrid : hybrid_top
GENERIC MAP(A1_G => 160.0,
			A2_G => 250.0,
			A3_G => 300.0,
			ANTI_WINDUP_G => 1600,
			CMAX_G => 1666,
			CORR_DELTA_G => 32,
			D_IOUT_MAX_G => 80,
			DATAWIDTH_G => 16,
			DELTA_I_REF_G => 800,
			DELTA_I_THR_G => 1280,
			DELTA_VC_G => 3200,
			F_CLK_G => 100000000.0,
			FS_G => 60096.0,
			GAINBM_G => 12,
			GAINBP_G => 4,
			HYST_COND_SEL_G => "111",
			L1_G => 0.00025,
			L2_G => 0.00025,
			L3_G => 0.00025,
			MAX_DELTA_G => 12800,
			MEAS_I_DATAWIDTH_G => 13,
			MEAS_V_DATAWIDTH_G => 12,
			N_CYCLE_REST_G => 1,
			NINTERLOCK_G => 50,
			NO_CONTROLER_G => 1
			)
PORT MAP(clk_i => Clk_Main,
		 nreset_i => nreset,
		 nsoftreset_i => soft_reset,
		 data_clk_i => data_clk,
		 sample_clk_i => sample_clk,
		 hyst_enable_i => hyst_ena,
		 imeas_i => iL,
		 iset_i => SYNTHESIZED_WIRE_3,
		 kixts_i => ki,
		 kprop_i => kp,
		 switch_i => switch,
		 vbush_i => V1,
		 vbusl_i => V2,
		 vc_i => Vc,
		 vc_switch_i => Vc,
		 pwm_o => PWM);


END bdf_type;