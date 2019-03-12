--==========================================================
-- Unit		:	hysteresis_calc(rtl)
-- File		:	hysteresis_calc.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file hysteresis_calc.vhd
--! @author Michael Hersche
--! @date  10.03.2018

USE work.stdvar_arr_pkg.all;
-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Central calculation of Hss and dH 


entity hysteresis_calc is 
	generic( CMAX_G 			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency) =>  ~60 KHz with 100 MHz clock   
			 MEAS_I_DATAWIDTH_G : integer range 8 to 16 := 12;  --! Data width of current measurements  
			 MEAS_V_DATAWIDTH_G	: integer range 8 to 16 := 12; --! Data width of voltage measurements 
			 NO_CONTROLER_G 	: integer := 2; --! Total number of controler used (slaves + master)
			 DATAWIDTH_G		: integer := 16; --! internal data width for calculations 
			 NINTERLOCK_G: natural := 50; -- number of interlock clocks 
			 -- variable L calculation constants 
			FS_G 			: real 	 := 60000.0; --! Switching frequency 
			F_CLK_G			: real 	 := 100.0*(10**6); --! Clock frequency  
			L1_G			: real 	 := 0.00025;--0.00013; --! Inductance [H] at point 1 
			L2_G 			: real 	 :=  0.00025;--0.000115; --! Inductance [H] at point 2 
			L3_G 			: real 	 :=  0.00025;--0.00003; --! Inductance [H] at point 3 
			A1_G			: real	 := 160.0; --! Current [A] corner 1 
			A2_G 			: real	 := 250.0; --! Current [A] corner 2 
			A3_G 			: real	 := 300.0  --! Current [A] corner 3 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 				
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in unsigned(MEAS_V_DATAWIDTH_G-1 downto 0); --! V2 measured voltage
			vc_i 			: in signed(MEAS_I_DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			imeas_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --! individual measured current  
			iset_i			: in array_signed_in(NO_CONTROLER_G-1 downto 0); --!
			hyst_i			: in std_logic; --! hysteris mode of master 
			hyst_t1_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t1 during hysteresis control of all modules (0: master) 
			hyst_t2_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t2 during hysteresis control of all modules (0: master) 
			nreset_phase_shift_i: in std_logic; --! reset phase shift enable signal 
			hss_bound_o 	: out signed(DATAWIDTH_G-1 downto 0); --! signed output value
			imeas_tot_o		: out signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0);--! signed total measurement current 
			iset_tot_o		: out signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0);--! signed total set current 
			deltaH_ready_o	: out std_logic_vector(NO_CONTROLER_G-1 downto 1); --! calculation of deltaH finished 
			deltaH_o 		: out array_signed16(NO_CONTROLER_G-1 downto 1) --! signed output value dH 
			);
			
end hysteresis_calc;

architecture structural of hysteresis_calc is
-- ================== CONSTANTS ==================================================				
constant MAX_VAL_DW_C : integer := 2**(DATAWIDTH_G-1)-1;
constant MIN_VAL_DW_C : integer := -2**(DATAWIDTH_G-1); 

