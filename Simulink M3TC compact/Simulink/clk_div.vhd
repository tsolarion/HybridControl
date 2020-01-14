--==========================================================
-- Unit		:	clk_div(rtl)
-- File		:	clk_div.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file clk_div.vhd
--! @author Michael Hersche
--! @date  06.11.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief clk_div block for dividing clock, dont use as input of registers becaus not locked !!!!
entity clk_div is 
	generic( 	
			IN_FREQ_G 			: real := 100000.0;  --! input frequency in kHz
			OUT_FREQ_G			: real := 60.0 --!   --! input frequency in kHz
			);		
	port( 	clk_i			: in std_logic; --! main system clock
			nreset_i 		: in std_logic; --! asynchronous nreset 
			clk_div_o		: out std_logic
			);
end clk_div;

architecture structural of clk_div is
-- ================== CONSTANTS ==================================================				
constant TOP_CNT : natural := integer(IN_FREQ_G/(2.0*OUT_FREQ_G)); 
-- ================== COMPONENTS =================================================
	
-- =================== STATES ====================================================


-- =================== SIGNALS ===================================================
signal cnt_s, cnt_next_s : natural range 0 to TOP_CNT-1 := 0; 
signal clk_div_s, clk_div_next_s: std_logic := '0'; 

begin		

	-- State machine and counter Registers 
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			clk_div_s 	<= '0'; 
			cnt_s 		<= 0; 
		elsif rising_edge(clk_i) then
			clk_div_s 	<= clk_div_next_s;  
			cnt_s 		<= cnt_next_s;  
		end if; 
	end process; 
	
	-- State machine and counter logic 
	counter_logic: process(cnt_s,clk_div_s) 
	begin
		if cnt_s =  TOP_CNT-1 then 
			clk_div_next_s <= not clk_div_s; 
			cnt_next_s <= 0; 
		else 
			clk_div_next_s <= clk_div_s; 
			cnt_next_s <= cnt_s +1; 
		end if; 
	end process; 
	
	-- output assignments
	clk_div_o <= clk_div_s; 
	
			
end structural; 