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
entity hybrid_top is
	generic( 	CMAX_G 				: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock 
				FS_G 				: real 	  := 60096.0; --! PWM frequency 
				F_CLK_G				: real 	  := 100.0*(10**6); --! Clock frequency  
				NINTERLOCK_G		: integer := 50; --50
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
				DATAWIDTH_G			: integer := 16; --! General internal datawidth: THIS HAS TO BE KEPT CONSTANT
				-- MAF settings 
				MAX_DELTA_G: natural := 200*(2**5); 				--! MAF: limitation of current change for storing in buffer   
				CORR_DELTA_G: natural := 1*(2**5); 				--! MAF: If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
				-- PI settings 
				ANTI_WINDUP_G		: integer 				:= 50*(2**5); --! maximum error for integration active 
				GAINBM_G			: natural range 0 to 16 := 12; 			--! fractional fixed points bit
				GAINBP_G			: natural range 1 to 16 := 4; 			--! integer bits
				--Kprop_G				: integer				:= 16384;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G				: integer				:= 5000; 	--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				-- Hysteresis settings 
				NO_CONTROLER_G 		: integer := 6 ; --!  Total number of controler used (slaves + master)
				DELTA_I_REF_G 		: integer := 10*(2**5)*6; --! minimum set current change (10 A) for entering hysteresis mode 
				DELTA_I_THR_G 		: integer := 40*(2**5)*6; --! minimum current difference (40 A) between measured and set current for entering hysteresis mode 
				DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G		: integer := 20*(2**5); --! Maximum current ripple after first rise (here 20A) 
				HYST_COND_SEL_G		: std_logic_vector(2 downto 0):= "011"; --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
				N_CYCLE_REST_G		: integer := 1; --! Number of cycles controller stays in Hysterssis after phaseshift 
				-- Variable L points
				L1_G				: real 	  := 0.00025;--0.00013; --! Inductance [H] at point 1 
				L2_G 				: real 	  := 0.00025;--0.000115; --! Inductance [H] at point 2 
				L3_G 				: real 	  := 0.00025;--0.00003; --! Inductance [H] at point 3 
				A1_G				: real	  := 160.0; --! Current [A] corner 1 
				A2_G 				: real	  := 250.0; --! Current [A] corner 2 
				A3_G 				: real	  := 300.0  --! Current [A] corner 3 
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
		pi_o			: out array_signed16(NO_CONTROLER_G-1 downto 0); 
		iset_tot_o		: out std_logic_vector(11 downto 0); --! total measured current only integer bits
		imeas_tot_o		: out std_logic_vector(11 downto 0)  --! total measured current only integer bits 
		);			            							
end hybrid_top;

architecture rtl of hybrid_top is 