constant BIT_DIFF_C : natural := DATAWIDTH_G - MEAS_I_DATAWIDTH_G; 
constant ZEROS_BIT_C: signed(BIT_DIFF_C-1 downto 0) := (others => '0');  
-- ================== COMPONENTS =================================================
--! @brief Calculate Hss bound  
component calc_hyst_bounds is 
	generic( 	DATAWIDTH_G : natural := 16;
				NINTERLOCK_G: natural := 50 -- number of interlock clocks 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in signed(DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in signed(DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
			vc_i 			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			iset_i			: in signed(DATAWIDTH_G-1 downto 0); --! set current 
			phase_shift_en_i: in std_logic;  --! start of calculation 		
			H_bount_fac_i	: in signed(12 downto 0); --! 1/(2*fs*L) 
			hss_bound_o 	: out signed(DATAWIDTH_G-1 downto 0) --! signed output value
			);
end component;
	
component and_reduce_edge is 
	generic( 	NO_CONTROLER_G 	: integer := 2 --! Total number of controler used
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			nsoftreset_i	: in std_logic; --! Synchronous nreset 
			data_i			: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Input vector 
			result_o		: out std_logic --! 
			);
end component;

component calc_deltaH_bound2 is 
	generic( 	DATAWIDTH_G		: natural := 16; --! Data width of measurements  
				CMAX_G 			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency)
				NO_CONTROLER_G 	: integer := 2 --! Total number of controler used
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in signed(DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in signed(DATAWIDTH_G-1 downto 0); --! V2 measured voltage 
			vc_i 			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			hyst_i	: in std_logic; --! start of hysteresis mode in this module 
			hyst_t2_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t2 during hysteresis control of all modules (0: master) 
			phase_shift_en_i: in std_logic; --! all modules reached t1
			dH_fac_i		: in signed(DATAWIDTH_G-1 downto 0); --! L/T = L*fclk
			deltaH_ready_o	: out std_logic_vector(NO_CONTROLER_G-1 downto 1); --! calculation of deltaH finished 
			deltaH_o 		: out array_signed16(NO_CONTROLER_G-1 downto 1) --! signed output value dH 
			);
			
end component;

--! @brief variable L generator 
component cal_var_L is 
	generic(DATAWIDTH_G	: integer:= 16;  --! General internal datawidth
			FS_G 			: real 	 := 60000.0; --! Switching frequency 
			F_CLK_G			: real 	 := 100.0*(10**6); --! Clock frequency  
			L1_G			: real 	 := 0.00025;--0.00013; --! Inductance [H] at point 1 
			L2_G 			: real 	 :=  0.00025;--0.000115; --! Inductance [H] at point 2 
			L3_G 			: real 	 :=  0.00025;--0.00003; --! Inductance [H] at point 3 
			A1_G			: real	 := 160.0; --! Current [A] corner 1 
			A2_G 			: real	 := 250.0; --! Current [A] corner 2 
			A3_G 			: real	 := 300.0  --! Current [A] corner 3 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			current_i		: in signed(DATAWIDTH_G -1 downto 0); 
			H_bound_fac_o	: out signed (12 downto 0); 
			dH_fac_o		: out signed (15 downto 0) 
			); 	
end component;
	
-- =================== STATES ====================================================

-- =================== SIGNALS ===================================================
signal vbush_s    	: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! V1 measured voltage                   
signal vbusl_s     	: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! V2 measured voltage 
signal vc_s 		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Vc measured voltage
signal iset_s		: signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! Set current 




signal imeas_tot_next_s 	: signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0) :=  (others => '0');
signal imeas_tot_s			: signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0) :=  (others => '0');
signal iset_tot_next_s 		: signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0) :=  (others => '0');
signal iset_tot_s			: signed(DATAWIDTH_G-1+(NO_CONTROLER_G-1) downto 0) :=  (others => '0');

signal phase_shift_en_s: std_logic := '0'; -- high if all modules hit t1 once 

signal H_bount_fac_s: signed(12 downto 0) := (others => '0'); -- Hbound factor: 1/(2*fs*L) 
signal dH_fac_s: signed(15 downto 0) := (others => '0'); -- dHbound factor: L/T = L*fclk


begin 

