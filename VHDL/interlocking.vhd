--==========================================================
-- Unit		:	interlocking.vhd(rtl)
-- File		:	interlocking.vhd.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file interlocking.vhd.vhd
--! @author Michael Hersche
--! @date  24.10.2017

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Generates interlocked high side and low side signal out of one high side signal 
entity interlocking is 
	generic( 	NINTERLOCK_G 	: natural := 50 --! Number of Bits counter 
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous reset 
			sw1_i			: in std_logic; --! high switch 
			sw2_i			: in std_logic; --! low switch (only used for start up)
			int_sw1_o		: out std_logic; --! high side output switch  
			int_sw2_o		: out std_logic; --! low side output switch 			
			interl_o		: out std_logic --! interlocking state 
			);
end interlocking;

architecture structural of interlocking is
-- ================== CONSTANTS ==================================================				

-- ================== COMPONENTS =================================================
	
-- =================== STATES ====================================================
type interlocking_state is (IDLE, S1_HIGH,S2_HIGH,INT1,INT2); --! interlocking states 

-- =================== SIGNALS ===================================================
signal cnt_s, cnt_next_s : integer range 0 to NINTERLOCK_G := 0; --! interlocking counter 
signal state_s, state_next_s : interlocking_state := IDLE; --! counter states

begin		

	-- State machine and counter Registers 
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			state_s <= IDLE; 
			cnt_s <= 0; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				state_s <= IDLE; 
				cnt_s <= 0; 
			else 
				state_s <= state_next_s; 
				cnt_s <= cnt_next_s; 
			end if; 
		end if; 
	end process; 
	
	-- State machine and counter logic 
	statemachine_logic: process(state_s,cnt_s,sw1_i,sw2_i) 
	begin
		-- default assignment to avoid latches 
		cnt_next_s <= cnt_s; 
		state_next_s <= state_s; 
		
		case state_s is 
			when IDLE => 
				if sw1_i = '1' then -- rising edge 
					state_next_s <= S1_HIGH; 
					cnt_next_s <= 0; 
				elsif sw2_i = '1' then -- start with a low switch signal 
					state_next_s <= S2_HIGH; 
					cnt_next_s <= 0; 
				end if; 
			when S1_HIGH => 
				if cnt_s = NINTERLOCK_G then 
					if sw1_i = '0' then -- falling edge 
						state_next_s <= INT1; 
						cnt_next_s <= 0; 
					end if; 
				else 
					cnt_next_s <= cnt_s + 1;
				end if; 
				
			when INT1 => 
				if cnt_s = NINTERLOCK_G then 
					if sw1_i = '0' then 
						state_next_s <= S2_HIGH; 
					elsif sw1_i = '1' then 
						state_next_s <= S1_HIGH; 
					end if; 
					cnt_next_s <= 0; 
				else 
					cnt_next_s <= cnt_s + 1; 
				end if; 				
			when S2_HIGH => 
				if cnt_s = NINTERLOCK_G then 
					if sw1_i = '1' then -- rising edge 
						state_next_s <= INT2; 
						cnt_next_s <= 0; 
					end if; 
				else 
					cnt_next_s <= cnt_s + 1; 
				end if; 
					
			when INT2 => 
				if cnt_s = NINTERLOCK_G then 
					if sw1_i = '0' then 
						state_next_s <= S2_HIGH; 
					elsif sw1_i = '1' then 
						state_next_s <= S1_HIGH; 
					end if; 
					cnt_next_s <= 0; 
				else 
					cnt_next_s <= cnt_s + 1; 
				end if; 	
			when others => 
				cnt_next_s <= 0; 
				state_next_s <= IDLE; 
			end case; 
	end process; 
	
	-- outputs 
	int_sw1_o <= '1' when state_s = S1_HIGH else '0'; 
	int_sw2_o <= '1' when state_s = S2_HIGH else '0'; 
	interl_o  <= '1' when state_s = INT1 or state_s = INT2 else '0'; 
	
			
end structural; 