-- ================== COMPONENTS =================================================
	component hybrid_control is
	generic( CMAX_G 			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock   
			NINTERLOCK_G		: integer := 50; 
			MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 12;  --! Data width of current measurements  
			MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
			DATAWIDTH_G			: integer := 16; --! General internal datawidth 
			-- MAF settings 
			MAX_DELTA_G: natural := 100; 				--! MAF: limitation of current change for storing in buffer   
			CORR_DELTA_G: natural := 0;					--! MAF: If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
			-- PI settings 
			ANTI_WINDUP_G: integer 				:= 20*(2**5); --! maximum error for integration active 
			GAINBM_G	: natural range 0 to 16 := 1; 		--! fractional fixed points bit
			GAINBP_G	: natural range 1 to 16 := 2; 		--! integer bits
			--Kprop_G		: integer				:= 4;		--! Proportional gain:  Kp*(2**GAINBM)
			--KixTs_G		: integer				:= 1;		--! Integral gain:  (Ki/fs)*(2**GAINBM)	
			-- Hysteresis settings 
			NO_CONTROLER_G 		: integer := 2; --!  Total number of controler used (slaves + master)
			MY_NUMBER_G 		: integer := 1; --! index of current slave: 0 indicates master 
			DELTA_I_REF_G 		: integer := 25*(2**5); --! minimum set current change (25 A) for entering hysteresis mode 
			DELTA_I_THR_G 		: integer := 10*(2**5); --! minimum current difference (25 A) between measured and set current for entering hysteresis mode 
			DELTA_VC_G			: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
			D_IOUT_MAX_G		: integer := 5*(2**5); --! Maximum current ripple after first rise (here 5A) 
			N_CYCLE_REST_G		: integer := 0 --! Number of cycles controller stays in Hysterssis after phaseshift 
		);
	port(
		clk_i			: in  std_logic;  --! Main system clock 
		nreset_i    	: in  std_logic;  --! asynchronous lowactive reset 
		nsoftreset_i	: in std_logic; 							--! softreset for whole PI chain including MAF 		
		data_clk_i 		: in std_logic;	  --! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic;   --! ~2 MHz sample clk 
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in  unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                              			
		vbusl_i     	: in  unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 	
		vc_i 			: in  signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic_vector(1 downto 0); -- switch signal 		
		imeas_i			: in  signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Measured current 
		iset_i			: in  signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Set current 
		imeas_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total measurement current 
		iset_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total set current 
		kprop_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i			: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
		hyst_cond_sel_i	: in std_logic_vector(2 downto 0); --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
		pi_o			: out signed(DATAWIDTH_G-1 downto 0); --! Output of PI controller (only for testing)
		pwm1_o			: out std_logic;  --! High switch output
		pwm2_o			: out std_logic;  --! Low switch output 
		pwm_ma_start_i	: in  std_logic; --! Start of master pwm cycle (for slaves)
		pwm_ma_start_o	: out std_logic; --! Start of master pwm cycle (for master)
		hyst_t1_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t1 during hysteresis control of all modules (0: master) 
		hyst_o			: out std_logic; 
		hyst_t1_o 		: out std_logic;--! Start of point t1 during hysteresis control of this module 
		hyst_t2_o		: out std_logic; --! Start of SECOND_UP of this module
		hyst_vec_i		: in std_logic_vector(NO_CONTROLER_G-1 downto 0);  --! hystersis mode of all modules  		
		hyst_t2_ma_i	: in std_logic; --! Start of SECOND_UP of master module 		
		hss_bound_i		: in signed(DATAWIDTH_G-1 downto 0); --! hss_bound	 	
		deltaH_ready_i	: in std_logic; --! calculation of deltaH finished 
		deltaH_i 		: in signed(DATAWIDTH_G-1 downto 0); --! signed output value dH 
		nreset_pwm_o	: out std_logic; --! soft reset of PI chain, used for reset the phase shift enable signal 
		imeas_avg_o 	: out signed(DATAWIDTH_G-1 downto 0); --! error measurement averaged (for testing)
		ierr_o			: out signed(DATAWIDTH_G-1 downto 0); --! error measurement (for testing)
		d_o				: out signed(DATAWIDTH_G-1 downto 0); --! duty cycle out (for testing) 
		pwm_count_o		: out signed(DATAWIDTH_G-1 downto 0); --! pwm counter (for testing) 
		i_upper_o		: out signed(DATAWIDTH_G-1 downto 0); --! hysteresis upper current bound (for testing) 
		i_lower_o		: out signed(DATAWIDTH_G-1 downto 0) --! hysteresis lower current bound (for testing) 
		);			            								
	end component;
	
	
	component hysteresis_calc is 
	generic( CMAX_G 			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock   
			 MEAS_I_DATAWIDTH_G : integer range 8 to 16 := 12;  --! Data width of current measurements  
			 MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
			 NO_CONTROLER_G 	: integer := 2; --!  Total number of controler used (slaves + master)
			 DATAWIDTH_G		: integer := 16; --! internal data width for calculations 
			 NINTERLOCK_G		: natural := 50; -- number of interlock clocks
			 FS_G 				: real 	  := 60000.0; --! Switching frequency 
			 F_CLK_G			: real 	  := 100.0*(10**6); --! Clock frequency  
			 L1_G				: real 	  := 0.00025;--0.00013; --! Inductance [H] at point 1 
			 L2_G 				: real 	  := 0.00025;--0.000115; --! Inductance [H] at point 2 
			 L3_G 				: real 	  := 0.00025;--0.00003; --! Inductance [H] at point 3 
			 A1_G				: real	  := 160.0; --! Current [A] corner 1 
			 A2_G 				: real	  := 250.0; --! Current [A] corner 2 
			 A3_G 				: real	  := 300.0  --! Current [A] corner 3 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage
			vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			imeas_i			: in  array_signed_in(NO_CONTROLER_G-1 downto 0); --! individual measured current  
			iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --!
			hyst_i	: in std_logic; 
			hyst_t1_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t1 during hysteresis control of all modules (0: master) 
			hyst_t2_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t2 during hysteresis control of all modules (0: master) 
			nreset_phase_shift_i: in std_logic; --! reset phase shift enable signal 
			hss_bound_o 	: out signed(DATAWIDTH_G-1 downto 0); --! signed output value
			imeas_tot_o		: out signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0);--! signed total measurement current 
			iset_tot_o		: out signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0);--! signed total set current 
			deltaH_ready_o	: out std_logic_vector(NO_CONTROLER_G-1 downto 1); --! calculation of deltaH finished 
			deltaH_o 		: out array_signed16(NO_CONTROLER_G-1 downto 1) --! signed output value dH 
			);
	end component;
	
