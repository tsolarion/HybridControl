--==========================================================
-- Unit		:	fp_conversion(rtl)
-- File		:	fp_conversion.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	fp32_signed16_conv
--==========================================================

--! @file fp_conversion.vhd
--! @author Michael Hersche
--! @date  13.11.2018
--! @version 1.0

library work; 
USE work.stdvar_arr_pkg.all;
-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief Conversion of PI gains and set current 
--! @details Input PI gains are original floating points values 
--! @details Output is fixed point value 4.12 , be aware that integer ranges from [-8 7]
--! @details Iset current: Input is total current in fixed point, output is array of current per module 

entity fp_conversion is 
	generic( 	
				-- Iset settings 
				MEAS_I_DATAWIDTH_G 	: integer range 8 to 16 := 13;  --! Data width of current measurements  
				NO_CONTROLER_G		: integer range 1 to 6 := 1
				
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			iset_i			: in std_logic_vector(10 downto 0); --! Total set current as signed value in [A] 
			kixts_fp_i		: in std_logic_vector(31 downto 0); --! integral gain PI controller in 32bit single precision 
			kp_fp_i			: in std_logic_vector(31 downto 0); --! proportional gain PI controller in 32bit single precision 
			iset_o			: out array_signed_in(NO_CONTROLER_G-1 downto 0); --! Output set current fixed point (11 bit integer, 2 bits fractional) 
			kixts_o			: out signed(15 downto 0); --! 4 bit int, 12 bit fractional 
			kp_o			: out signed(15 downto 0) --! 4bit int, 12 bit fractional 
			);		
end fp_conversion;


architecture structural of fp_conversion is
-- ================== CONSTANTS ==================================================				

-- ================== COMPONENTS =================================================

-- Floating point 32  to fixed point 16 (4 integer, 12 fractional) conversion 
COMPONENT fp32_signed16_conv IS
	PORT
	(
		clock		: IN STD_LOGIC ;
		dataa		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		nan			: OUT STD_LOGIC ;
		overflow	: OUT STD_LOGIC ;
		result		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
		underflow	: OUT STD_LOGIC 
	);
END COMPONENT;


-- =================== STATES ====================================================


-- =================== SIGNALS ===================================================
signal kixts_s, kp_s : std_logic_vector(15 downto 0):= (others => '0'); 
signal iset_tot_s : std_logic_vector(MEAS_I_DATAWIDTH_G -1 downto 0) := (others => '0'); 
signal iset_s : signed(MEAS_I_DATAWIDTH_G -1 downto 0):= (others => '0'); 

begin

PI_kixts_conv : fp32_signed16_conv
port map 
(   clock 	=> clk_i, 
	dataa 	=> kixts_fp_i, 
	nan 	=> open, 
	overflow=> open, 
	result 	=> kixts_s, 
	underflow=>open
); 

PI_kp_conv : fp32_signed16_conv
port map 
(   clock 	=> clk_i, 
	dataa 	=> kp_fp_i, 
	nan 	=> open, 
	overflow=> open, 
	result 	=> kp_s, 
	underflow=>open
); 


dividing_proc: process (clk_i, nreset_i)
begin 
	if nreset_i = '0' then 
		iset_s <= (others => '0'); 
	elsif rising_edge(clk_i) then 
		iset_s <= shift_left(resize(signed(iset_i),MEAS_I_DATAWIDTH_G),MEAS_I_DATAWIDTH_G-11)/to_signed(NO_CONTROLER_G,MEAS_I_DATAWIDTH_G); 
	end if; 
end process dividing_proc;

-- Output assignments
out_proc: process(iset_s)
begin 
	my_for: for I in 0 to NO_CONTROLER_G-1 loop 
			iset_o(I) <= iset_s;
	end loop my_for;
end process out_proc; 

kixts_o <= signed(kixts_s); 
kp_o	<= signed(kp_s);

		


	
end structural; 