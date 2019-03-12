--==========================================================
-- Unit		:	and_reduce_edge(rtl)
-- File		:	and_reduce_edge.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file and_reduce_edge.vhd
--! @author Michael Hersche
--! @date  15.01.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Output result_o goes high if all data_i components went high once 
--! @details 
--! @details 

entity and_reduce_edge is 
	generic( 	NO_CONTROLER_G 	: integer := 2 --! Total number of controler used
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			nsoftreset_i	: in std_logic; --! Synchronous nreset 
			data_i			: in std_logic_vector(NO_CONTROLER_G-1 downto 0); --! Input vector 
			result_o		: out std_logic --! 
			);
			
end and_reduce_edge;


architecture structural of and_reduce_edge is
-- ================== CONSTANTS ==================================================				
constant ONE_VECTOR_C : std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '1'); 
-- ================== COMPONENTS =================================================

-- =================== STATES ====================================================
signal data_reg_s, data_reg_next_s : std_logic_vector(NO_CONTROLER_G-1 downto 0) := (others => '0'); 
signal result_next_s, result_s : std_logic := '0'; 
-- =================== SIGNALS ===================================================


begin	
		

	--! @brief Input registers 
	--! @details Asynchronous reset nreset_i, and softreset 
	input_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			data_reg_s <= (others => '0'); 
			result_s <= '0'; 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				data_reg_s <= (others => '0'); 
				result_s <= '0'; 
			else 
				data_reg_s <= data_reg_next_s ; 
				result_s <= result_next_s;
			end if; 
		end if; 
	end process; 
			
	--! @brief Logic 
	proc_logic: process(data_i,data_reg_s,nsoftreset_i) 
	begin
		data_reg_next_s <= data_reg_s; 
		
		if nsoftreset_i = '0' then 
			data_reg_next_s <= (others => '0'); 
			result_next_s <= '0'; 
		else		
			for i in 0 to NO_CONTROLER_G-1 loop 
				if (data_i(i) = '1') then 
					data_reg_next_s(i) <= '1'; 
				end if; 
			end loop; 
		
			if data_reg_s = ONE_VECTOR_C then 
				result_next_s <= '1'; 
			else 
				result_next_s <= '0';
			end if; 
		end if; 
	end process; 


result_o <= result_s; 
end structural; 