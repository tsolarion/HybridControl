--==========================================================
-- Unit		:	dk_mult(rtl)
-- File		:	dk_mult.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	my_16_12_mult
--==========================================================

--! @file dk_mult.vhd
--! @author Michael Hersche
--! @date  14.03.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Calculation of (dK*dk_factor_i) >> 12 per slave. 
--! @details This block has mainly two stages: 
--! @details - Assessment of phaseshift between Master and Slave current and determination of necessairy phaseshift 
--! @details - Calculation of dH = (dK*dk_factor_i) >> 12

entity dk_mult is 
	generic( 	DATAWIDTH_G		: natural := 16; 	--! Data width of measurements  
				CMAX_G 			: integer := 1666; 	--! Maximum counter value of PWM (determines PWM frequency)
				MAX_NEG_FAC_G	: real 	  := 0.5; 	--! dH calc maximum fraction of period to go back => MAX_NEG_FAC_G*CMAX_G 
				NO_CONTROLER_G 	: integer := 2; 	--! Total number of controler used
				MY_NUMBER_G 	: integer := 1  	--! Slave number 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			hyst_i			: in std_logic; --! start of hysteresis mode in this module 
			t2_start_sl_i	: in std_logic; --! Start of corner point t2 during hysteresis control of slave 
			t2_start_ma_i	: in std_logic; --! Start of corner point t2 during hysteresis control of master 
			dk_factor_i		: in signed(DATAWIDTH_G-1 downto 0); --!  factor with 12 additional fractional bits 
			dk_factor_ready_i: in std_logic; --! new dk_factor available 
			deltaH_ready_o	: out std_logic; --! calculation of deltaH finished 
			deltaH_o 		: out signed(DATAWIDTH_G-1 downto 0) --! signed output value dH 
			);		
end dk_mult;


architecture structural of dk_mult is
-- ================== CONSTANTS ==================================================				
-- Timing constants 

constant CNT_MULT_C	: integer  range 0 to 10*CMAX_G:= 20; --! number of clockcycles for multiplying DK(12 bits) with S1*S2 (34 bits)

constant DK_WANTED_C: integer  range 0 to 10*CMAX_G := (CMAX_G * MY_NUMBER_G)/(NO_CONTROLER_G); --! wanted counter difference 
constant DK_MAXNEG_C: integer range 0 to CMAX_G := integer(MAX_NEG_FAC_G*real(CMAX_G)) ; 

-- ================== COMPONENTS =================================================

--! @brief Signed multiplier 34 bits x 12 bits 
component my_16_12_mult is 
	port
	(
		clock		: in std_logic ;
		dataa		: in std_logic_vector (15 downto 0);
		datab		: in std_logic_vector (11 downto 0);
		result		: out std_logic_vector (27 downto 0)
	);
end component;

-- =================== STATES ====================================================
type dk_state is (IDLE,WAIT_TRIGGER, SLAVECNT, MASTERCNT, SLAVEUPDATE, MASTERUPDATE,MULT); --! States measuring the phase shift (in clocks) between master and slave 

-- =================== SIGNALS ===================================================
-- All variables denoted with x are inputs of operations
-- 							  y are outputs of operations 
signal dk_state_s, dk_state_next_s: dk_state := IDLE; --! states for detecting phase shift(in clocks)
signal dk_cnt_s, dk_cnt_next_s : integer  range 0 to 10*CMAX_G:= 0; --! measured phase shift 

signal x1_s, x1_next_s : std_logic_vector(DATAWIDTH_G-1 downto 0) := (others => '0'); --! x1_s = dk_factor_i
signal x2_s, x2_next_s : std_logic_vector(11 downto 0) := (others => '0'); --! d_phase 

signal y1_s : std_logic_vector(27 downto 0) := (others => '0'); --! y1_s = x1_s*x2_s = dk_factor_i*d_phase
signal result_s, result_next_s : signed(DATAWIDTH_G-1 downto 0) := (others => '0'); --! result_s = y1_s >> 12 = (dk_factor_i*d_phase) >> 12

signal dk_factor_ready_next_s, dk_factor_ready_s: std_logic := '0'; -- latched dk_factor_ready_i signal, reset at end of MULT state 

signal hyst_start_s : std_logic_vector(1 downto 0) := "00"; -- for edge detection 

