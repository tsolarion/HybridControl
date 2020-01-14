--==========================================================
-- Unit		:	modeDetection(rtl)
-- File		:	modeDetection.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
-- testbench: tb_serialize_detection.vhd 
--==========================================================

--! @file modeDetection.vhd
--! @author Pascal Zähner 
--! @date  06.12.2018

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

-- Revised by M.H. on 30.11.2018  

-- 8 bit word with start word 11110 and 3 bits for mode
entity modeDetection is	
   port (
      nreset_i			: in std_logic; -- Asynchronous reset
	  opt_mode_i		: in std_logic; -- serialized mode input
	  clk_i         	: in std_logic; -- main clock
      ov_mode_o     	: out std_logic_vector(2 downto 0) -- decoded mode
   );
end entity;

architecture rt1 of modeDetection is
-- ================== CONSTANTS ==================================================
-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
-- =================== SIGNALS =================================================== 
signal counter_s, counter_next_s	: integer range 0 to 11 := 0; -- security counter, turn off if no mode detected
signal ov_s, ov_next_s			: std_logic_vector(2 downto 0); -- mode vector for output
signal mode_reg_s				: std_logic_vector(7 downto 0); -- buffer for received data
 
begin

--! @brief Register update
REG: process(clk_i, nreset_i)
begin 
	if nreset_i = '0' then
		counter_s 	<= 1;
		ov_s 		<= (others => '0');
		mode_reg_s 	<= (others => '0');
	elsif rising_edge(clk_i) then
		counter_s 	<= counter_next_s; 
		ov_s 		<= ov_next_s; 
		mode_reg_s 	<= mode_reg_s(6 downto 0) & opt_mode_i; 
	end if; 
end process; 

-- logic process 
LOG: process(counter_s, ov_s, mode_reg_s) 
begin 
	-- default assignments for avoiding Latches 
	counter_next_s 	<= counter_s + 1;
	ov_next_s		<= ov_s; 
	
	if (mode_reg_s(7 downto 3) = "11110") then	--
		if( unsigned(mode_reg_s(2 downto 0)) < 6 ) then	--if mode correct set it
			ov_next_s <= mode_reg_s(2 downto 0);
		else
			ov_next_s <= (others => '0');	-- if mode is wrong go to IDLE
		end if;
		counter_next_s <= 1;
	else
		if counter_s = 10 then	-- if no mode is detected go to idle
			counter_next_s <= 1;
			ov_next_s <= (others => '0');
		
		end if;
	end if;
	
end process; 
-- output assignment
ov_mode_o <= ov_s;
end architecture;