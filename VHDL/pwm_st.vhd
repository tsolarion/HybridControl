--==========================================================
-- Unit		:	pwm_st(rtl)
-- File		:	pwm_st.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file pwm.vhd
--! @author Michael Hersche
--! @date  10.10.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief SAWTOOTH PWM GENERATION
--! @details It can use a clock signal of e.g. 100 MHz
ENTITY pwm_st IS
  GENERIC(
		CNT_RES_G : integer :=12; --counter resolution in bits
		CNT_TOP_G : integer := 2500; --upper limit for the reference signal (depends on the scaling of the duty_i cycle)
		INIT_CNT_G : integer range 0 to 4095 :=0; --this is for initial phase shift if need be
		CNT_INTERLOCK_G : integer range 0 to 4095 := 0; -- this corresponds to deadtime of 1 us for my system
		IND_WIDTH: natural := 11
		);	
  PORT(
		clk_i		: in  std_logic;  --! main system clock
			nreset_i    : in  std_logic;  --! asynchronous nreset_i
			enable_i    : in  std_logic;  --! enable_i signal
			duty_i      : in  unsigned(IND_WIDTH-1 downto 0); --! Dutycycle 
			cnt_top_i	: in unsigned(12 downto 0); --! counter top value (for additional phase shift) 
			switch1_o   : out std_logic; --! High switch output
			switch2_o   : out std_logic; --! Low switch output 
			start_pwm_cycle_o: out std_logic; --! indicates start of a new pwm cycle 
			pwm_count_o: out signed(15 downto 0) --! PWM counter value (only for testing) 
			);				            								
END pwm_st;

architecture rtl of pwm_st is 

-- ================== CONSTANTS ==================================================				
	constant REF_UPPER_C 	: integer := CNT_TOP_G-CNT_INTERLOCK_G; -- Upper limit of the reference signal
	constant REF_LOWER_C 	: integer := CNT_INTERLOCK_G; 			-- Lower limit
	
-- =================== SIGNALS ===================================================
	signal count_clk_s 		: std_logic;							--trigger sampling signal
	signal count_s 			: integer range 0 to 2**(CNT_RES_G+1)-1;				--carrier
	signal ref_sat_s		: integer range 0 to 2**(CNT_RES_G+1)-1;	--input after saturation...
	signal cnt_top_s 		: integer range 0 to 2**(CNT_RES_G+1)-1 := CNT_TOP_G;  --  
	signal next_duty_candidate: integer range 0 to 2**(CNT_RES_G+1)-1;
-- =================== STATES ====================================================
	type state_t is (SW_ON, SW_OFF, SW_DISABLED, SW_INTERLOCK);
	signal current_state_s, next_state_s : state_t;
	

	begin
	--Generation of carrier using counter:
	counter : process(clk_i, nreset_i)
		variable cnt: integer range 0 to 2**(CNT_RES_G+1)-1; --counter value
		variable count_zero : STD_LOGIC;
	begin
		if nreset_i = '0' then
			cnt := INIT_CNT_G;
			count_zero := '0';
		elsif rising_edge(clk_i) then
			cnt := cnt+1;				-- count_s up
			count_zero := '0';			-- do not trigger sampling
				if cnt>=cnt_top_s or enable_i = '0' then
					cnt:=0;				-- start a new cycle
					count_zero := '1';	-- trigger sampling
				end if;
		end if;
		count_s <=cnt;
		count_clk_s <=count_zero;
	end process;
	
	-- Sample and saturate reference signal:
	-- Reference signal cannot be less than the required interlocking and not bigger than 4095-Interlocking
	sample: process(clk_i,nreset_i)
		variable ref_val : integer range 0 to 4095;
	begin
		if nreset_i = '0' then
			ref_sat_s <= 0;
			cnt_top_s <= CNT_TOP_G; 
			ref_val := 0;
		elsif rising_edge(clk_i) then
			--if count_clk_s = '1' then 
				cnt_top_s <= to_integer(cnt_top_i);
				ref_val := next_duty_candidate;		--convert duty_i to integer so that it can be compared to counter. 
				if ref_val > REF_UPPER_C then 
					ref_sat_s <= REF_UPPER_C;
				elsif ref_val < REF_LOWER_C then
					ref_sat_s <= REF_LOWER_C;
				else
					ref_sat_s <=ref_val;
				end if;
			--end if; 
		end if;
	end process;
	
	next_duty_candidate <= (to_integer(duty_i)*CNT_TOP_G)/2048;
	
	-- State Machine Process:
	
	state_transition : process(clk_i,nreset_i)
	begin 
		if nreset_i = '0' then 
			current_state_s <= SW_DISABLED;
		elsif rising_edge(clk_i) then 
			if enable_i = '0' then -- softnreset 
				current_state_s <= SW_DISABLED;
			else 
				current_state_s <= next_state_s;
			end if; 
		end if;
	end process;
	
	state_machine : process(enable_i, count_s, ref_sat_s, current_state_s)			-- not sure about this sensitivity list
		begin
			case current_state_s is
				when SW_ON =>
					switch1_o <= '1';
					switch2_o <= '0';
					--if enable_i = '0' then 
						--next_state_s <= SW_DISABLED;
					if ref_sat_s >= count_s then 
						next_state_s <=SW_ON;
					elsif ref_sat_s< count_s and count_s<= ref_sat_s+CNT_INTERLOCK_G then
						next_state_s <=SW_INTERLOCK;
					else 
						next_state_s <=SW_OFF;
					end if;
					
				when SW_OFF =>
					switch1_o <= '0';
					switch2_o <= '1';
					--if enable_i = '0' then 
						--next_state_s <= SW_DISABLED;
					-- if ref_sat_s <= count_s then 
						-- next_state_s <=SW_OFF;
					-- elsif ref_sat_s>count_s and count_s<82 then
						-- next_state_s <= SW_INTERLOCK;
					-- else 
						-- next_state_s <=SW_ON;
					-- end if;
					if count_s = 0 then 
						next_state_s <= SW_INTERLOCK; 
					else 
						next_state_s <= SW_OFF; 
					end if; 
					
					
				when SW_DISABLED =>
					switch1_o <= '0';
					switch2_o <= '0';
					if enable_i = '0' then 
						next_state_s <= SW_DISABLED;
					elsif ref_sat_s>count_s then 
						next_state_s <= SW_ON;
					else
						next_state_s <= SW_OFF;
					end if;
					
				when SW_INTERLOCK =>
					switch1_o <= '0';
					switch2_o <= '0';
					--if enable_i = '0' then 
						--next_state_s <= SW_DISABLED;
					if count_s<= CNT_INTERLOCK_G then 
						next_state_s <= SW_INTERLOCK;
					elsif count_s>ref_sat_s and count_s <= ref_sat_s+CNT_INTERLOCK_G then 
						next_state_s <= SW_INTERLOCK;
					elsif count_s > ref_sat_s+CNT_INTERLOCK_G then 
						next_state_s <=SW_OFF;
					else
						next_state_s <=SW_ON;
					end if;
					
			end case;
		end process;
	
	start_pwm_cycle_o <= '1' when count_s = 1 else '0'; 
	pwm_count_o 	<= to_signed(count_s,16); 
	
end rtl;