--==========================================================
-- Unit		:	hybrid_top(rtl)
-- File		:	hybrid_top.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file hybrid_top.vhd 
--! @author Michael Hersche
--! @date  10.10.2017

-- library ieee;
-- --! package for arrays 
-- use ieee.std_logic_1164.all;


library work; 
USE work.stdvar_arr_pkg.all;

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Top level of hybrid control 
--! @details Introduces usagage of master and multiple slaves 
entity top1 is
	generic( 	CMAX_G : integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock 
				NINTERLOCK_G		: integer := 50; --50
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
				DATAWIDTH_G			: integer := 16; --! General internal datawidth: THIS HAS TO BE KEPT CONSTANT
				-- PI settings 
				ANTI_WINDUP_G: integer 				:= 20*(2**5); --! maximum error for integration active 
				GAINBM_G	: natural range 0 to 16 := 12; 			--! fractional fixed points bit
				GAINBP_G	: natural range 1 to 16 := 4; 			--! integer bits
				--Kprop_G		: integer				:= 16384;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G		: integer				:= 5000; 	--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				-- Hysteresis settings 
				NO_CONTROLER_G 	: integer := 1; --!  Total number of controler used (slaves + master)
				DELTA_I_REF_G 		: integer := 25*(2**5); --! minimum set current change (25 A) for entering hysteresis mode 
				DELTA_I_THR_G 		: integer := 40*(2**5); --! minimum current difference (25 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G		: integer := 40*(2**5); --! Maximum current ripple after first rise (here 5A) 
				HYST_COND_SEL_G		: std_logic_vector(2 downto 0):= "111"; --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
				N_CYCLE_REST_G		: integer := 5 --! Number of cycles controller stays in Hysterssis after phaseshift 
		);
	port(
		clk_i			: in  std_logic;                               --! Main system clock 
		nreset_i    	: in  std_logic;                               --! asynchronous lowactive reset 
		nsoftreset_i	: in std_logic; 							--! softreset for whole PI chain including MAF 		
		data_clk_i 		: in std_logic; 								--! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic; 								--! ~2 MHz sample clk
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                    			
		vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
		vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic_vector(1 downto 0); -- switch signal 		
		imeas_i			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Measured current  
		iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Set current No.1 
		kprop_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
		pwm_o			: out std_logic_vector(2*NO_CONTROLER_G-1 downto 0) --! High switch output
		);			            							
end top1;

architecture rtl of top1 is 

-- ================== COMPONENTS =================================================
component hybrid_top is
	generic( 	CMAX_G : integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock 
				NINTERLOCK_G		: integer := 1; --50
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
				DATAWIDTH_G			: integer := 16; --! General internal datawidth: THIS HAS TO BE KEPT CONSTANT
				-- PI settings 
				ANTI_WINDUP_G: integer 				:= 20*(2**5); --! maximum error for integration active 
				GAINBM_G	: natural range 0 to 16 := 12; 			--! fractional fixed points bit
				GAINBP_G	: natural range 1 to 16 := 4; 			--! integer bits
				--Kprop_G		: integer				:= 16384;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G		: integer				:= 5000; 	--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				-- Hysteresis settings 
				NO_CONTROLER_G 		: integer := 6 ; --!  Total number of controler used (slaves + master)
				DELTA_I_REF_G 		: integer := 25*(2**5)*6; --! minimum set current change (25 A) for entering hysteresis mode 
				DELTA_I_THR_G 		: integer := 40*(2**5)*6; --! minimum current difference (25 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G		: integer := 40*(2**5); --! Maximum current ripple after first rise (here 5A) 
				HYST_COND_SEL_G		: std_logic_vector(2 downto 0):= "111"; --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
				N_CYCLE_REST_G		: integer := 5 --! Number of cycles controller stays in Hysterssis after phaseshift 
		);
	port(
		clk_i			: in  std_logic;                               --! Main system clock 
		nreset_i    	: in  std_logic;                               --! asynchronous lowactive reset 
		nsoftreset_i	: in std_logic; 							--! softreset for whole PI chain including MAF 		
		data_clk_i 		: in std_logic; 								--! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic; 								--! ~2 MHz sample clk
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                    			
		vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
		vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic_vector(1 downto 0); -- switch signal 		
		imeas_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Measured current  
		iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! Set current No.1 
		kprop_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
		pwm_o			: out std_logic_vector(2*NO_CONTROLER_G-1 downto 0); --! High switch output
		count_o			: out array_signed16(NO_CONTROLER_G-1 downto 0); --! PWM counter No.1 (testing)
		i_upper_o		: out array_signed16(NO_CONTROLER_G-1 downto 0); --! Hysteresis upper current bound No.1 (testing)
		i_lower_o		: out array_signed16(NO_CONTROLER_G-1 downto 0);  --! Hysteresis lower current bound No.2 (testing)
		d_o				: out array_signed16(NO_CONTROLER_G-1 downto 0);
		ierr_o			: out array_signed16(NO_CONTROLER_G-1 downto 0);
		pi_o			: out array_signed16(NO_CONTROLER_G-1 downto 0)
		);			            							
end component;
-- ================== CONSTANTS ==================================================				

	
	
-- =================== SIGNALS ===================================================
signal imeas_s : array_signed_in(NO_CONTROLER_G-1 downto 0); --! Intermediate measurement array (with one element)


-- =================== STATES ====================================================
	begin
	
	imeas_s(0) <= imeas_i; 
	
	
	inst_controller: hybrid_top 
	generic map( CMAX_G 			=> CMAX_G, 			
				NINTERLOCK_G		=> NINTERLOCK_G,		
				MEAS_I_DATAWIDTH_G 	=> MEAS_I_DATAWIDTH_G, 	
				MEAS_V_DATAWIDTH_G	=> MEAS_V_DATAWIDTH_G,	
				DATAWIDTH_G			=> DATAWIDTH_G,			
				-- PI settings       
				ANTI_WINDUP_G		=> ANTI_WINDUP_G,		
				GAINBM_G			=> GAINBM_G,			
				GAINBP_G			=> GAINBP_G,			
				--Kprop_G				=> Kprop_G,				
				--KixTs_G				=> KixTs_G,				
				-- Hysteresis settings 
				NO_CONTROLER_G 		=> NO_CONTROLER_G, 		
				DELTA_I_REF_G 		=> DELTA_I_REF_G, 		
				DELTA_I_THR_G 		=> DELTA_I_THR_G, 		
				DELTA_VC_G			=> DELTA_VC_G,			
				D_IOUT_MAX_G		=> D_IOUT_MAX_G,		
				HYST_COND_SEL_G		=> HYST_COND_SEL_G,		
				N_CYCLE_REST_G		=> N_CYCLE_REST_G		
		)
	port map(
		clk_i			=> clk_i,			
		nreset_i    	=> nreset_i,    
		nsoftreset_i	=> nsoftreset_i, 
		data_clk_i 		=> data_clk_i, 		
		sample_clk_i	=> sample_clk_i,	
		hyst_enable_i	=> hyst_enable_i,	
		vbush_i    		=> vbush_i,    		
		vbusl_i     	=> vbusl_i,     	
		vc_i 			=> vc_i, 			
		vc_switch_i 	=> vc_switch_i, 	
		switch_i		=> switch_i,		
		imeas_i			=> imeas_s,			
		iset_i			=> iset_i,		
		kprop_i			=>	kprop_i,			
		kixts_i			=> kixts_i,		
		pwm_o			=> pwm_o,			
		count_o			=> open, 			
		i_upper_o		=> open,		
		i_lower_o		=> open,		
		d_o				=> open,				
		ierr_o			=> open,			
		pi_o			=> open			
		);			            							

	
	
	
	
end rtl; 