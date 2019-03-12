--==========================================================
-- Unit		:	hybrid_control(rtl)
-- File		:	hybrid_control.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	hysteresis_control, moving_avg, pi_control_bw_euler, dutycycle_calc, pwm_st, phase_shift_control
--==========================================================

--! @file hybrid_control.vhd
--! @author Michael Hersche, Pascal Zaehner
--! @date  21.11.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Implements one single controller module 
--! @details Interconnection with PI chain and Hysteresis control 
--! @details Module can either be slave or master, this module makes the appropriate connections 

entity hybrid_control is
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
		nsoftreset_i	: in std_logic; --! softreset for whole PI chain including MAF 
		data_clk_i 		: in std_logic;	  --! ~60 KHz clock PWM  
		sample_clk_i	: in std_logic;   --! ~2 MHz sample clk 
		hyst_enable_i	: in std_logic; --! enables hysteresis mode			
		vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage                                              			
		vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage 	
		vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
		vc_switch_i 	: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! switchable input signal vc (00: no operation, 01: +, 10: -)
		switch_i		: in std_logic_vector(1 downto 0); -- switch signal 		
		imeas_i			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Measured current 
		iset_i			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Set current 
		imeas_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total measurement current 
		iset_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total set current 
		kprop_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control proportional gain:  kprop_i = Kp*(2**GAINBM)
		kixts_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! PI control integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
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
	end hybrid_control;

