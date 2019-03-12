--==========================================================
-- Unit		:	runtime_limiter(rtl)
-- File		:	runtime_limiter.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file runtime_limiter.vhd
--! @author Michael Hersche
--! @date  05.11.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Limit the numnber of main clock cycles the where block outputs the signals
entity runtime_limiter is 
	generic( 	
			RUN_CYCLES_G 		: integer := 20000; --! number of main clock cycles
			NO_CONTROLER_G 		: integer := 1 --! number of controler
			
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous softreset 
			sw_i			: in std_logic_vector(2*NO_CONTROLER_G-1 downto 0); --! PWM switch input 
			sw_o			: out std_logic_vector(2*NO_CONTROLER_G-1 downto 0) --! PWM switch output  			
			);
end runtime_limiter;

architecture structural of runtime_limiter is
-- ================== CONSTANTS ==================================================				

-- ================== COMPONENTS =================================================
	
-- =================== STATES ====================================================

-- =================== SIGNALS ===================================================
signal cnt_s, cnt_next_s : integer := 0; --! start counter 

signal sw_s, sw_next_s:  std_logic_vector(2*NO_CONTROLER_G-1 downto 0) := (others => '0'); --! intermediate signal (to keep synchronous) 

begin		

	-- State machine and counter Registers 
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			cnt_s <= 0; 
			sw_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				cnt_s <= 0; 
				sw_s <= (others => '0'); 
			else 
				cnt_s <= cnt_next_s; 
				sw_s <= sw_next_s;
			end if; 
		end if; 
	end process; 
	
	--counter logic 
	statemachine_logic: process(cnt_s,sw_i) 
	begin
		if cnt_s < RUN_CYCLES_G then 
			cnt_next_s <= cnt_s + 1; 
			sw_next_s <= sw_i; 
		else 
			cnt_next_s <= cnt_s; 
			sw_next_s <= (others => '0'); 
		end if; 
		
	end process; 
	
	-- output assignments 
	sw_o <= sw_s; 

			
end structural; 