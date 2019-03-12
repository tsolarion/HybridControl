
---------------------------------------------------------------------
-- Ignores the change when the value change is small
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Ignore_LSB is
	generic(
		number_of_bits : natural := 2; 	
		IN_WIDTH : natural range 8 to 17 := 13
	);
	port(
			clk_i 		: in std_logic;					--! Clock oscillator
			nreset_i 	: in std_logic;					--! Reset
			sample_i 	: in STD_LOGIC_VECTOR(IN_WIDTH-1 downto 0);	--! Signal to be averaged
			sample_out 	: out STD_LOGIC_VECTOR(IN_WIDTH-1 downto 0)	--! Average value
		);
end Ignore_LSB;

architecture rtl of Ignore_LSB is

-- Define internal signals
signal sample_i_pre : STD_LOGIC_VECTOR(IN_WIDTH-1 downto 0)	:= (others => '0'); -- Previous sample

begin
	-- Generate vector with data valid vector 
	din_valid_proc : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			sample_out <= (others => '0');
			sample_i_pre <= sample_i;
		elsif rising_edge(clk_i) then
			if sample_i(IN_WIDTH-1 downto 0) /= sample_i_pre(IN_WIDTH-1 downto 0) then
					if (signed(sample_i(IN_WIDTH-1 downto 0)) <= signed(sample_i_pre(IN_WIDTH-1 downto 0))+2**(number_of_bits)) AND (signed(sample_i(IN_WIDTH-1 downto 0)) >= signed(sample_i_pre(IN_WIDTH-1 downto 0))-2**(number_of_bits)) then
						sample_out <= sample_i_pre;
						sample_i_pre <= sample_i_pre;
					else
						sample_out <= sample_i;
						sample_i_pre <= sample_i;
					end if;
			else
				sample_out <= sample_i;
				sample_i_pre <= sample_i;
			end if;
		end if;
	end process;

end rtl;

