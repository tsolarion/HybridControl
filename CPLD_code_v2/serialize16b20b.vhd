
-- Works only if we assume that parallel_data_i does not change all the time.
-- Annotate starting pattern (4bits) and ending pattern ((3bits).

library ieee;
library work;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity serialize16b20b is
	generic(
		n_bits_g 		: integer range 1 to 32 := 13; 
		n_bits_total : integer range 1 to 32 := 20; 
		start_Symbol : std_logic_vector(6 downto 0) := "1110011"
	);
	
	port(
		nreset_i 			: in std_logic;
		parallel_data_i 	: in std_logic_vector(n_bits_g - 1 downto 0);	
		clk_i 				: in std_logic;
		serial_data_o 		: out std_logic
	);
end serialize16b20b;

architecture rtl of serialize16b20b is

signal register_s,register_next_s : std_logic_vector(n_bits_total - 1 downto 0) := (others => '0');
signal counter_s, counter_next_s : integer range 0 to n_bits_total := 0;


begin

proc_reg : process(clk_i, nreset_i)
begin
	if nreset_i = '0' then
		counter_s 		<= n_bits_total - 1;
		register_s 		<= (others => '0'); 
	elsif rising_edge(clk_i) then
		counter_s 		<= counter_next_s; 	
		register_s 		<= register_next_s; 		
	end if;
end process;


proc_log : process(counter_s,parallel_data_i, counter_s,register_s)
begin 
		if counter_s = 0 then
			counter_next_s <= n_bits_total - 1;
			register_next_s <= start_Symbol & parallel_data_i;
		else
			counter_next_s <= counter_s - 1;
			register_next_s <= register_s;
		end if; 
end process; 

proc_data_out : process(clk_i, nreset_i)
begin
	if nreset_i = '0' then
		serial_data_o <= '0';
	elsif rising_edge(clk_i) then
		serial_data_o <= register_s(counter_s);
	end if;
end process;

end rtl;
