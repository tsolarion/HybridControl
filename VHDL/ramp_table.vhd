--==========================================================
-- Unit		:	ramp_table(rtl)
-- File		:	ramp_table.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
--==========================================================

--! @file ramp_table.vhd
--! @author Michael Hersche
--! @date  20.11.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Synchronous ramp table storage of whole period   

entity ramp_table is
generic(
	OUTW_G : natural := 13
	);
port (
  clk_i          : in  std_logic;
  nreset_i		 : in std_logic; 
  addr_i         : in  std_logic_vector(4 downto 0);
  amp_i 		 : in std_logic_vector(15 downto 0); --! amplification (1 is amplitude of 10) 
  data_o         : out std_logic_vector(OUTW_G-1 downto 0));
end ramp_table;

architecture rtl of ramp_table is
type t_ramp_table is array(0 to 31) of integer;

signal data_s : integer := 0; 
-- -cos table with amplitude 10 and 5 fractional bits 
constant C_RAMP_TABLE  : t_ramp_table := (0, 20, 40, 60, 80, 100, 120,
		140, 160, 180, 200, 220, 240, 260, 280, 300, 320, 300, 280, 260, 
		240, 220, 200, 180, 160, 140, 120, 100, 80, 60, 40, 20);

begin

--------------------------------------------------------------------

p_table : process(clk_i,nreset_i)
begin
  if nreset_i = '0' then 
	data_s <= 0; 
	data_o <= (others => '0'); 
  elsif(rising_edge(clk_i)) then
    data_s  <= to_integer(unsigned(amp_i)) * C_RAMP_TABLE(to_integer(unsigned(addr_i)));
	data_o <= std_logic_vector(to_unsigned(data_s/8,OUTW_G)); 
  end if;
end process p_table;

end rtl;