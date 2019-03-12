--==========================================================
-- Unit		:	calc_deltaH_bound2(rtl)
-- File		:	calc_deltaH_bound2.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file calc_deltaH_bound2.vhd
--! @author Michael Hersche
--! @date  13.11.2017
--! @version 1.1 -- Centralized calculation of deltaH for all slave modules 

library work; 
USE work.stdvar_arr_pkg.all;
-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Calculate hystersis delta H bound. 
--! @details The deltaH bound is used to introduce an aditional phase shift in the hystersis control 
--! @details deltaH_o = (dt*-dt)*S1*S2/(S2-S1)
--! @details dt* : Wanted phase shift [s] between master and this slave
--! @details dt : Actual phase shift [s]
--! @details S1 = (Vbush - Vc)/L 
--! @details S2 = (-Vbusl - Vc)/L 
entity calc_deltaH_bound2 is 
	generic( 	DATAWIDTH_G		: natural := 16; --! Data width of measurements  
				CMAX_G 			: integer := 1666; --! Maximum counter value of PWM (determines PWM frequency)
				NO_CONTROLER_G 	: integer := 2; --! Total number of controler used
				MY_NUMBER_G 	: integer := 1  --! Slave number 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			vbush_i    		: in signed(DATAWIDTH_G-1 downto 0); --! V1 measured voltage 
			vbusl_i     	: in signed(DATAWIDTH_G-1 downto 0); --! V2 measured voltage
			vc_i 			: in signed(DATAWIDTH_G-1 downto 0); --! Vc measured voltage
			hyst_i			: in std_logic; --! start of hysteresis mode in this module 
			hyst_t2_vec_i	: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Start of point t2 during hysteresis control of all modules (0: master) 
			phase_shift_en_i: in std_logic; --! all modules reached t1
			dH_fac_i		: in signed(DATAWIDTH_G-1 downto 0); --! L/T = L*fclk
			deltaH_ready_o	: out std_logic_vector(NO_CONTROLER_G-1 downto 1); --! calculation of deltaH finished 
			deltaH_o 		: out array_signed16(NO_CONTROLER_G-1 downto 1) --! signed output value dH 
			);
			
end calc_deltaH_bound2;


architecture structural of calc_deltaH_bound2 is

-- ================== CONSTANTS ==================================================				
-- Timing constants for arithmetic operations 
constant CNT_MULT_S1S2_C 	: integer := 20; --! number of clockcycles for multiplying s1 with s2 (17 bits)
constant CNT_DIVIDING_C	  	: integer := 101; --! number of clockcycles for scaling (46 bits)

-- Scaling constants 
--constant SCALE_T_L_C 		: std_logic_vector(15 downto 0) := std_logic_vector(to_signed(25000,16)); --! L*fclk = 250e-6*100e6 

-- Maximum of constants  
constant SIGNED_16_MAX		: signed(15 downto 0) := to_signed(2**15-1,16); 
constant SIGNED_16_MIN		: signed(15 downto 0) := to_signed(-2**15,16); 

-- ================== COMPONENTS =================================================
--! @brief Signed multiplier 17 bits x 17 bits 
component my_17_mult is
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (16 downto 0);
		datab		: in std_logic_vector (16 downto 0);
		result		: out std_logic_vector (33 downto 0)
	);		
end component ;

--! @brief Signed divider 46 bits x 34 bits 
component my_46_33_div is 
	port
	(
		clock		: in std_logic;
		denom		: in std_logic_vector (32 downto 0);
		numer		: in std_logic_vector (45 downto 0);
		quotient	: out std_logic_vector (45 downto 0);
		remain		: out std_logic_vector (32 downto 0)
	);
end component;

--! @brief Signed multiplier 17 bits x 16 bits 
component my_17_16_mult is 
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (16 downto 0);
		datab		: in std_logic_vector (15 downto 0);
		result		: out std_logic_vector (32 downto 0)
	);
end component;

--! @brief dK multiplier
component dk_mult is 
	generic( 	DATAWIDTH_G		: natural := 16; 	--! Data width of measurements  
				CMAX_G 			: integer := 1666; 	--! Maximum counter value of PWM (determines PWM frequency)
				NO_CONTROLER_G 	: integer := 2; 	--! Total number of controler used
				MY_NUMBER_G 	: integer := 1  	--! Slave number 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			hyst_i	: in std_logic; --! start of hysteresis mode in this module 
			t2_start_sl_i	: in std_logic; --! Start of corner point t2 during hysteresis control of slave 
			t2_start_ma_i	: in std_logic; --! Start of corner point t2 during hysteresis control of master 
			dk_factor_i		: in signed(DATAWIDTH_G-1 downto 0); --!  factor with 12 additional fractional bits 
			dk_factor_ready_i: in std_logic; --! new dk_factor available 
			deltaH_ready_o	: out std_logic; --! calculation of deltaH finished 
			deltaH_o 		: out signed(DATAWIDTH_G-1 downto 0) --! signed output value dH 
			);		
