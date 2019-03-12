


library ieee;
--! package for arrays 
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

PACKAGE stdvar_arr_pkg IS
	constant IN_SIZE : natural :=13; 
    type array_signed16 is array (natural range <>) of signed(15 downto 0);
	type array_signed_in is array (natural range <>) of signed(IN_SIZE-1 downto 0); 
END; 