-- resize all input measurements to 16 bits 
	-- transform from unsigned 12 bit to signed 16 bit 
	vbush_s(DATAWIDTH_G-1 downto DATAWIDTH_G -1- MEAS_V_DATAWIDTH_G) 	<= signed('0' & vbush_i); 
	vbusl_s(DATAWIDTH_G-1 downto DATAWIDTH_G -1- MEAS_V_DATAWIDTH_G)	<= signed('0' & vbusl_i);  
	vc_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) <= vc_i; 
	iset_s(DATAWIDTH_G-1 downto DATAWIDTH_G - MEAS_I_DATAWIDTH_G) <= iset_i(0); 


	
	--! @brief Calculate Hysteresis Bounds 
	calc_hyst_bounds_inst: calc_hyst_bounds 
	generic map( 	DATAWIDTH_G => DATAWIDTH_G,
					NINTERLOCK_G=> NINTERLOCK_G
			)		
	port map( 	clk_i			=> clk_i, --! Main clock 
			nreset_i 		=> nreset_i, --! reset 
			vbush_i    		=> vbush_s, 
			vbusl_i     	=> vbusl_s, 
			vc_i 			=> vc_s, 
			iset_i			=> iset_s, 
			phase_shift_en_i=> phase_shift_en_s,  --! start of calculation 
			H_bount_fac_i => H_bount_fac_s, 
			hss_bound_o  => hss_bound_o --! signed output value
			); 

	--! @brief Detects t1 events of all modules 
	phase_shift_en_s_inst: and_reduce_edge
	generic map ( 	NO_CONTROLER_G =>	NO_CONTROLER_G
			)		
	port map( 	clk_i		 	=> clk_i, 
			nreset_i 		=> nreset_i, 
			nsoftreset_i	=> nreset_phase_shift_i, -- which nreset??  
			data_i			=> hyst_t1_vec_i, 
			result_o		=> phase_shift_en_s
			);
	
	--! @brief Calculation of dH
	calc_deltaH_bound2_inst: calc_deltaH_bound2 
	generic map( 	DATAWIDTH_G			=> DATAWIDTH_G, 
					CMAX_G 				=> CMAX_G,
					NO_CONTROLER_G 	 	=> NO_CONTROLER_G
			)		
	port map( 	
			clk_i				=> clk_i,
			nreset_i 			=> nreset_i, 
			vbush_i    			=> vbush_s, 
			vbusl_i     		=> vbusl_s, 
			vc_i 				=> vc_s, 
			hyst_i				=> hyst_i, 
			hyst_t2_vec_i		=> hyst_t2_vec_i,
			phase_shift_en_i	=> phase_shift_en_s, 
			dH_fac_i			=> dH_fac_s, 
			deltaH_ready_o		=> deltaH_ready_o, 
			deltaH_o 			=> deltaH_o
			);
			
	--! @brief variable L generator 
	calc_var_inst: cal_var_L 
		generic map(DATAWIDTH_G => DATAWIDTH_G, 
				FS_G 			=> FS_G ,	--! Switching frequency 
				F_CLK_G			=> F_CLK_G,	 --! Clock frequency  
				L1_G			=> L1_G	,--0.00013; --! Inductance [H] at point 1 
				L2_G 			=> L2_G ,	--0.000115; --! Inductance [H] at point 2 
				L3_G 			=> L3_G ,	--0.00003; --! Inductance [H] at point 3 
				A1_G			=> A1_G	, --! Current [A] corner 1 
				A2_G 			=> A2_G ,	 --! Current [A] corner 2 
				A3_G 			=> A3_G	 --! Current [A] corner 3 
				)		
		port map( clk_i		=> clk_i,
				nreset_i 		=> nreset_i,
				current_i		=> iset_s, -- master set current 
				H_bound_fac_o	=> H_bount_fac_s, 
				dH_fac_o		=> dH_fac_s
				);
						
			
	-- Add Process of currents 
	
	add_imeas_proc: process(imeas_i)
		variable sum: integer := 0;  
		begin
			sum := 0; 
			for i in 0 to NO_CONTROLER_G-1 loop
				sum := sum + to_integer(imeas_i(i) & ZEROS_BIT_C);
			end loop;
			
			imeas_tot_next_s <= to_signed(sum,DATAWIDTH_G+(NO_CONTROLER_G-1)); 
			
		end process;
		
	add_set_proc: process(iset_i)
		variable sum:  integer := 0;  
		begin
			sum := 0; 
			for i in 0 to NO_CONTROLER_G-1 loop
				sum := sum + to_integer(iset_i(i) & ZEROS_BIT_C);
			end loop;
			-- limit output 
			iset_tot_next_s <= to_signed(sum,DATAWIDTH_G+(NO_CONTROLER_G-1)); 

		end process;
		
	reg_proc : process(clk_i,nreset_i)
		begin
			if nreset_i = '0' then 
				-- outputs 
				imeas_tot_s <= (others => '0'); 
				iset_tot_s <= (others => '0'); 				
			elsif rising_edge(clk_i) then
				-- outputs 
				imeas_tot_s <= imeas_tot_next_s; 
				iset_tot_s <= iset_tot_next_s; 
			end if; 
			
		end process; 
			
	-- output assignments 
	imeas_tot_o <= imeas_tot_s; 
	iset_tot_o <= iset_tot_s; 
	
	
	
			
end structural; 