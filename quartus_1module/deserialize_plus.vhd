library ieee;
library work;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity deserialize_plus is

	generic (
		n_bits_g : integer range 1 to 32 := 20;
		n_bits_data_g : integer range 1 to 32 := 13; 
		start_Symbol : std_logic_vector(6 downto 0) := "1110011"
		
	);
 
	port (
		reset_n			: in std_logic;
		clk            	: in std_logic;
		--sync_n          : in std_logic;
		serial_data    	: in std_logic;
		parallel_data  	: out std_logic_vector(19 downto 0); 
        start_OK        : out std_logic;
		measured_data   : out std_logic_vector(12 downto 0)
	);
 
end deserialize_plus;

architecture rtl of deserialize_plus is
	signal counter_serial	: integer range 0 to n_bits_g - 1 := 0;	-- input serialization
	signal counter_par 		: integer range 0 to n_bits_g - 1 := 0;
	signal counter_par_r 	: integer range 0 to n_bits_g - 1 := 0;
	signal counter_data 	: integer range 0 to 20 := 0;
	signal check_start 	: 	std_logic := '0';
	signal buffer_measured : std_logic_vector(12 downto 0) := (others => '0');
	signal input_buffer_s 	: std_logic_vector((2 * n_bits_g - 2) downto 0) := (others => '0');
	signal buffer_start_s	: std_logic_vector(6 downto 0):= (others => '0');
--begin
	-- shifts input buffer
--	proc_shift_input_buffer : process(clk,reset_n)
--	begin
--		if reset_n = '0' then	-- async_nhronous reset
--			input_buffer_s 	<= (others=>'0');
--			counter_serial		<= 0;
--		elsif rising_edge(clk) then
--			input_buffer_s 	<= input_buffer_s((2 * n_bits_g - 3) downto 0) & serial_data;
--			counter_serial 	<= (counter_serial + 1) mod n_bits_g;
--		end if;
--	end process;

--	--sets counter
--	proc_sync_n : process(clk,reset_n)
--	begin
--		if reset_n = '0' then	-- async_nhronous reset
--				counter_par				<= 0;
--				counter_par_r			<= 0;
--		elsif rising_edge(clk) then
--			if counter_serial = 0 and sync_n = '1' and counter_par = n_bits_g then
--				counter_par 			<= 0;
--				counter_par_r			<= counter_par; 
--			elsif counter_serial = 0 and sync_n = '1' then
--				counter_par 			<= counter_par + 1;
--				counter_par_r			<= counter_par;
--			elsif sync_n = '0' then
--				counter_par				<= counter_par_r;
--			else
--				counter_par				<= counter_par;
--				counter_par_r			<= counter_par_r;
--			end if;
--		end if;
--	end process;

begin

	proc_buff_data: process(clk,reset_n)
	begin

	  if reset_n = '0' then	-- async_nhronous reset
				counter_data <= 0;
		elsif rising_edge(clk) then
		  if check_start = '1' and counter_data < 12 then
				counter_data <=  counter_data + 1;		
				buffer_measured <= buffer_measured(11 downto 0) & serial_data;
			elsif check_start = '1' and counter_data = 12 then
				counter_data <= 0;
				buffer_measured <= buffer_measured(11 downto 0) & serial_data;
		  elsif check_start = '0' then
		    counter_data <= 0;
		    buffer_measured <= buffer_measured;
		  end if;
		else
				counter_data <= counter_data; 
				buffer_measured <= buffer_measured;
		end if;
	end process proc_buff_data;

	
	proc_start: process(clk,reset_n)
	begin
		if reset_n = '0' then	-- async_nhronous reset
				buffer_start_s 	<= (others=>'0');
				check_start <=  '0';
		elsif rising_edge(clk) and counter_data = 0 and  buffer_start_s = start_Symbol then
				buffer_start_s <= buffer_start_s;
				check_start <=  '1';
		elsif rising_edge(clk) and counter_data =  0 and  buffer_start_s /= start_Symbol then
				buffer_start_s <= buffer_start_s(5 downto 0) & serial_data;
					if (buffer_start_s (5 downto 0) & serial_data) = start_Symbol then
						check_start <=  '1';
					else 
						check_start <=  '0';
					end if;
		elsif rising_edge(clk) and counter_data >=  12 then
			buffer_start_s <= "0000000";
			check_start <=  '0';
		else 
			buffer_start_s <= buffer_start_s;
			check_start <= check_start;
		end if;
	end process proc_start;

	--outputs parallel data
--	proc_outdata : process(clk,reset_n)
--	begin
--		if reset_n = '0' then
--				parallel_data <= (others=>'0');
--		elsif rising_edge(clk) then
--			if counter_serial = 0 then
--				parallel_data <= input_buffer_s((n_bits_g - 1 + counter_par) downto counter_par);
--			end if;
--		end if;
--	end process;
	
		--outputs measured data
	proc_measdata : process(clk,reset_n)
	begin
		if reset_n = '0' then
				measured_data <= (others=>'0');
		elsif rising_edge(clk) and counter_data = 0 then
				        measured_data <= buffer_measured;
                start_OK <= check_start;
        elsif rising_edge(clk) and counter_data /= 0 then
                start_OK <= check_start; -- start_OK is used for data synchronization
		
		end if;
	end process proc_measdata;

end rtl;