end component;

-- =================== STATES ====================================================
type dH_calcstate is (IDLE, MULT_S1S2 , DIVIDING, WAIT_DK_UPDATE); --! States supervising the main calculation steps 
type overfl_superv is (IDLE,OVERFLOW, UNDERFLOW); 	
-- =================== SIGNALS ===================================================
-- All variables denoted with x are inputs of operations
-- 							  y are outputs of operations 
-- The x are updated as soon as the statemachine allows it(for propper multiplication and division)
signal dH_cnt_s, dH_cnt_next_s : integer := 0; --! counter for dH_state machine supervising timing of calculations
signal dH_state_s,dH_state_next_s : dH_calcstate := IDLE; --! State machine dH calculation 

signal s1_s, s1_next_s 		: signed(DATAWIDTH_G downto 0) := (others => '0'); --! s1_s = (Vbush - Vc)  , normalization by L is done in the end 
signal s2_s, s2_next_s		: signed(DATAWIDTH_G downto 0) := (others => '0'); --! s2_s = (Vbusl - Vc) , normalization by L is done in the end 
signal s2ms1_s,	s2ms1_next_s: signed(DATAWIDTH_G downto 0) := (others => '0'); --! s2ms1_s = (Vbusl - Vbush) ,normalization by L is done in the end  

signal y10_s : std_logic_vector( 2*DATAWIDTH_G+1 downto 0) := (others => '0'); --! output of multiplier: y10_s = s1_s * s2_s 
signal y11_s : std_logic_vector(32 downto 0) := (others => '0'); --! output of multiplier for scaling: y11_s = SCALE_T_L_C * s2ms1_s 

signal x20_s, x20_next_s : std_logic_vector(2*DATAWIDTH_G+1 + 12 downto 0) := (others => '0'); --! x20_s =  (s1_s * s2_s) << 12
signal x21_s, x21_next_s : std_logic_vector(32 downto 0) := (others => '0'); --! x21_s = SCALE_T_L_C * s2ms1_s 

signal y2_s, y2_next_s : std_logic_vector(45 downto 0) :=  (others => '0'); --! y2_s = ((s1_s * s2_s) << 12)/(SCALE_T_L_C * s2ms1_s)  

signal dk_factor_s, dk_factor_next_s: signed(15 downto 0):= (others => '0'); 
signal dk_factor_ready_s, dk_factor_ready_next_s: std_logic := '0'; 

signal phase_shift_en_vec_s : std_logic_vector(1 downto 0) := "00"; --! last two signals of phase_shift_en_i for edge detection 

signal deltaH_s : signed(15 downto 0):= (others => '0'); -- array_signed16(NO_CONTROLER_G-1 downto 0) := (others => (others=> '0')); 

signal dk_superv_s, dk_superv_next_s: overfl_superv := IDLE; 


