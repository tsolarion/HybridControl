
---------------------------------------------------------------------
-- The component buffers a signal and computes its average_o over 
-- a sliding window. When a new sample_i is read, the buffer's content 
-- is shifted by one position discarding the oldest sample_i. The block
-- updates its output in each cycle when the flag din_valid is true. 
-- Otherwise it holds its output at the previous value. 

--%%%%%%%% Send a reset signal from 0 to 1 to start the code
--%%%%%%%% This works with 4 samples only!!!
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity moving_avg is
	generic(
		NSAMPLES : natural := 4; 	
		IN_WIDTH : natural range 8 to 17 := 13
	);
	port(
			clk_i 		: in std_logic;					--! Clock oscillator
			clk_sample 	: in std_logic;					--! Sample Clock from convert signal
			nreset_i 	: in std_logic;					--! Reset
			din_valid_i : in std_logic;					--! Flag for valid input data
			sample_i 	: in STD_LOGIC_VECTOR(IN_WIDTH-1 downto 0);	--! Signal to be averaged
			average_o 	: out STD_LOGIC_VECTOR(IN_WIDTH-1 downto 0)	--! Average value
		);
end moving_avg;

architecture rtl of moving_avg is

-- Define internal signals
signal sum_s, sum_next_s : signed(IN_WIDTH+NSAMPLES-1  downto 0) := (others => '0'); -- Sum register (larger due to overflow protection 
signal din_valid_s: std_logic_vector(1 downto 0)	:= (others => '0'); -- for detecting rising edge of din_valid 
signal average_next_s : signed(IN_WIDTH-1 downto 0)	:= (others => '0');

-- Define sample_i buffer
type sample_buffer_t is array (NSAMPLES-1 downto 0) of signed(IN_WIDTH-1 downto 0);
signal sbuffer_s : sample_buffer_t :=(others => (others => '0'));

begin

	-- Generate vector with data valid vector 
	din_valid_proc : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			din_valid_s <= (others => '0');
		elsif rising_edge(clk_i) then
			din_valid_s <= '0' & din_valid_i; 
		end if;
	end process;
	
	-- Store new value in buffer, discard oldest value
	store_data : process(clk_sample, nreset_i)
	begin
		if nreset_i = '0' then
			sbuffer_s <= (others => (others => '0'));
		elsif rising_edge(clk_sample) then
			if din_valid_s = "01" then -- new data 
				sbuffer_s <= sbuffer_s(NSAMPLES-2 downto 0) & signed(sample_i);
			else
				sbuffer_s <= sbuffer_s;
			end if;
		end if;
	end process;

	-- Calculate sum_s of samples: Executed with the fast clock
	calc_reg : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			sum_s <= (others => '0');
			average_o <= (others => '0');
		elsif rising_edge(clk_i) then
			if din_valid_s = "01" then -- new data 
				sum_s <= sum_next_s; 
			else 
				sum_s <= sum_s; 
			end if; 
			average_o <= STD_LOGIC_VECTOR(average_next_s); 
		end if;
	end process;

	calc_log : process(clk_i) --Executed every time we have a change in the buffer... 
	begin
	 if  rising_edge(clk_i) then
		  -- calculate sum_s 
		  sum_next_s <= resize(sbuffer_s(0),IN_WIDTH+NSAMPLES) + resize(sbuffer_s(NSAMPLES-1),IN_WIDTH+NSAMPLES) + resize(sbuffer_s(NSAMPLES-2),IN_WIDTH+NSAMPLES)+ resize(sbuffer_s(NSAMPLES-3),IN_WIDTH+NSAMPLES);--+ resize(sbuffer_s(NSAMPLES-4),IN_WIDTH+NSAMPLES)+ resize(sbuffer_s(NSAMPLES-5),IN_WIDTH+NSAMPLES)+ resize(sbuffer_s(NSAMPLES-6),IN_WIDTH+NSAMPLES)+ resize(sbuffer_s(NSAMPLES-7),IN_WIDTH+NSAMPLES); -- Simulated with 4 samples
		  average_next_s <= resize(sum_s/(NSAMPLES), IN_WIDTH); --
		end if;
		 
	end process;


end rtl;

