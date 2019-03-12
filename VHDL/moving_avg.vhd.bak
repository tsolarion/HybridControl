
--===================================================================
-- Unit:		moving_avg
-- File:		moving_avg.vhd
-- Purpose:		Moving average_o of input signal
-- Author:		Evangelos Kalkounis - HPE - ETH Zürich
-- Device:		Altera FPGA - Cyclone V
-- EDA syn:		Altera Quartus Prime
-- EDA sim:		Modelsim SE 10.1c
--===================================================================

---------------------------------------------------------------------
-- The component buffers a signal and computes its average_o over 
-- a sliding window. When a new sample_i is read, the buffer's content 
-- is shifted by one position discarding the oldest sample_i. The block
-- updates its output in each cycle when the flag din_valid is true. 
-- Otherwise it holds its output at the previous value. 
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity moving_avg is
	generic(
		NSAMPLES : natural := 32; 					-- Number of samples from 2 MHz to 60 KHz: 2e6/60e3 =~  34
		IN_WIDTH : natural range 8 to 17 := 12; 
		MAX_DELTA_G: natural := 100; 				--! Limitation of current change for storing in buffer   
		CORR_DELTA_G: natural := 0					--! If change was too high, last buffer value goes into "direction" with CORR_DELTA_G
	);
	port(
			clk_i 		: in std_logic;					--! Clock
			nreset_i 	: in std_logic;					--! Reset
			nsoftreset_i: in std_logic; 				--! soft reset 
			din_valid_i : in std_logic;					--! Flag for valid input data
			sample_i 	: in signed(IN_WIDTH-1 downto 0);	--! Signal to be averaged
			average_o 	: out signed(IN_WIDTH-1 downto 0)	--! Average value
		);
end moving_avg;

architecture rtl of moving_avg is

-- Define internal signals
signal old_sum_s,sum_s, sum_next_s : signed(IN_WIDTH+NSAMPLES-1  downto 0) := (others => '0'); -- Sum register (larger due to overflow protection 
signal din_valid_s: std_logic_vector(1 downto 0) := "00"; -- for detecting rising edge of din_valid 
signal average_s, average_next_s : signed(IN_WIDTH-1 downto 0); 

signal sample_s, sample_next_s: signed(IN_WIDTH-1 downto 0) := (others => '0'); 

-- Define sample_i buffer
type sample_buffer_t is array (NSAMPLES downto 0) of signed(IN_WIDTH-1 downto 0);
signal sbuffer_s : sample_buffer_t;
signal sharp_inc : std_logic := '0'; 
signal sharp_dec : std_logic := '0'; 



begin

	-- Limitation process
	limit_proc : process(sample_i,average_s)
	begin 
		if (average_s - sample_i) > to_signed(MAX_DELTA_G,IN_WIDTH) then -- too sharp decrease 
			sample_next_s <= average_s - to_signed(CORR_DELTA_G, IN_WIDTH); 
			sharp_dec <= '1'; 
		elsif  (sample_i - average_s) > to_signed(MAX_DELTA_G,IN_WIDTH) then -- too sharp increase
			sample_next_s <= average_s + to_signed(CORR_DELTA_G, IN_WIDTH); 
			sharp_inc <= '1'; 
		else 
			sample_next_s <= sample_i; 
			sharp_inc <='0'; 
			sharp_dec <= '0'; 
		end if; 
	end process; 

	-- Generate vector with data valid vector 
	din_valid_proc : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			din_valid_s <= (others => '0');
		elsif rising_edge(clk_i) then
			din_valid_s <= din_valid_s(0) & din_valid_i; 
		end if;
	end process;

	-- Store new value in buffer, discard oldest value
	store_data : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			sbuffer_s <= (others => (others => '0'));
			sum_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				sbuffer_s <= (others => (others => '0'));
				sum_s <= (others => '0'); 
			elsif din_valid_s = "01" then -- new data 
				sbuffer_s <= sbuffer_s(NSAMPLES-1 downto 0) & sample_s;
				sum_s <= old_sum_s; 
			else
				sbuffer_s <= sbuffer_s;
				sum_s <= sum_s; 				
			end if;
		end if;
	end process;

	-- Calculate sum_s of samples
	calc_reg : process(clk_i, nreset_i)
	begin
		if nreset_i = '0' then
			old_sum_s <= (others => '0');
			average_s <= (others => '0');
			sample_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			if nsoftreset_i = '0' then 
				old_sum_s <= (others => '0');
				average_s <= (others => '0');
				sample_s <= (others => '0'); 
			else 
				sample_s <= sample_next_s; 
				old_sum_s <= sum_next_s; 
				average_s <= average_next_s; 
			end if; 
		end if;
	end process;


	calc_log : process(sbuffer_s,sum_s,old_sum_s)
	begin 
		-- calculate sum_s 
		sum_next_s <= sum_s + resize(sbuffer_s(0),IN_WIDTH+NSAMPLES) - resize(sbuffer_s(NSAMPLES),IN_WIDTH+NSAMPLES);
		-- Calculate average_s
		average_next_s <= resize(old_sum_s/NSAMPLES, IN_WIDTH);
	end process;

	-- output annotation 
	average_o <= average_s; 
end rtl;

