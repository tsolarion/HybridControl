--==========================================================
-- Unit		:	sin_table(rtl)
-- File		:	sin_table.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
--==========================================================

--! @file sin_table.vhd
--! @author Michael Hersche
--! @date  20.11.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Synchronous sine table storage of whole period   

entity sin_table is
generic(
	OUTW_G : natural := 13
	);
port (
  clk_i          : in  std_logic;
  nreset_i		 : in std_logic; 
  addr_i         : in  std_logic_vector(4 downto 0);
  amp_i 		 : in std_logic_vector(15 downto 0); --! amplification (1 is amplitude of 10) 
  data_o         : out std_logic_vector(OUTW_G-1 downto 0));
  
end sin_table;

architecture rtl of sin_table is
type t_sin_table is array(0 to 31) of integer range 0 to 511;

signal data_s : integer := 0; 
-- -cos table with amplitude 10 and 5 fractional bits 
constant C_SIN_TABLE  : t_sin_table := (0, 3, 12,  27,  47,  71,  99, 129, 160,
   191, 221, 249, 273, 293, 308, 317, 320, 317, 308, 293,
   273, 249, 221, 191, 160, 129,  99, 71,  47,  27,  12,  3);

begin

--------------------------------------------------------------------

p_table : process(clk_i,nreset_i)
begin
  if nreset_i = '0' then 
	data_s <= 0; 
	data_o <= (others => '0'); 
  elsif(rising_edge(clk_i)) then
    data_s  <= to_integer(unsigned(amp_i)) * C_SIN_TABLE(to_integer(unsigned(addr_i)));
	data_o <= std_logic_vector(to_unsigned(data_s/8,OUTW_G)); 
  end if;
end process p_table;

end rtl;