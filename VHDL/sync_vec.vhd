--==========================================================
-- Unit		:	sync_vec(rtl)
-- File		:	sync_vec.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file sync_vec.vhd
--! @author Michael Hersche
--! @date  11.12.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @Synchronization of ansync_vechronous input std_logic with N_REG_G registers  
entity sync_vec is 
	generic(N_REG_G	: natural range 2 to 10:= 2; 
			INW_G	: natural range 1 to 100:= 16
		); 
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Async_vechronous reset 
			data_i			: in std_logic_vector(INW_G-1 downto 0); --! asynchronous input 
			data_o			: out std_logic_vector(INW_G-1 downto 0) --! synchronous output 
			);		
end sync_vec;


architecture structural of sync_vec is

-- =================== SIGNALS ===================================================
type data_array is array (natural range <>) of std_logic_vector(INW_G-1 downto 0); 

signal data_s : data_array(N_REG_G-1 downto 0); 

begin		

	--! @brief Registers
	REG : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			data_s <= (others =>(others => '0')); 
		elsif rising_edge(clk_i) then
			data_s(N_REG_G-1 downto 1) <= data_s(N_REG_G-2 downto 0);  
			data_s(0) <= data_i;  
		end if; 
	end process; 
	-- OUTPUT ANOTAITON:
	data_o <= data_s(N_REG_G-1); 	
	
end structural; 