-- ================== CONSTANTS ==================================================				
	constant HIGH_C		: std_logic := '1'; 
	constant LOW_C 		: std_logic := '0'; 
	
	
-- =================== SIGNALS ===================================================
	signal pwm_ma_start_s: std_logic := LOW_C; --! Start of master pwm cylce 
	signal hyst_vec_s : std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '0'); --! Hysteresis mode of all modules
	signal hyst_t1_vec_s: std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '0'); --! Start of point t1 during hysteresis control
	signal hyst_t2_vec_s: std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '0'); --! Start of point t1 during hysteresis control
	signal nreset_pwm_master_s : std_logic := LOW_C; 
	signal hss_bound_s : signed(15 downto 0); 
	signal deltaH_ready_s: std_logic_vector(NO_CONTROLER_G-1 downto 1); --! calculation of deltaH finished 
	signal deltaH_s 	: array_signed16(NO_CONTROLER_G-1 downto 1); --! signed output value dH 
	signal imeas_tot_s: signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! total measured current 
	signal iset_tot_s : signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! total measured current 
-- =================== STATES ====================================================
	begin
	
		
	-- master declaration 
	inst_master : hybrid_control
	generic map(CMAX_G 				=> CMAX_G, 
				NINTERLOCK_G		=> NINTERLOCK_G, 
				MEAS_I_DATAWIDTH_G 	=> MEAS_I_DATAWIDTH_G,
				MEAS_V_DATAWIDTH_G 	=> MEAS_V_DATAWIDTH_G,
				MAX_DELTA_G			=> MAX_DELTA_G,
				CORR_DELTA_G		=> CORR_DELTA_G,
				ANTI_WINDUP_G		=> ANTI_WINDUP_G, 
				GAINBM_G			=> GAINBM_G,	 	
				GAINBP_G			=> GAINBP_G,
				--Kprop_G				=> Kprop_G,		
				--KixTs_G				=> KixTs_G,
				NO_CONTROLER_G		=> NO_CONTROLER_G, -- Total number of Controler used
				MY_NUMBER_G 		=> 0, -- indice of current slave: 0 indicates master  -- indice of current slave: 0 indicates master 
				DELTA_I_REF_G 		=> DELTA_I_REF_G, 	
				DELTA_I_THR_G 		=> DELTA_I_THR_G, 	
				DELTA_VC_G			=> DELTA_VC_G, 
				D_IOUT_MAX_G		=> D_IOUT_MAX_G,
				N_CYCLE_REST_G		=> N_CYCLE_REST_G
		)
	port map(
		clk_i			=> clk_i,                               --system clock
		nreset_i    	=> nreset_i,                            --asynchronous nreset_i
		nsoftreset_i	=> nsoftreset_i, 
		data_clk_i 		=> data_clk_i, 							-- 60 KHz clock 
		sample_clk_i	=> sample_clk_i, 						-- 2 MHz sample clk 
		hyst_enable_i	=> hyst_enable_i,
		vbush_i    		=> vbush_i,                                     			
		vbusl_i     	=> vbusl_i,  	
		vc_i 			=> vc_i, 
		vc_switch_i		=> vc_switch_i, 	 	
		switch_i		=> switch_i,		
		imeas_i			=> imeas_i(0),	-- Measured current 
		iset_i			=> iset_i(0),  -- Set current 
		imeas_tot_i		=> imeas_tot_s, 	
		iset_tot_i		=> iset_tot_s,
		kprop_i			=> kprop_i,						
		kixts_i			=> kixts_i,			
		hyst_cond_sel_i => HYST_COND_SEL_G, 
		pi_o			=> pi_o(0), -- Output of PI controller 
		pwm1_o			=> pwm_o(0),  -- pwm output 
		pwm2_o			=> pwm_o(1), 
		pwm_ma_start_i	=> LOW_C, -- only for slave modules 
		pwm_ma_start_o	=> pwm_ma_start_s, -- only for master module 
		hyst_t1_vec_i	=> hyst_t1_vec_s, 
		hyst_o			=> hyst_vec_s(0), 
		hyst_t1_o 		=> hyst_t1_vec_s(0), 
		hyst_t2_o		=> hyst_t2_vec_s(0),
		hyst_vec_i		=> hyst_vec_s, 
		hyst_t2_ma_i	=> LOW_C,
		hss_bound_i		=> hss_bound_s,
		deltaH_ready_i	=> LOW_C,	
		deltaH_i 		=> (others => '0'), 		
		nreset_pwm_o	=> nreset_pwm_master_s, 
		imeas_avg_o 	=> open, 
		ierr_o			=> ierr_o(0), 
		d_o				=> d_o(0), 
		pwm_count_o		=> count_o(0), 
		i_upper_o		=> i_upper_o(0),
		i_lower_o		=> i_lower_o(0)
		);			            								--signal for lower switch
	
	
	-- slave declaration 
	
	--generate for loop 
	SLAVE_MODULE: 
		for I in 1 to NO_CONTROLER_G-1 generate
			REGX : hybrid_control
         
			generic map(CMAX_G 				=> CMAX_G, 
						NINTERLOCK_G		=> NINTERLOCK_G, 
						MEAS_I_DATAWIDTH_G 	=> MEAS_I_DATAWIDTH_G,
						MEAS_V_DATAWIDTH_G 	=> MEAS_V_DATAWIDTH_G, 
						MAX_DELTA_G			=> MAX_DELTA_G,
						CORR_DELTA_G		=> CORR_DELTA_G,
						ANTI_WINDUP_G		=> ANTI_WINDUP_G, 
						GAINBM_G			=> GAINBM_G,	 	
						GAINBP_G			=> GAINBP_G,
						--Kprop_G				=> Kprop_G,		
						--KixTs_G				=> KixTs_G,
						NO_CONTROLER_G		=> NO_CONTROLER_G, -- Total number of Controler used
						MY_NUMBER_G 		=> I, -- indice of current slave: 0 indicates master  -- indice of current slave: 0 indicates master 
						DELTA_I_REF_G 		=> DELTA_I_REF_G, 	
						DELTA_I_THR_G 		=> DELTA_I_THR_G, 
						DELTA_VC_G			=> DELTA_VC_G, 						
						D_IOUT_MAX_G		=> D_IOUT_MAX_G, 
						N_CYCLE_REST_G		=> N_CYCLE_REST_G
				)
			port map(
				clk_i			=> clk_i,                               --system clock
				nreset_i    	=> nreset_i,                            --asynchronous nreset_i
				nsoftreset_i	=> nsoftreset_i, 
				data_clk_i 		=> data_clk_i, 							-- 60 KHz clock 
				sample_clk_i	=> sample_clk_i, 						-- 2 MHz sample clk 
				hyst_enable_i	=> hyst_enable_i,
				vbush_i    		=> vbush_i,                                     			
				vbusl_i     	=> vbusl_i,  	
				vc_i 			=> vc_i, 
				vc_switch_i		=> vc_switch_i, 	 	
				switch_i		=> switch_i,		
				imeas_i			=> imeas_i(I),	-- Measured current 
				iset_i			=> iset_i(I),  -- Set current 
				imeas_tot_i		=> imeas_tot_s, 	
				iset_tot_i		=> iset_tot_s, 	
				kprop_i			=> kprop_i,						
				kixts_i			=> kixts_i,	
				hyst_cond_sel_i => HYST_COND_SEL_G,
				pi_o			=> pi_o(I), -- Output of PI controller 
				pwm1_o			=> pwm_o(2*I),  -- pwm output 
				pwm2_o			=> pwm_o(2*I+1), 
				pwm_ma_start_i	=> pwm_ma_start_s, -- only for slave modules 
				pwm_ma_start_o	=> open, -- only for master module 
				hyst_t1_vec_i	=> hyst_t1_vec_s, 
				hyst_o			=> hyst_vec_s(I), 
				hyst_t1_o 		=> hyst_t1_vec_s(I), 
				hyst_t2_o		=> hyst_t2_vec_s(I), 
				hyst_vec_i		=> hyst_vec_s, 
				hyst_t2_ma_i	=> hyst_t2_vec_s(0),
				hss_bound_i		=> hss_bound_s,
				deltaH_ready_i	=> deltaH_ready_s(I),	
				deltaH_i 		=> deltaH_s(I), 		
				nreset_pwm_o	=> open, 
				imeas_avg_o 	=> open,
				ierr_o			=> ierr_o(I),  
				d_o				=> d_o(I), 
				pwm_count_o		=> count_o(I),
				i_upper_o		=> i_upper_o(I),
				i_lower_o		=> i_lower_o(I)
				);			            								--signal for lower switch
	
	  end generate SLAVE_MODULE;
	
	
	inst_hyst_calc: hysteresis_calc 
	generic map( 	CMAX_G 				=> CMAX_G, 
					MEAS_I_DATAWIDTH_G 	=> MEAS_I_DATAWIDTH_G,
					MEAS_V_DATAWIDTH_G 	=> MEAS_V_DATAWIDTH_G, 
					NO_CONTROLER_G		=> NO_CONTROLER_G,
					DATAWIDTH_G			=> DATAWIDTH_G,
					NINTERLOCK_G		=> NINTERLOCK_G,
					FS_G 				=> FS_G, 	
					F_CLK_G				=> F_CLK_G,	
					L1_G				=> L1_G	,
					L2_G 				=> L2_G ,	
					L3_G 				=> L3_G ,	
					A1_G				=> A1_G	,
					A2_G 				=> A2_G ,	
					A3_G 				=> A3_G 	
			)		
	port map( clk_i			=> clk_i,                               --system clock				
			nreset_i    	=> nreset_i,                            --asynchronous nreset_i
			vbush_i    		=> vbush_i, 
			vbusl_i     	=> vbusl_i, 
			vc_i 			=> vc_i, 
			imeas_i			=> imeas_i,				
			iset_i			=> iset_i,			
			hyst_i			=> hyst_vec_s(0), 
			hyst_t1_vec_i	=> hyst_t1_vec_s,
			hyst_t2_vec_i	=> hyst_t2_vec_s,
			nreset_phase_shift_i => nreset_pwm_master_s, 
			hss_bound_o 	=> hss_bound_s,
			imeas_tot_o		=> imeas_tot_s,		
			iset_tot_o		=> iset_tot_s,			
			deltaH_ready_o	=> deltaH_ready_s,	
			deltaH_o 		=> deltaH_s 		
			);
			
	imeas_tot_o <= std_logic_vector(resize(imeas_tot_s(imeas_tot_s'length -1 downto 5),12)); 
	iset_tot_o  <= std_logic_vector(resize(iset_tot_s(iset_tot_s'length -1 downto 5),12)); 
			
end rtl; 