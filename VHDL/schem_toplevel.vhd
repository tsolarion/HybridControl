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
-- CREATED		"Fri Jan 18 10:31:05 2019"

LIBRARY ieee;
USE ieee.std_logic_1164.all; 

LIBRARY work;

ENTITY schem_toplevel IS 
	PORT
	(

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
		 sig_o : OUT STD_LOGIC_VECTOR(12 DOWNTO 0)
	);
END COMPONENT;

SIGNAL	iref :  STD_LOGIC_VECTOR(12 DOWNTO 0);


BEGIN 




b2v_inst1 : signal_generator
GENERIC MAP(CNT_BIT_G => 8,
			MAX_DIV_CNT_G => 10000000,
			OUTW_G => 13
			)
PORT MAP(		 sig_o => iref);


END bdf_type;