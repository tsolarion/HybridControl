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
		nreset_i			: in std_logic;
		clk_i            	: in std_logic;
		data_valid_i		: in std_logic; 
		serial_data_i    	: in std_logic;
		parallel_data_o  	: out std_logic_vector(19 downto 0); 
        start_OK_o        : out std_logic;
		measured_data_o   : out std_logic_vector(12 downto 0)
	);
 
end deserialize_plus;

architecture rtl of deserialize_plus is
	
	
	type receive_state is (SENSE_START, BUFFER_DATA); 
	
	signal state_s, state_next_s 				: receive_state := SENSE_START; 
	signal cnt_s, cnt_next_s 					: integer range 0 to 20 := 0;
	signal data_valid_vec_s 					: std_logic_vector(1 downto 0) := "00"; 
	signal check_start_s 						: std_logic := '0';
	signal buffer_meas_s, buffer_meas_next_s 	: std_logic_vector(12 downto 0) := (others => '0');
	signal buffer_start_s, buffer_start_next_s	: std_logic_vector(6 downto 0):= (others => '0');
	signal parallel_data_s, parallel_data_next_s: std_logic_vector(19 downto 0) := (others => '0');
	signal measured_data_s, measured_data_next_s: std_logic_vector(12 downto 0) := (others => '0');
	signal start_OK_s, start_OK_next_s			: std_logic; 

begin

	proc_buff_data: process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then	-- async_nhronous reset
			cnt_s <= 0;
			state_s <= SENSE_START; 
			data_valid_vec_s <= "00"; 
			buffer_meas_s    <= (others => '0'); 
			buffer_start_s   <= (others => '0'); 
			parallel_data_s  <= (others => '0'); 
			measured_data_s	 <= (others => '0'); 
			start_OK_s		 <= '0'; 
		elsif rising_edge(clk_i) then
			cnt_s 			<= cnt_next_s; 
			state_s 		<= state_next_s; 
			data_valid_vec_s<= data_valid_vec_s(0) & data_valid_i; 
			buffer_meas_s   <= buffer_meas_next_s ; 
			buffer_start_s  <= buffer_start_next_s; 
			parallel_data_s <= parallel_data_next_s; 
			measured_data_s <= measured_data_next_s; 
			start_OK_s		<= start_OK_next_s; 
		end if; 
	end process proc_buff_data;

	
	proc_log: process(state_s, data_valid_vec_s,cnt_s,serial_data_i,buffer_meas_s,buffer_start_s,parallel_data_s,measured_data_s) 
	begin 
	-- default assignments 
		buffer_meas_next_s <= buffer_meas_s; 
		buffer_start_next_s<= buffer_start_s; 
		cnt_next_s			<= cnt_s; 
		state_next_s		<= state_s; 
		measured_data_next_s<= measured_data_s; 
		start_OK_next_s		<= '0'; 
		case state_s is 
			when SENSE_START =>
				if buffer_start_s = start_Symbol then 
					cnt_next_s <= 0; 
					state_next_s <= BUFFER_DATA; 
					buffer_start_next_s <= (others => '0'); 
					start_OK_next_s		<= '1'; 
				elsif data_valid_vec_s = "01" then -- read new value
					buffer_start_next_s <= buffer_start_s(buffer_start_s'left -1 downto 0) & serial_data_i; 
				end if; 
					
			when BUFFER_DATA => 
				if cnt_s = n_bits_data_g then 
					measured_data_next_s <= buffer_meas_s; 
					state_next_s <= SENSE_START; 
				elsif data_valid_vec_s = "01" then -- read new value
					buffer_meas_next_s <= buffer_meas_s(buffer_meas_s'left -1 downto 0) & serial_data_i; 
					cnt_next_s <= cnt_s + 1; 
				end if; 
			when others => 
			
		end case; 
		
		if data_valid_vec_s = "01" then 
			parallel_data_next_s <= parallel_data_s(parallel_data_s'left -1 downto 0) & serial_data_i; 
		else 
			parallel_data_next_s<= parallel_data_s; 
		end if; 
		
			
	end process; 
		
		
	parallel_data_o <=parallel_data_s; 
	measured_data_o	<= measured_data_s; 
	start_OK_o		<= start_OK_s; 
		
		
		
	
		
	

end rtl;