architecture rtl of hybrid_control is 

	-- ================== COMPONENTS =================================================
	
	
	--! Moving average filter 
	component moving_avg is
		generic(
			NSAMPLES : natural := 32; --! Number of samples from 2 MHz to 60 KHz: 2e6/60e3 =~  34
			IN_WIDTH : natural range 8 to 17 := 12; --! input data width 
			MAX_DELTA_G: natural := 100; 				--! Limitation of current change for storing in buffer   
			CORR_DELTA_G: natural := 0					--! If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
		);
		port(
			clk_i 		: in std_logic;					--! Clock
			nreset_i 	: in std_logic;					--! Reset
			nsoftreset_i: in std_logic; 				--! soft reset 
			din_valid_i : in std_logic;					--! Flag for valid input data
			sample_i 	: in signed(IN_WIDTH-1 downto 0);	--! Signal to be averaged
			average_o 	: out signed(IN_WIDTH-1 downto 0)	--! Average value
		);
	end component;

	--! PI backward euler 
	component pi_control_bw_euler is 
		generic( 	-- default Kp = 2; Ki = 20000 -> KIs = 0.5, assuming fs = 20000 Hz
				INW_G 		: natural range 1 to 64 := 20; 		--! input bits
				OUTW_G		: natural range 1 to 64 := 20; 
				ANTI_WINDUP_G: integer 				:= 20*(2**5); --! maximum error for integration active 
				GAINBM_G	: natural range 0 to 16 := 1; 		--! fractional fixed points bit
				GAINBP_G	: natural range 1 to 16 := 2 		--! integer bits
				--Kprop_G		: integer				:= 4;		--! Proportional gain:  Kp*(2**GAINBM)
				--KixTs_G		: integer				:= 1		--! Integral gain:  (Ki/fs)*(2**GAINBM)	
				);		
		port( 	clk_i		: in std_logic; --! Main clock 
				nreset_i	: in std_logic; --! Main asynchronous reset low active
				nsoftreset_i: in std_logic; --! Synchronous reset signal low active 
				int_enable_i: in std_logic; --! Enable integral part 
				data_i		: in signed(INW_G-1 downto 0); --! Input data 
				data_valid_i: in std_logic; --! rising edge indicates new data 
				kprop_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! Proportional gain:  kprop_i = Kp*(2**GAINBM)
				kixts_i		: in signed(GAINBM_G + GAINBP_G -1 downto 0);  --! Integral gain:  kixts = (Ki/fs)*(2**GAINBM)	
				result_o 	: out signed(OUTW_G-1 downto 0); --! Output data 			
				result_valid_o: out std_logic
				);
				
	end component;

	component dutycycle_calc is 
	generic( 	
			INW_G 		: natural range 1 to 64 := 16; 		--! Controller input data size 
			OUTW_G		: natural range 1 to 63 := 11; 		--! Output data width 
			NINTERLOCK_G		: integer := 50
			);		
	port( 	clk_i		: in std_logic; --! Main clock 
			nreset_i	: in std_logic; --! Main asynchronous reset low active
			nsoftreset_i: in std_logic; --! Synchronous reset signal low active 
			pi_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! data originating from PI Controller 
			pi_valid_i	: in std_logic; --! new PI value valid 
			vc_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vc(feed forward)  
			vc_switch_i : in signed(INW_G-1 downto 0) := (others => '0'); --! switchable input signal vc (00: no operation, 01: +, 10: -)
			switch_i	: in std_logic_vector(1 downto 0) := (others => '0'); -- switch signal 
			vbush_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vbush
			vbusl_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! measurement data Vbusl
			iset_i		: in signed(INW_G-1 downto 0) := (others => '0'); --! input set current 
			half_duty_i : in std_logic := '0'; --! use only half of duty cycle (in startup) 
			d_o 		: out unsigned(OUTW_G-1 downto 0) := (others => '0') --! Dutycycle output 		
			);
	end component; 

	--! @brief PWM SAWTOOTH
	component pwm_st is 
	generic(
			CNT_RES_G : integer :=12; --! counter resolution in bits
			CNT_TOP_G : integer := 4095; --! upper limit for the reference signal (depends on the scaling of the duty_i cycle)
			INIT_CNT_G : integer range 0 to 4095 :=0; --! this is for initial phase shift if need be
			CNT_INTERLOCK_G : integer range 0 to 4095 := 5; --! this corresponds to deadtime of 1 us for my system
			IND_WIDTH: natural := 10 --! input resolution 
			);	
	  port(
			clk_i		: in  std_logic;  --! system clock
			nreset_i    : in  std_logic;  --! asynchronous nreset_i
			enable_i    : in  std_logic;  --! enable_i signal
			duty_i      : in  unsigned(IND_WIDTH-1 downto 0); --! Dutycycle 
			cnt_top_i	: in unsigned(12 downto 0); --! counter top value (for additional phase shift) 
			switch_i	: in std_logic_vector(1 downto 0) := (others => '0'); -- Pascal: Add input
			switch1_o   : out std_logic; --! High switch output
			switch2_o   : out std_logic; --! Low switch output 
			start_pwm_cycle_o: out std_logic; --! indicates start of a new pwm cycle 
			pwm_count_o: out signed(15 downto 0) --! PWM counter value (only for testing) 
			);			            						
	end component;
	
	
	--! @brief Calculates Phase shift between two current signals 
	component phase_shift_control is 
	generic( 	CNT_RES_G 		: natural := 12; 
				CMAX_G 			: integer := 2500; -- Generic Maximum counter value of PWM 
				NO_CONTROLER_G 	: integer := 2; -- Total number of Controler used
				MY_NUMBER_G 	: integer := 1 -- indice of current slave 	
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! reset 
			nsoftreset_i 	: in std_logic; --! reset the phase shift calculation and start again 
			pwm_ma_start_i	: in std_logic; --! pwm master starts new cycle  
			pwm_sl_start_i	: in std_logic; --! pwm slave starts new cycle
			cnt_top_slave_o : out unsigned(CNT_RES_G downto 0) --! output counter top value (intentionally one bit longer than CNT_RES_G due to possible double value)	
			);
	end component; 
	
	component hysteresis_control is 
	generic( 	DATAWIDTH_G 	: integer := 12; --! Data width of measurements  
				CMAX_G			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency)
				NINTERLOCK_G	: integer := 50; 
				NO_CONTROLER_G 	: integer := 2;--! Total number of controler used
				MY_NUMBER_G 	: integer := 1; --! Slave number 
				DELTA_I_REF_G 	: integer := 25*(2**5); --! minimum set current change (25 A) for entering hysteresis mode 
				DELTA_I_THR_G 	: integer := 25*(2**5); --! minimum current difference (25 A) between measured and set current for entering hysteresis mode
				DELTA_VC_G		: integer := 100*(2**5); --! minimum VC change change (100 V) for entering hysteresis mode 
				D_IOUT_MAX_G	: integer := 5*(2**5); --! Maximum current ripple after first rise (here 5A) 
				N_CYCLE_REST_G	: integer := 0 --! Number of cycles controller stays in Hysterssis after phaseshift 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset
			nsoftreset_i	: in std_logic; --! synchronous softreset 
			hyst_enable_i	: in std_logic; --! enables hysteresis mode			
			iset_i			: in signed(DATAWIDTH_G-1 downto 0); --! set current 
			imeas_i			: in signed(DATAWIDTH_G-1 downto 0); --! measured effective current 
			imeas_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total measurement current 
			iset_tot_i		: in signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0); --! Total set current 
			vc_i			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			hyst_cond_sel_i	: in std_logic_vector(2 downto 0); --! Enable conditions for entering hysteresis: 2: vc, 1: ierr, 0: iset 
			pwm_switch1_i	: in std_logic; --! PWM high switch signal 
			pwm_switch2_i	: in std_logic; --! PWM low switch signal 
			hyst_t1_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t1 during hysteresis control of all modules (0: master) 
			hyst_o			: out std_logic; 
			hyst_t1_o 		: out std_logic;--! Start of point t1 during hysteresis control of this module
			hyst_t2_o		: out std_logic; --! Start of SECOND_UP of this module
			hyst_vec_i		: in std_logic_vector(NO_CONTROLER_G-1 downto 0);  --! hystersis mode of all modules  		
			hyst_t2_ma_i	: in std_logic; --! Start of SECOND_UP of master module
			hss_bound_i		: in signed(15 downto 0); --! hss_bound
			deltaH_ready_i	: in std_logic; --! calculation of deltaH finished 
			deltaH_i 		: in signed(15 downto 0); --! signed output value dH 
			switch1_o		: out std_logic; --! Output high switch 
			switch2_o		: out std_logic; --! Output low switch 
			nreset_pwm_o	: out std_logic; --! low active softreset of pwm 
			i_upper_o		: out signed(DATAWIDTH_G-1 downto 0); --! Hysteresis upper current bound (just for testing)
			i_lower_o		: out signed(DATAWIDTH_G-1 downto 0) --! Hysteresis lower current bound (just for testing)
			);
	end component;
	
	component startup is 
	generic( 	
			MY_NUMBER_G 		: integer := 0; --! index of current slave: 0 indicates master 
			CMAX_G				: integer := 1666
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous nreset 
			nsoftreset_o	: out std_logic; --! synchronous reset signal for PWM 
			sw2_o			: out std_logic; --! low side output switch 			
			half_duty_o 	: out std_logic --! use only half of duty cycle in startup 
			);
	end component;
	
	