begin		

	--! @brief Registers for dH state machine 
	--! @details Asynchronous reset nreset_i, no softreset 
	dH_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			phase_shift_en_vec_s <= "01"; 
			dH_state_s <= IDLE; 
			dH_cnt_s 	<= 0;
			s1_s 		<= (others => '0');
			s2_s        <= (others => '0');
			s2ms1_s     <= (others => '0');
			x20_s		<= (others => '0');
			x21_s       <= (others => '0');
			dk_factor_s <= (others => '0');
			y2_s		<= (others => '0');
			dk_factor_ready_s <= '0'; 
			dk_superv_s	<= IDLE; 
		elsif rising_edge(clk_i) then
			phase_shift_en_vec_s <= phase_shift_en_vec_s(0) & phase_shift_en_i; 
			dH_state_s 	<= dH_state_next_s; 
			dH_cnt_s 	<= dH_cnt_next_s; 
			s1_s 		<= s1_next_s; 
			s2_s        <= s2_next_s; 
			s2ms1_s     <= s2ms1_next_s; 
			x20_s		<= x20_next_s; 
			x21_s       <= x21_next_s;
			y2_s		<= y2_next_s; 
			dk_factor_s <= dk_factor_next_s; 
			dk_factor_ready_s <= dk_factor_ready_next_s;
			dk_superv_s <= dk_superv_next_s; 
		end if; 
	end process; 
			
	--! @brief dH state machine and counter logic 
	--! @details Statemachine leaves IDLE 
	--! @details The inputs of the operators (x_) are updated with the outputs of the operators (y_) as soon
	--! @details as the time for operation is over. 
	dH_proc_logic: process(vbush_i,vbusl_i,vc_i,dH_state_s, dH_cnt_s,y10_s,y2_s,y11_s,phase_shift_en_vec_s, dk_factor_s,s1_s,s2_s,s2ms1_s,x20_s,x21_s,dk_factor_ready_s,dk_superv_s) 
	begin
		-- default assignments for avoiding latches 
		dH_state_next_s <= dH_state_s; 
		dH_cnt_next_s 	<= dH_cnt_s; 
		s1_next_s 	 	<= s1_s; 
		s2_next_s	 	<= s2_s; 
		s2ms1_next_s 	<= s2ms1_s; 
		x20_next_s		<= x20_s; 
		x21_next_s		<= x21_s; 
		dk_factor_next_s<= dk_factor_s; 
		dk_factor_ready_next_s <= dk_factor_ready_s; 
		
		case dH_state_s is 
			when IDLE => 
				dk_factor_ready_next_s <= '0'; 
				if phase_shift_en_vec_s = "01" then -- start new calculation 
					dH_state_next_s <= MULT_S1S2; 
					s1_next_s 	 <= resize(vbush_i,DATAWIDTH_G+1) - resize(vc_i,DATAWIDTH_G+1); 
					s2_next_s	 <= -resize(vbusl_i,DATAWIDTH_G+1)-resize(vc_i,DATAWIDTH_G+1); 
					s2ms1_next_s <= -resize(vbusl_i,DATAWIDTH_G+1) - resize(vbush_i,DATAWIDTH_G+1); 
					dH_cnt_next_s <= 0; 
				end if; 
				
			when MULT_S1S2 => 
				dk_factor_ready_next_s <= '0'; 
				if dH_cnt_s < CNT_MULT_S1S2_C then 
					dH_cnt_next_s <= dH_cnt_s +1; 
				else -- calculation done 
					dH_cnt_next_s <= 0; 
					dH_state_next_s <= DIVIDING ;
					x20_next_s(x20_next_s'left downto 12) <= y10_s; 
					x21_next_s <= y11_s; 
				end if; 
			
			when DIVIDING => 
				if dH_cnt_s < CNT_DIVIDING_C then 
					dH_cnt_next_s <= dH_cnt_s +1; 
					dk_factor_ready_next_s <= '0'; 
				else 
					dH_state_next_s <= IDLE;  
					dH_cnt_next_s <= 0; 
					dk_factor_ready_next_s <= '1'; 
					-- Clipping of output signal 
					case dk_superv_s is 
						when OVERFLOW => 
							dk_factor_next_s <= SIGNED_16_MAX; 
						when UNDERFLOW => 
							dk_factor_next_s <= SIGNED_16_MIN; 
						when IDLE => 
							dk_factor_next_s <= resize(signed(y2_s),16); 
						when others  => 
							dk_factor_next_s <= to_signed(0,16); 
					end case;  	
				end if; 
			
			when others => 		
			end case;  
	end process; 
	
	
	dk_supervision: process(y2_s)
	begin 
	
		if signed(y2_s) > SIGNED_16_MAX then -- overflow 
			dk_superv_next_s <= OVERFLOW; 
		elsif signed(y2_s) < SIGNED_16_MIN then -- underflow  
			dk_superv_next_s <= UNDERFLOW; 
		else -- everything ok 
			dk_superv_next_s <= IDLE; 
		end if; 
		
	end process; 
	-- ======= Components declarations for calculations ================
	my_17_mult_inst2:  my_17_mult 
	port map (
		clock		=> clk_i,
		dataa		=> std_logic_vector(s1_s), 
		datab		=> std_logic_vector(s2_s), 
		result		=> y10_s
	);
	
		my_17_16_mult_inst:  my_17_16_mult
	port map(
		clock		=> clk_i,
		dataa		=> std_logic_vector(s2ms1_s),
		datab		=> std_logic_vector(dH_fac_i),
		result		=> y11_s
	);
		
	my_46_33_div_inst: my_46_33_div 
	port map(
		clock		=> clk_i,
		denom		=> x21_s,  
		numer		=> x20_s, 
		quotient	=> y2_next_s,
		remain		=> open
	);
		
	
	--generate for loop dk_mult for every slave  
	DK_MULTIPLIER_LOOP: 
		for I in 1 to NO_CONTROLER_G-1 generate
			REGX : dk_mult
			generic map(
				DATAWIDTH_G			=> DATAWIDTH_G, 
				CMAX_G 				=> CMAX_G, 
				NO_CONTROLER_G 		=> NO_CONTROLER_G, 
				MY_NUMBER_G 		=> I
				)
			port map(
				clk_i				=> clk_i, 
				nreset_i 			=> nreset_i, 
				hyst_i				=> hyst_i, 
				t2_start_sl_i		=> hyst_t2_vec_i(I),	
				t2_start_ma_i		=> hyst_t2_vec_i(0), 
				dk_factor_i			=> dk_factor_s, 
				dk_factor_ready_i	=> dk_factor_ready_s,
				deltaH_ready_o		=> deltaH_ready_o(I),
				deltaH_o 			=> deltaH_o(I)
				); 
	
	  end generate DK_MULTIPLIER_LOOP;
	
	
	
	
end structural; 