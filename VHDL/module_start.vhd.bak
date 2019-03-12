--==========================================================
-- Unit		:	module_start(rtl)
-- File		:	module_start.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	my_16_mult, signed_limiter, median_filt
--==========================================================

--! @file module_start.vhd
--! @author Michael Hersche
--! @date  21.11.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Enable module after rising edge of enable_i for t1
--! @details Iref and softreset_o are activated during t1 

entity module_start is 
	generic(INW_G 			: natural := 10; --! Input data width of set current 
			T1_G 			: natural := 20000 	--! number of clock cycles the controller is enabled
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous nreset 
			nsoftreset_i	: in std_logic; --! synchronous nreset 
			enable_i		: in std_logic; --! Start/enable signal 
			iset_i			: in std_logic_vector(INW_G-1 downto 0); 
			nsoftreset_o	: out std_logic; --! softreset for whole controller 
			iset_o			: out std_logic_vector(INW_G-1 downto 0)
			);		
end module_start;


architecture structural of module_start is
-- ================== CONSTANTS ==================================================


-- =================== STATES ====================================================


-- =================== SIGNALS ===================================================
signal iset_s, iset_next_s : std_logic_vector(INW_G-1 downto 0) := (others => '0');
signal nsoftreset_s,nsoftreset_next_s : std_logic := '1'; 
signal cnt_s, cnt_next_s : natural range 0 to T1_G := 0;  
signal enable_vec_s : std_logic_vector(1 downto 0) := "00"; 

-- ================== COMPONENTS =================================================

begin
--
	
REG: process(clk_i, nreset_i)
begin 
	if nreset_i = '0' then 
		cnt_s <= 0; 
		iset_s <= (others => '0');
		enable_vec_s <= "00"; 
		nsoftreset_s <= '0'; 
	elsif rising_edge(clk_i) then 
		if nsoftreset_i = '0' then 
			cnt_s <= 0; 
			iset_s <= (others => '0');
			enable_vec_s <= enable_vec_s(0) & enable_i; -- not included in softreset case (otherwise always start) 
			nsoftreset_s <= '0'; 
		else 
			cnt_s <= cnt_next_s; 
			iset_s <= iset_next_s; 
			enable_vec_s <= enable_vec_s(0) & enable_i; 
			nsoftreset_s <= nsoftreset_next_s; 
		end if; 
	end if; 
end process REG;


LOG: process(cnt_s, enable_vec_s, iset_s) 
begin
	if enable_vec_s = "01" then -- rising edge 
		cnt_next_s <= 1; 
		iset_next_s <= iset_i; 
		nsoftreset_next_s <= '1';  
	elsif cnt_s > 0 and cnt_s < T1_G  then 
		cnt_next_s <= cnt_s + 1; 
		iset_next_s <= iset_i; 
		nsoftreset_next_s <= '1';  
	else 
		cnt_next_s <=0; 
		iset_next_s <= (others => '0'); 
		nsoftreset_next_s <= '0';
	end if; 
end process LOG; 
		

nsoftreset_o <= nsoftreset_s;
iset_o		 <= iset_s;		

 
end structural; 