-- ================== CONSTANTS ==================================================				
	constant D_WIDTH_C 	: natural := 11; -- width of duty cycle signal 
	constant HIGH_C		: std_logic := '1'; --! High signal constant 
	constant LOW_C 		: std_logic := '0'; --! Low signal constant 
		
	-- PWM 
	constant PWM_CNT_RES_C : natural := 12; --! number of bits for pwm counter 
	constant PWM_TOP_C 	: unsigned(PWM_CNT_RES_C downto 0) := to_unsigned(CMAX_G, PWM_CNT_RES_C + 1); --! Top pwm counter value 
	
-- =================== SIGNALS ===================================================
	-- resized input signals: all 16 bits signed 
	signal vbush_s    	: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! V1 measured voltage                   
	signal vbusl_s     	: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! V2 measured voltage 
	signal vc_s 		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Vc measured voltage
	signal vc_switch_s	: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Vc switchable voltage 
	signal imeas_s		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Measured current 
	signal imeas_avg_s  : signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Averaged measured current (limitMAF) with 32 taps 
	signal iset_s		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Set current 
	

    signal ierr_avg_s	: signed(DATAWIDTH_G downto 0) := (others => '0'); --! iset_i - imeas_i  averaged error current (with moving average) 
	
	-- PWM 
	signal pi_s 		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! output of PI controler 
	signal pi_result_valid_s: std_logic := '0'; 
	signal pwm_count_top_s, pwm_count_top_slave_s: unsigned(PWM_CNT_RES_C downto 0):= PWM_TOP_C; --! counter top value (pwm_count_top_s is either constant (master) or pwm_count_top_slave_s (slave) 
	signal phase_shift_dis_s : std_logic := LOW_C; 
	signal pwm_ma_start_s : std_logic := LOW_C; --! PWM cycle start of master 
	signal pwm_sl_start_s : std_logic := LOW_C; --! PWM cylce start of slave 
	signal pwm_start_s	  : std_logic := LOW_C; 
	
	-- Duty cycle
	signal d_s 			  : unsigned(D_WIDTH_C-1 downto 0) := (others => '0');  --! duty cycle  
	signal half_duty_s	  : std_logic := '0'; --! connection startup - dutycycle_calc , use only half of dutycycle in  startup 
	
	-- Communication between PWM and Hysteresis
	signal pwm_switch1_s : std_logic :=  LOW_C; --! high switch signal 
	signal pwm_switch2_s : std_logic :=  LOW_C; --! low switch signal 
	
	signal nreset_fromhyst_s: std_logic:= HIGH_C; 
	signal nreset_PI_Duty_s : std_logic :=  HIGH_C; --! soft reset for PI and dutycycle
	
	signal nreset_pwm_s : std_logic := HIGH_C; --! soft reset for pwm counter 
	signal startup_pwm_nreset_s: std_logic := HIGH_C; --! pwm startup nreset 
	-- 
	signal switch1_s	: std_logic := LOW_C; --! high switch signal 
	
		
-- =================== STATES ====================================================

	begin
	
	-- assignments of MASTER/SLAVE differences 
	pwm_count_top_s <= PWM_TOP_C 	when MY_NUMBER_G = 0 else pwm_count_top_slave_s; 
	pwm_ma_start_s 	<= LOW_C 	 	when MY_NUMBER_G = 0 else pwm_ma_start_i; 
	pwm_sl_start_s	<= LOW_C	 	when MY_NUMBER_G = 0 else pwm_start_s; 
	pwm_ma_start_o 	<= pwm_start_s	when MY_NUMBER_G = 0 else LOW_C; 
		
	-- resize all input measurements to 16 bits 
	-- transform from unsigned 12 bit to signed 16 bit 
	vbush_s(DATAWIDTH_G-1 downto DATAWIDTH_G -1- MEAS_V_DATAWIDTH_G) 	<= signed('0' & vbush_i); 
	vbusl_s(DATAWIDTH_G-1 downto DATAWIDTH_G -1- MEAS_V_DATAWIDTH_G)	<= signed('0' & vbusl_i);  
	
	vc_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) 	<= vc_i; 
	vc_switch_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) <= vc_switch_i; 
	imeas_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) 	<= imeas_i;  	
	iset_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) 	<= iset_i; 
	-- phase shift enable combinatoric 
	
	-- soft reset signals 
	nreset_PI_Duty_s <=nsoftreset_i and nreset_fromhyst_s;
	phase_shift_dis_s <= not(hyst_vec_i(0)) and nreset_fromhyst_s;
	nreset_pwm_s <= nreset_fromhyst_s  and startup_pwm_nreset_s and nsoftreset_i; 
	
			
	-- Input moving average filter 
	inst_moving_average: moving_avg
	generic map(
		NSAMPLES => 32, -- Number of samples from 2 MHz to 60 KHz: 2e6/60e3 =~  32 (set to 32 for easier division)
		IN_WIDTH => DATAWIDTH_G,
		MAX_DELTA_G => MAX_DELTA_G,
		CORR_DELTA_G => CORR_DELTA_G
	)
	port map(
		clk_i 		=> clk_i, 				-- Clock
		nreset_i 	=> nreset_i,			-- Reset
		nsoftreset_i=> nsoftreset_i, 		-- 
		din_valid_i => sample_clk_i,		-- Flag for valid input data
		sample_i 	=> imeas_s,		-- Signal to be averaged
		average_o 	=> imeas_avg_s		-- Average value
	);
	
	-- Calculate error current 
	ierr_avg_s <= (resize(iset_s,DATAWIDTH_G+1) - resize(imeas_avg_s,DATAWIDTH_G+1)); 
	
	
	-- PI controller 
	inst_pi_control_bw_euler : pi_control_bw_euler
	generic map(INW_G 	=> DATAWIDTH_G+1, 		--! input bits
				OUTW_G	=> DATAWIDTH_G,
				ANTI_WINDUP_G 		=> ANTI_WINDUP_G,
				GAINBM_G			=> GAINBM_G,	 	
				GAINBP_G			=> GAINBP_G
				--Kprop_G				=> Kprop_G,		
				--KixTs_G				=> KixTs_G
	)
	port map(
		clk_i			=> clk_i, 	
		nreset_i		=> nreset_i, 
		nsoftreset_i	=> nreset_PI_Duty_s, 
		int_enable_i	=> HIGH_C, 
		data_i			=> ierr_avg_s,
		data_valid_i	=> pwm_start_s, 
		kprop_i			=> kprop_i,	
		kixts_i	        => kixts_i,	
		result_o 		=> pi_s,
		result_valid_o 	=> pi_result_valid_s
	);
	
	-- Dutycycle calculator 
	inst_dutycycle_calc: dutycycle_calc
	generic map(INW_G 	=> DATAWIDTH_G, 				
				OUTW_G	=> D_WIDTH_C,
				NINTERLOCK_G => NINTERLOCK_G
	)
	port map(
		clk_i			=> clk_i, 	
		nreset_i		=> nreset_i, 
		nsoftreset_i	=> nreset_PI_Duty_s, 
		pi_i		    => pi_s,
		pi_valid_i		=> pi_result_valid_s,
		vc_i			=> vc_s, 
		vc_switch_i 	=> vc_switch_s, 	
		switch_i		=> switch_i,		
		vbush_i			=> vbush_s,
		vbusl_i		    => vbusl_s,
		iset_i			=> iset_s, 
		half_duty_i		=> half_duty_s, 
		d_o 		    => d_s
		);
	
	-- PWM 
	inst_pwm_st : pwm_st
	generic map(CNT_RES_G =>PWM_CNT_RES_C, --counter resolution in bits
		CNT_TOP_G => CMAX_G, --upper limit for the reference signal (depends on the scaling of the duty_i cycle)
		INIT_CNT_G => 0, --this is for initial phase shift if need be
		CNT_INTERLOCK_G => 1, -- this corresponds to deadtime of 1 us for my system
		IND_WIDTH => D_WIDTH_C
		)
	port map(
		clk_i				=> clk_i, 	
		nreset_i 			=> nreset_i, 
		enable_i 			=> nreset_pwm_s, 
		duty_i   			=> d_s, 
		cnt_top_i			=> pwm_count_top_s,
		switch_i			=> switch_i,	-- Pascal: connect this signal
		switch1_o			=> pwm_switch1_s, 
		switch2_o			=> open, 
		start_pwm_cycle_o 	=> pwm_start_s, 
		pwm_count_o			=> pwm_count_o
	);
		
	
	-- Phase shift control 
	inst_phase_shift_control: phase_shift_control
	generic map(CNT_RES_G 	=> PWM_CNT_RES_C,
				CMAX_G 	 	=> CMAX_G, -- Generic Maximum counter value of PWM 
				NO_CONTROLER_G=> NO_CONTROLER_G, -- Total number of Controler used
				MY_NUMBER_G => MY_NUMBER_G -- indice of current slave 	
			)	
	port map( clk_i			=> clk_i, 	 --! Main clock 
			nreset_i 		=> nreset_i,  --! reset 
			nsoftreset_i	=> phase_shift_dis_s, 
			pwm_ma_start_i	=> pwm_ma_start_s, --! pwm master starts new cycle  
			pwm_sl_start_i	=> pwm_sl_start_s, --! pwm slave starts new cycle
			cnt_top_slave_o => pwm_count_top_slave_s --! output counter top value (intentionally one bit longer than CNT_RES_G due to possible double value)	
			);
	
	-- Startup 	
	inst_startup : startup
	generic map( 	
			MY_NUMBER_G 		=> MY_NUMBER_G, 
			CMAX_G				=> CMAX_G
			)
	port map( 	clk_i			=> clk_i, 
			nreset_i 		=> nreset_i,
			nsoftreset_i	=> nsoftreset_i, 
			nsoftreset_o	=> startup_pwm_nreset_s,
			sw2_o			=> pwm_switch2_s, 
			half_duty_o 	=> half_duty_s
			);
			
	
	--!central hysteresis bound calculation block 
	inst_hysteresis: hysteresis_control 
	generic map(DATAWIDTH_G 		=> DATAWIDTH_G, 
				CMAX_G				=> CMAX_G, 
				NINTERLOCK_G		=> NINTERLOCK_G, 
				NO_CONTROLER_G 		=> NO_CONTROLER_G, -- Total number of Controler used
				MY_NUMBER_G 		=> MY_NUMBER_G, -- indice of current slave 	
				DELTA_I_REF_G 		=> DELTA_I_REF_G, 	
				DELTA_I_THR_G 		=> DELTA_I_THR_G, 
				DELTA_VC_G			=> DELTA_VC_G, 
				D_IOUT_MAX_G		=> D_IOUT_MAX_G,
				N_CYCLE_REST_G		=> N_CYCLE_REST_G
			)
	port map (clk_i			=> clk_i, 
			nreset_i 		=> nreset_i,
			nsoftreset_i	=> nsoftreset_i,
			hyst_enable_i	=> hyst_enable_i,
			iset_i			=> iset_s,
			imeas_i			=> imeas_s, -- measured current 
			imeas_tot_i		=> imeas_tot_i,			
			iset_tot_i		=> iset_tot_i,		
			vc_i			=> vc_s,	
			hyst_cond_sel_i	=> hyst_cond_sel_i,
			pwm_switch1_i	=> pwm_switch1_s,  
			pwm_switch2_i	=> pwm_switch2_s, 
			hyst_t1_vec_i	=> hyst_t1_vec_i,
			hyst_o			=> hyst_o,
			hyst_t2_o		=> hyst_t2_o,	
			hyst_vec_i		=> hyst_vec_i,
			hyst_t2_ma_i	=> hyst_t2_ma_i,	
			hss_bound_i		=> hss_bound_i,
			deltaH_ready_i	=> deltaH_ready_i,		
			deltaH_i 		=> deltaH_i, 		
			hyst_t1_o 		=> hyst_t1_o, 		
			switch1_o		=> pwm1_o,
			switch2_o		=> pwm2_o,
			nreset_pwm_o	=> nreset_fromhyst_s , 
			i_upper_o		=> i_upper_o, 
			i_lower_o		=> i_lower_o
			);
		
	-- Output assignments
	nreset_pwm_o <= nreset_PI_Duty_s; 
	pi_o <= pi_s; 
	d_o <= signed(resize(d_s,16));
	ierr_o <= resize(ierr_avg_s,16);
	imeas_avg_o <= resize(imeas_avg_s,16);
	
end rtl;