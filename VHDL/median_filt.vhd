
--===================================================================
-- Unit:		median_filt
-- File:		median_filt.vhd
-- Purpose:		Median filtering of input signal 
-- Author:		Michael Hersche - HPE - ETH Zürich
-- Device:		Altera FPGA - Cyclone V
-- EDA syn:		Altera Quartus Prime
-- EDA sim:		Modelsim SE 10.1c
--===================================================================

---------------------------------------------------------------------
-- The component buffers a signal and computes its median over 
-- a sliding window. When a new sample_i is read, the buffer's content 
-- is shifted by one position discarding the oldest sample_i. Median calculation is 
-- done by ordering the samples in sort_buffer using advanced bubble sort 
-- algorithm. The output median_o is updated as soon as the bubble sort 
-- is finished. 
---------------------------------------------------------------------

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity median_filt is
	generic(
		NTAPS : natural := 32; 					-- Number of samples stored in buffer for median calculation, has to be odd. 
		IN_WIDTH : natural range 8 to 17 := 12
	);
	port(
			clk_i 		: in std_logic;					--! Clock
			nreset_i 	: in std_logic;					--! Reset
			din_valid_i : in std_logic;					--! Flag for valid input data
			sample_i 	: in signed(IN_WIDTH-1 downto 0);	--! input signal 
			median_o 	: out signed(IN_WIDTH-1 downto 0)	--! median value
		);
end median_filt;

architecture rtl of median_filt is
-- Define internal signals
signal din_valid_s: std_logic_vector(1 downto 0) := "00"; -- for detecting rising edge of din_valid 
signal median_s, median_next_s : signed(IN_WIDTH-1 downto 0); -- output value internally stored 

--! State machine signals 
type state_t is (IDLE, LOAD, START,SORT);
signal state_s, state_next_s : state_t := IDLE; --! state machine signals for sort
signal sort_cnt_s, sort_cnt_next_s : integer range 0 to NTAPS -1 := 0; --! index of buffer to sort  
signal new_maxcnt_s, new_maxcnt_next_s: integer range 0 to NTAPS-1 := 0; --! maximum count for sorting in the next run through 
signal maxcnt_s, maxcnt_next_s: integer range 0 to NTAPS-1 := 0; --! current maximum count for sorting, decreases every pass through the whole buffer by at least 1 

-- Define buffer
type sample_buffer_t is array (NTAPS-1 downto 0) of signed(IN_WIDTH-1 downto 0); 
signal in_buffer_s, in_buffer_next_s : sample_buffer_t := (others => (others => '0')); --! input buffer 
signal sort_buffer_s, sort_buffer_next_s : sample_buffer_t := (others => (others => '0')); --! sorted buffer 

begin
	assert (NTAPS mod 2) = 1 report "Median Filter use odd number of Taps!" severity failure; 
	
	-- Generate vector with data valid vector 
	din_valid_proc : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			din_valid_s <= (others => '0');
		elsif rising_edge(clk_i) then
			din_valid_s <= din_valid_s(0) & din_valid_i; 
		end if;
	end process;
	
	-- Main register
	reg_proc : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			median_s 	<= (others => '0');
			in_buffer_s <= (others => (others => '0'));
			sort_buffer_s<=(others => (others => '0'));
			state_s <= IDLE; 
			sort_cnt_s <= 0; 
			new_maxcnt_s <= 0 ; 
			maxcnt_s <= NTAPS -2 ; 
		elsif rising_edge(clk_i) then
			median_s 	<= median_next_s; 
			in_buffer_s	<= in_buffer_next_s; 
			sort_buffer_s<=sort_buffer_next_s; 
			state_s <= state_next_s; 
			sort_cnt_s <= sort_cnt_next_s; 
			new_maxcnt_s <= new_maxcnt_next_s; 
			maxcnt_s <= maxcnt_next_s; 
		end if;
	end process;
	
	-- Logic including statemachine and sorting 
	sort_proc : process(din_valid_s, sort_cnt_s,state_s, in_buffer_s, 
						sort_buffer_s, median_s, sample_i,new_maxcnt_s,maxcnt_s)
	begin 
		-- default assignments
		median_next_s 	<= median_s; 
		state_next_s 	<= state_s; 
		sort_cnt_next_s <= sort_cnt_s; 
		in_buffer_next_s<= in_buffer_s; 
		sort_buffer_next_s<= sort_buffer_s; 
		new_maxcnt_next_s <= new_maxcnt_s; 
		maxcnt_next_s <= maxcnt_s; 
		
		case state_s is
				when IDLE => 
					median_next_s <= sort_buffer_s((NTAPS-1)/2); 
					-- load new input data into in_buffer
					if din_valid_s = "01" then 
						state_next_s <= LOAD; 
						in_buffer_next_s(NTAPS-1 downto 1) <= in_buffer_s(NTAPS-2 downto 0); 
						in_buffer_next_s(0) <= sample_i; 
					end if; 
					
				when LOAD => 
					state_next_s <= START; 
					-- initialize sort_buffer with in_buffer value
					sort_buffer_next_s <= in_buffer_s; 
					maxcnt_next_s <= NTAPS-1;
					
				when START => 
					-- start a new pass through the sort vector (initialization) 
					-- if last pass had to sort 
					if maxcnt_s = 0 then 
						state_next_s <= IDLE; 
					else 
						state_next_s <= SORT; 
					end if; 
					
					sort_cnt_next_s <= 0; 
					new_maxcnt_next_s <= 0; 
					
				when SORT => 
					-- end of sort detection 
					if sort_cnt_s = maxcnt_s then 
						state_next_s <= START; 
						maxcnt_next_s <= new_maxcnt_s; 
					else 
						-- do one sort
						if sort_buffer_s(sort_cnt_s) > sort_buffer_s(sort_cnt_s + 1) then 
							new_maxcnt_next_s <= sort_cnt_s; 
							-- change the entries 
							sort_buffer_next_s(sort_cnt_s) <= sort_buffer_s(sort_cnt_s + 1); 
							sort_buffer_next_s(sort_cnt_s+1) <= sort_buffer_s(sort_cnt_s); 
						end if; 
						sort_cnt_next_s <= sort_cnt_s + 1; 
					end if; 
								
				when others => 
					state_next_s <= IDLE; 
		end case; 
	
	end process; 

	-- output assignment
	median_o <= median_s; 
	
end rtl;

