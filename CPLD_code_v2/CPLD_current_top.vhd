-- Copyright (C) 2017  Intel Corporation. All rights reserved.
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
-- VERSION		"Version 16.1.2 Build 203 01/18/2017 SJ Standard Edition"
-- CREATED		"Thu May 17 17:49:11 2018"

LIBRARY ieee;
USE ieee.std_logic_1164.all; 

LIBRARY work;

ENTITY CPLD_current_top IS 
	PORT
	(
		CLK_OSCI_100MHz :  IN  STD_LOGIC;
		DATA_ADC_raw :  IN  STD_LOGIC;
		CON_ADC :  OUT  STD_LOGIC;
		CLK_ADC_P :  OUT  STD_LOGIC;
		CLK_ADC_N :  OUT  STD_LOGIC;
		Data_Out_p :  OUT  STD_LOGIC;
		Data_Out_n :  OUT  STD_LOGIC
	);
END CPLD_current_top;

ARCHITECTURE bdf_type OF CPLD_current_top IS 

COMPONENT statemachine
GENERIC (bits_resolution : INTEGER;
			CONV_CYCLE_G : INTEGER;
			CONV_WAIT_CYCLE_G : INTEGER;
			Total_cycle_G : INTEGER
			);
	PORT(clk : IN STD_LOGIC;
		 data_i : IN STD_LOGIC;
		 cnv_o : OUT STD_LOGIC;
		 clock_MAF : OUT STD_LOGIC;
		 sck_oP : OUT STD_LOGIC;
		 sck_oN : OUT STD_LOGIC;
		 sample_o : OUT STD_LOGIC_VECTOR(12 DOWNTO 0)
	);
END COMPONENT;

COMPONENT serialize16b20b
GENERIC (End_Symbol : STD_LOGIC_VECTOR(2 DOWNTO 0);
			n_bits_g : INTEGER;
			n_bits_total : INTEGER;
			start_Symbol : STD_LOGIC_VECTOR(3 DOWNTO 0)
			);
	PORT(reset_n : IN STD_LOGIC;
		 clk : IN STD_LOGIC;
		 parallel_data : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 serial_data : OUT STD_LOGIC
	);
END COMPONENT;

COMPONENT moving_avg
GENERIC (IN_WIDTH : INTEGER;
			NSAMPLES : INTEGER
			);
	PORT(clk_i : IN STD_LOGIC;
		 clk_sample : IN STD_LOGIC;
		 nreset_i : IN STD_LOGIC;
		 din_valid_i : IN STD_LOGIC;
		 sample_i : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 average_o : OUT STD_LOGIC_VECTOR(12 DOWNTO 0)
	);
END COMPONENT;

SIGNAL	SYNTHESIZED_WIRE_0 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_1 :  STD_LOGIC_VECTOR(12 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_2 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_7 :  STD_LOGIC;
SIGNAL	SYNTHESIZED_WIRE_5 :  STD_LOGIC_VECTOR(12 DOWNTO 0);
SIGNAL	SYNTHESIZED_WIRE_6 :  STD_LOGIC;


BEGIN 
Data_Out_p <= SYNTHESIZED_WIRE_6;
SYNTHESIZED_WIRE_0 <= '1';
SYNTHESIZED_WIRE_7 <= '1';



b2v_inst : statemachine
GENERIC MAP(bits_resolution => 14,
			CONV_CYCLE_G => 4,
			CONV_WAIT_CYCLE_G => 2,
			Total_cycle_G => 21
			)
PORT MAP(clk => CLK_OSCI_100MHz,
		 data_i => DATA_ADC_raw,
		 cnv_o => CON_ADC,
		 clock_MAF => SYNTHESIZED_WIRE_2,
		 sck_oP => CLK_ADC_P,
		 sck_oN => CLK_ADC_N,
		 sample_o => SYNTHESIZED_WIRE_5);


b2v_inst22 : serialize16b20b
GENERIC MAP(End_Symbol => "010",
			n_bits_g => 13,
			n_bits_total => 20,
			start_Symbol => "0110"
			)
PORT MAP(reset_n => SYNTHESIZED_WIRE_0,
		 clk => CLK_OSCI_100MHz,
		 parallel_data => SYNTHESIZED_WIRE_1,
		 serial_data => SYNTHESIZED_WIRE_6);



b2v_inst4 : moving_avg
GENERIC MAP(IN_WIDTH => 13,
			NSAMPLES => 2
			)
PORT MAP(clk_i => CLK_OSCI_100MHz,
		 clk_sample => SYNTHESIZED_WIRE_2,
		 nreset_i => SYNTHESIZED_WIRE_7,
		 din_valid_i => SYNTHESIZED_WIRE_7,
		 sample_i => SYNTHESIZED_WIRE_5,
		 average_o => SYNTHESIZED_WIRE_1);



Data_Out_n <= NOT(SYNTHESIZED_WIRE_6);



END bdf_type;