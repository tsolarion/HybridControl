--==========================================================
-- Unit		:	startup(rtl)
-- File		:	startup.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file startup.vhd
--! @author Michael Hersche
--! @date  06.11.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Startup block for automatic interleaving of modules 
entity startup is 
	generic( 	
			MY_NUMBER_G 		: integer := 0;  --! index of current slave: 0 indicates master 
			CMAX_G				: integer := 1666 --!  Maximum counter value of PWM (determines PWM frequency) 
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous nreset 
			nsoftreset_o	: out std_logic; --! synchronous reset signal for PWM 
			sw2_o			: out std_logic; --! low side output switch 		
			half_duty_o		: out std_logic --! use only half of dutycycle in startup 
			);
end startup;

architecture structural of startup is
-- ================== CONSTANTS ==================================================				
type T_DATA is array (0 to 5) of integer;
constant START_DELAY : T_DATA :=
            (0,
			277,
			554, 
			0, 
			277,
			554);
			
constant DOWN_DELAY : T_DATA := 
			(758,
			758,
			758,
			0,
			0,
			0);
-- ================== COMPONENTS =================================================
	
-- =================== STATES ====================================================
type startup_state  is (WAIT_DELAY, WAIT_IMIN,STARTUP,START_UPDONE); --! interlocking states 

-- =================== SIGNALS ===================================================
signal cnt_s, cnt_next_s : integer := 0; --! interlocking counter 
signal state_s, state_next_s : startup_state := WAIT_DELAY; --! counter states
signal soft_nreset_s,soft_nreset_next_s: std_logic := '0'; 
signal sw2_s,sw2_next_s: std_logic := '0'; 
signal half_duty_s, half_duty_next_s : std_logic := '0'; 


begin		

	-- State machine and counter Registers 
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			state_s <= WAIT_DELAY; 
			cnt_s <= 0; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				state_s <= WAIT_DELAY; 
				cnt_s <= 0; 
			else 
				state_s <= state_next_s; 
				cnt_s <= cnt_next_s; 
			end if; 
		end if; 
	end process; 
	
	-- State machine and counter logic 
	statemachine_logic: process(state_s,cnt_s) 
	begin
		-- default assignment to avoid latches 
		cnt_next_s <= cnt_s; 
		state_next_s <= state_s; 
		case state_s is 
			when WAIT_DELAY => 
				if cnt_s = START_DELAY(MY_NUMBER_G) then 
					if DOWN_DELAY(MY_NUMBER_G) /= 0 then 
						state_next_s <= WAIT_IMIN; 
						cnt_next_s <= 0; 
					else 
						state_next_s <= STARTUP; 
						cnt_next_s <= 0; 
					end if; 
				else 
					cnt_next_s <= cnt_s + 1; 
				end if; 
				
			when STARTUP => 
				if cnt_s = CMAX_G then 
					state_next_s <= START_UPDONE; 
				else 
					state_next_s <= STARTUP; 
					cnt_next_s <= cnt_s + 1;
				end if; 				
				
			when WAIT_IMIN => 
				if cnt_s = DOWN_DELAY(MY_NUMBER_G) then 
					state_next_s <= START_UPDONE; 
				else 
					cnt_next_s <= cnt_s + 1; 
				end if; 
								
			when START_UPDONE => 
				state_next_s <= START_UPDONE; 
				cnt_next_s <= 0; 
			when others => 
				cnt_next_s <= 0; 
				state_next_s <= START_UPDONE; 
			end case; 
	end process; 
	
	-- State machine and counter logic 
	output_logic: process(state_s,sw2_s,soft_nreset_s, half_duty_s) 
	begin
		-- default statements for avoiding latches
		sw2_next_s <= sw2_s; 
		soft_nreset_next_s <= soft_nreset_s; 
		half_duty_next_s <= half_duty_s;
		-- 
		case state_s is 
			when WAIT_DELAY => 
				sw2_next_s <= '0'; 
				soft_nreset_next_s <= '0'; 
				half_duty_next_s <= '0'; 
			when STARTUP => 
				sw2_next_s <= '0'; 
				soft_nreset_next_s <= '1'; 			
				half_duty_next_s <= '1'; 
			when WAIT_IMIN => 
				sw2_next_s <= '1'; 
				soft_nreset_next_s <= '0'; 
				half_duty_next_s <= '0'; 
			when START_UPDONE => 
				sw2_next_s <= '0'; 
				soft_nreset_next_s <= '1';			
				half_duty_next_s <= '0'; 
			end case; 
	end process; 
	

	
	-- Output register  
	OUT_REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			sw2_s <= '0'; 
			soft_nreset_s <= '1'; 
			half_duty_s <= '0'; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				sw2_s <= '0'; 
				soft_nreset_s <= '1'; 
				half_duty_s <= '0'; 
			else 
				sw2_s <= sw2_next_s; 
				soft_nreset_s <= soft_nreset_next_s; 
				half_duty_s <= half_duty_next_s; 
			end if; 
		end if; 
	end process;
	
	-- output assignments 
	sw2_o <= sw2_s; 
	nsoftreset_o <= soft_nreset_s; 
	half_duty_o <= half_duty_s; 
	
	
	
	
			
end structural; 