--==========================================================
-- Unit		:	sync(rtl)
-- File		:	sync.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file sync.vhd
--! @author Michael Hersche
--! @date  11.12.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @Synchronization of ansynchronous input std_logic with N_REG_G registers  
entity sync is 
	generic(N_REG_G	: natural range 2 to 10:= 2
		); 
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			data_i			: in std_logic; --! asynchronous input 
			data_o			: out std_logic --! synchronous output 
			);		
end sync;


architecture structural of sync is
-- =================== SIGNALS ===================================================
signal data_s : std_logic_vector(N_REG_G-1 downto 0); 

begin		

	--! @brief Registers
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			data_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			data_s <= data_s(N_REG_G-2 downto 0) & data_i;  
		end if; 
	end process; 
	-- OUTPUT ANOTAITON:
	data_o <= data_s(N_REG_G-1); 	
	
end structural; 