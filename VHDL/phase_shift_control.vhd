--==========================================================
-- Unit		:	phase_shift_control.vhd(rtl)
-- File		:	phase_shift_control.vhd.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file phase_shift_control.vhd.vhd
--! @author Michael Hersche
--! @date  24.10.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Measures Phase shift between two signals and calculates the 
--! @brief phase shift (in terms of maximum countervalue) 
entity phase_shift_control is 
	generic( 	CNT_RES_G 		: natural := 12; --! Number of Bits counter 
				CMAX_G 			: integer := 2500; --! Generic Maximum counter value of PWM 
				NO_CONTROLER_G 	: integer := 2; --! Total number of control modules used
				MY_NUMBER_G 	: integer := 1 --! Current slave number 
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i 	: in std_logic; --! synchronous reset the phase shift calculation and start again (Active!)
			pwm_ma_start_i	: in std_logic; --! pwm master starts new cycle  
			pwm_sl_start_i	: in std_logic; --! pwm slave starts new cycle
			cnt_top_slave_o : out unsigned(CNT_RES_G downto 0) --! output counter top value (intentionally one bit longer than CNT_RES_G due to possible double value)	
			);
			
end phase_shift_control;

architecture structural of phase_shift_control is
-- ================== CONSTANTS ==================================================				
constant DELTA_C_STAR_C : integer range 0 to 2*CMAX_G := (CMAX_G * MY_NUMBER_G)/(NO_CONTROLER_G); -- wanted counter difference 
constant MAX_DELTA_C : integer range 0 to 2*CMAX_G := CMAX_G/2; -- maximum change in counter value (here 20%)
-- ================== COMPONENTS =================================================
	
-- =================== STATES ====================================================
type state_t is (COUNTING_UP, IDLE,UPDATE); --! counter states 
type dev_state is (IDLE,TOOHIGH, TOOLOW, GOBACKWARDS); 	-- supervision of output value

-- =================== SIGNALS ===================================================
signal cnt_s, cnt_next_s : integer range 0 to 2*CMAX_G:= 0; --! counts from master edge to slave edge  
signal cnt_top_next_s : integer range 0 to 2*CMAX_G := CMAX_G; --! output value 

signal phase_s, phase_next_s : state_t := IDLE; --! counter states
signal dev_state_s,dev_state_next_s: dev_state:= IDLE;  --! supervision states 

begin		
	-- State machine and counter Registers 
	statemachine_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			phase_s <= IDLE; 
			cnt_s <= 0; 
			dev_state_s<= IDLE; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				phase_s <= IDLE; 
				cnt_s <= 0; 
				dev_state_s<= IDLE; 
			else 
				phase_s <= phase_next_s; 
				cnt_s <= cnt_next_s; 
				dev_state_s<= dev_state_next_s; 
			end if; 
		end if; 
	end process; 
	

		
	-- State machine and counter logic 
	statemachine_logic: process(phase_s,cnt_s,pwm_ma_start_i,pwm_sl_start_i) 
	begin
		-- default assignment to avoid latches 
		cnt_next_s <= cnt_s; 
		
		case phase_s is 
			when IDLE => 
				if pwm_ma_start_i = '1' then 
					if pwm_sl_start_i = '1' then -- both edges come together  
						phase_next_s <= UPDATE; 
						cnt_next_s <= 0; 
					else 
						phase_next_s <= COUNTING_UP; 
						cnt_next_s <= 0; 
					end if; 
				else 
					phase_next_s <= IDLE;
					cnt_next_s <= cnt_s; 
				end if; 
			when COUNTING_UP => 
				if pwm_ma_start_i = '1' then -- again a new starting of pwm because of restart 
					cnt_next_s <= 0; 
					phase_next_s <= COUNTING_UP; 
				elsif pwm_sl_start_i = '1' then 
					phase_next_s <= UPDATE; 
					cnt_next_s <= cnt_s; 
				else
					cnt_next_s <= cnt_s + 1; 
					phase_next_s <= COUNTING_UP; 
				end if; 
			when UPDATE => 
				if pwm_sl_start_i = '1' then -- only leave update when slave pwm cycle is completed. 
					phase_next_s <= IDLE; 
				else 
					phase_next_s <= UPDATE; 
				end if; 
			when others => 
				cnt_next_s <= DELTA_C_STAR_C; 
				phase_next_s <= IDLE; 
			end case; 
	
	end process; 

	--! @brief Determine the state for the next update 
	proc_deviation_supervision: process(cnt_s)
	begin
		
		if DELTA_C_STAR_C - cnt_s > MAX_DELTA_C then -- deviation too high 
			dev_state_next_s <= TOOHIGH; 
		elsif DELTA_C_STAR_C - cnt_s < -MAX_DELTA_C then -- deviation too low 
			dev_state_next_s <= TOOLOW; 
		elsif CMAX_G - DELTA_C_STAR_C + cnt_s < DELTA_C_STAR_C - cnt_s then -- go backwards 
			dev_state_next_s <= GOBACKWARDS;  
		else 					
			dev_state_next_s <= IDLE;  
		end if; 
	end process; 
	
	
	
	--! @brief Calculation of new top counter value 
	--! @details Only update value if not counting
	proc_next_counter: process(cnt_s,phase_s,dev_state_s)
	begin 
		case phase_s is
			when UPDATE => 
				-- update cases 
				case dev_state_s is
					when TOOHIGH => 
						cnt_top_next_s <= CMAX_G + MAX_DELTA_C; 
					when TOOLOW => 
						cnt_top_next_s <= CMAX_G - MAX_DELTA_C; 
					when GOBACKWARDS =>
						cnt_top_next_s  <= DELTA_C_STAR_C - cnt_s; 
					when IDLE=> 
						cnt_top_next_s <= CMAX_G + DELTA_C_STAR_C - cnt_s;
					when others => 
						cnt_top_next_s <= CMAX_G; 
				end case; 
				
			when COUNTING_UP =>
				cnt_top_next_s <= CMAX_G; 
			when IDLE => 
				cnt_top_next_s <= CMAX_G; 
			when others => 
				cnt_top_next_s <= CMAX_G; 
		end case; 
				
	end process;

	
	--! @brief Output register 
	reg_output : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			cnt_top_slave_o <= to_unsigned(CMAX_G,CNT_RES_G+1); 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				cnt_top_slave_o <= to_unsigned(CMAX_G,CNT_RES_G+1); 
			else 
				cnt_top_slave_o <= to_unsigned(cnt_top_next_s,CNT_RES_G+1); 	
			end if; 
		end if; 
	end process;  
				
			
end structural; 