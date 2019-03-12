--==========================================================
-- Unit		:	signed_limiter(rtl)
-- File		:	signed_limiter.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	--
--==========================================================

--! @file signed_limiter.vhd
--! @author Michael Hersche
--! @date  22.05.2018

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

--! @brief reduces the number of bits by limiting input singal 
entity signed_limiter is 
	generic( 	IN_BITS_G 	: natural := 16;  --! Number of input bits
				OUT_BITS_G	: natural := 16 --! Number of output bits 
			);		
	port( 	clk_i			: in std_logic; --! Main clock 
			nreset_i 		: in std_logic; --! Asynchronous reset 
			data_i			: in signed(IN_BITS_G-1 downto 0); --! Input value  
			data_o			: out signed(OUT_BITS_G-1 downto 0) --! Input value  
			);
			
end signed_limiter;


architecture structural of signed_limiter is
-- ================== CONSTANTS ==================================================		
	
constant MAX_VAL_C : signed(IN_BITS_G-1 downto 0) := to_signed(2**(OUT_BITS_G-1)-1,IN_BITS_G);
constant MIN_VAL_C : signed(IN_BITS_G-1 downto 0) := to_signed(-2**(OUT_BITS_G-1),IN_BITS_G);
-- ================== COMPONENTS =================================================

-- =================== STATES ====================================================
type overfl_superv is (IDLE,OVERFLOW, UNDERFLOW); 	

-- =================== SIGNALS ===================================================
signal lim_state_s, lim_state_next_s: overfl_superv := IDLE; 
signal d_out_s,d_out_next_s : signed(OUT_BITS_G-1 downto 0) := (others => '0'); 
signal data_s : signed(IN_BITS_G-1 downto 0) := (others => '0'); 

begin	
	
	assert (IN_BITS_G >= OUT_BITS_G ) report "Limiter error: IN_BITS_G < OUT_BITS_G" severity failure;	
		

	--! @brief Input registers 
	--! @details Asynchronous reset nreset_i
	input_reg : process(clk_i,nreset_i)
	begin
		if nreset_i = '0' then
			lim_state_s <= IDLE;
			d_out_s <= (others => '0'); 
			data_s <= (others => '0'); 
		elsif rising_edge(clk_i) then
			lim_state_s <= lim_state_next_s; 
			d_out_s <= d_out_next_s; 
			data_s <= data_i; 
		end if; 
	end process; 
			
	
	LIMITER_LOGIC: process(data_i,lim_state_s)
		begin
			lim_state_next_s <= lim_state_s; 
			
			if data_i < MIN_VAL_C then 
				lim_state_next_s <= UNDERFLOW; 
			elsif data_i > MAX_VAL_C then 
				lim_state_next_s <= OVERFLOW; 
			else 
				lim_state_next_s <= IDLE; 
			end if; 
			
		end process; 
		
	OUTPUT_LOGIC_PROC: process(data_s,d_out_s,lim_state_s)
		begin 
			d_out_next_s <= d_out_s; 
			case lim_state_s is 
				when IDLE => 
					d_out_next_s <= resize(data_s,OUT_BITS_G);
				when UNDERFLOW =>
					d_out_next_s <= resize(MIN_VAL_C,OUT_BITS_G);
				when OVERFLOW => 
					d_out_next_s <= resize(MAX_VAL_C,OUT_BITS_G);
				when others => 
					d_out_next_s <= (others => '0'); 
			end case; 


		end process; 

data_o <= d_out_s; 

end structural; 