begin		


	--! @brief Registers for dK state machine 
	--! @details Asynchronous reset nreset_i, no softreset 
	dk_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			dk_state_s  <= IDLE; 
			dk_cnt_s 	<= 0;
			x1_s 		<= (others => '0'); 
			x2_s 		<= (others => '0'); 
			result_s	<= (others => '0'); 
			dk_factor_ready_s <= '0'; 
			hyst_start_s <= "00"; 
		elsif rising_edge(clk_i) then
			dk_state_s 	<= dk_state_next_s; 
			dk_cnt_s	<= dk_cnt_next_s;
			x1_s 		<= x1_next_s; 
			x2_s 		<= x2_next_s; 
			result_s	<= result_next_s; 
			dk_factor_ready_s <= dk_factor_ready_next_s; 
			hyst_start_s <= hyst_start_s(0) & hyst_i; 	
		end if; 
	end process; 

	--! @brief  dk state machine and counter logic 
	dk_logic: process(dk_state_s,dk_cnt_s,t2_start_ma_i,t2_start_sl_i, 
						hyst_start_s,dk_factor_i,dk_factor_ready_i,dk_factor_ready_s,
						x1_s,x2_s,result_s,y1_s) 
	begin
		-- default assignments for avoiding latches 
		dk_state_next_s <= dk_state_s; 
		dk_cnt_next_s 	<= dk_cnt_s; 
		result_next_s	<= result_s; 
		x1_next_s		<= x1_s; 
		x2_next_s		<= x2_s; 
		
		-- set dk_factor_ready_s high from dk_factor_ready_i' till end of calculation 
		if dk_factor_ready_i = '1' then 
			dk_factor_ready_next_s <= '1'; 	
		else 
			dk_factor_ready_next_s <= dk_factor_ready_s; 	
		end if; 
				
		-- statemachine logic 
		case dk_state_s is 
			when IDLE => 
				if hyst_start_s = "01" then -- Rising edge  
					dk_state_next_s <= WAIT_TRIGGER; 
				end if; 
				
			when WAIT_TRIGGER => 
				if t2_start_sl_i = '1' and t2_start_ma_i = '1' then -- both events together => zero phase
					dk_state_next_s <= MASTERUPDATE; -- could also be SLAVEUPDATE; doesn't matter 
				elsif t2_start_sl_i = '1' then 
					dk_state_next_s <= SLAVECNT; -- slave t1 event came first
				elsif t2_start_ma_i = '1' then 
					dk_state_next_s <= MASTERCNT; -- master t1 event came first 	
				end if; 	
				dk_cnt_next_s <= 0; 
				
			when SLAVECNT => 
				if t2_start_ma_i = '1' then
					dk_state_next_s <= SLAVEUPDATE; 
				elsif t2_start_sl_i = '1' then -- again a slave trigger before first master trigger 
					dk_cnt_next_s <= 0; 
				else -- no trigger signal 
					dk_cnt_next_s <= dk_cnt_s + 1;
				end if; 			
				
			when MASTERCNT => 
				if t2_start_sl_i = '1' then 
					dk_state_next_s <= MASTERUPDATE; 
				elsif t2_start_ma_i = '1' then -- again master trigger before first slave trigger  
					dk_cnt_next_s <= 0; 
				else 
					dk_cnt_next_s <= dk_cnt_s + 1;
				end if; 				
			
			when MASTERUPDATE => 
				if dk_factor_ready_s = '1' then -- start multiplication only if dk_factor ready 
					dk_cnt_next_s <= 0; 
					dk_state_next_s <= MULT; 
					x1_next_s <= std_logic_vector(dk_factor_i); 
					-- decide which direction the correction has to be done 
					if ((dk_cnt_s-DK_WANTED_C <= DK_MAXNEG_C) and (dk_cnt_s > DK_WANTED_C)) then -- go backwards 
						x2_next_s <= std_logic_vector(to_signed(DK_WANTED_C - dk_cnt_s,12)); 
					elsif ((DK_WANTED_C+DK_MAXNEG_C>CMAX_G) and (dk_cnt_s <= DK_WANTED_C + DK_MAXNEG_C - CMAX_G)) then -- go backwards 
						x2_next_s <= std_logic_vector(to_signed(-CMAX_G +DK_WANTED_C - dk_cnt_s,12)); 
					elsif DK_WANTED_C >= dk_cnt_s then -- go forward
						x2_next_s <= std_logic_vector(to_signed(DK_WANTED_C - dk_cnt_s,12)); 
					else 
						x2_next_s <= std_logic_vector(to_signed(CMAX_G - dk_cnt_s + DK_WANTED_C  ,12)); 
					end if; 
				end if; 
				
			when SLAVEUPDATE => 
				if dk_factor_ready_s = '1' then -- start multiplication 
					dk_cnt_next_s <= 0; 
					dk_state_next_s <= MULT;
					x1_next_s <= std_logic_vector(dk_factor_i); 
					-- decide which direction the correction has to be done 
					if(CMAX_G - DK_WANTED_C - dk_cnt_s <= DK_MAXNEG_C) and (CMAX_G-dk_cnt_s >= DK_WANTED_C) then -- go backwards 
						x2_next_s <= std_logic_vector(to_signed(DK_WANTED_C + dk_cnt_s-CMAX_G,12)); 
					elsif dk_cnt_s >= CMAX_G - DK_WANTED_C then -- go forward 
						x2_next_s <= std_logic_vector(to_signed(DK_WANTED_C - CMAX_G + dk_cnt_s ,12)); 
					else 
						x2_next_s <= std_logic_vector(to_signed(DK_WANTED_C+ dk_cnt_s ,12)); 
					end if; 
				end if; 
			-- in MULT, dk_cnt_s is used as supervision 
			when MULT => 
				if dk_cnt_s < CNT_MULT_C then 
					dk_cnt_next_s <= dk_cnt_s +1; 
				else -- calculation done 
					dk_cnt_next_s <= 0; 
					dk_state_next_s <= IDLE; 
					result_next_s <= signed(y1_s(27 downto 12)); -- shift result 12 bits to right
					dk_factor_ready_next_s <= '0'; 
				end if; 
				
				
			when others => 		
			end case;  
	end process; 
	
		-- ======= Component declarations for calculation ================
	my_16_12_mult_inst:  my_16_12_mult 
	port map (
		clock		=> clk_i,
		dataa		=> std_logic_vector(x1_s), 
		datab		=> std_logic_vector(x2_s), 
		result		=> y1_s 
	);

	-- OUTPUT ANOTAITON:
	deltaH_o <= result_s; 
	deltaH_ready_o <= '1' when (dk_state_s = IDLE) else '0'; 
end structural; 