--==========================================================
-- Unit		:	Master_serrializeCommand(rtl)
-- File		:	Master_serrializeCommand.vhd
-- Purpose	:	
-- Author	:	Pascal Zähner - HPE - ETH Zuerich
-- Device	:	Altera FPGA - MAX10
-- EDA syn	:	Altera Quartus Prime
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
-- testbench: tb_serialize_detection.vhd 
--==========================================================



-- Works only if we assume that parallel_data does not change all the time.
-- Annotate starting pattern (4bits) and ending pattern ((3bits).

-- use standard library
library ieee;
library work;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;

entity Master_serrializeCommand is
	port(
		parallel_data_i	: in std_logic_vector(3 downto 0);  -- Input mode
		clk_i 			: in std_logic; -- main clock
		nreset_i		: in std_logic; -- Asynchronous reset
		gate1_i			: in std_logic; -- gate 1 signal from master control, not inverted
		gate2_i			: in std_logic; -- gate 2 signal from master control, not inverted
		gate1_o			: out std_logic; -- gate 1 output, inverted logic
		gate2_o			: out std_logic; -- gate 2 output, inverted logic
		serial_data_o 	: out std_logic -- serialized mode
	);
end Master_serrializeCommand ;

architecture rtl of Master_serrializeCommand  is
-- ================== CONSTANTS ==================================================
-- ================== COMPONENTS =================================================
-- =================== STATES ====================================================
-- =================== SIGNALS ===================================================
signal register_s 	: std_logic_vector(7 downto 0) := (others => '0'); -- buffer for serial data
signal counter_s	: integer range 0 to 8 := 0; -- counter to fix length of word

begin

--! @brief Register update
proc_counter : process(clk_i, nreset_i)
begin
	if nreset_i = '0' then
		counter_s <= 0;
	elsif rising_edge(clk_i) then -- update output once per 8 bits
		if counter_s = 7 then
			counter_s <= 0;	
			register_s <= "1111" & parallel_data_i; -- startword + mode
		else
			counter_s <= counter_s + 1;
		end if;
	end if;
end process;

proc_data_out : process(clk_i, nreset_i)
begin
	if nreset_i = '0' then
		serial_data_o <= '0';
		gate1_o <= '1';
		gate2_o <= '1';
	elsif rising_edge(clk_i) then
		serial_data_o <= register_s(7-counter_s);
		gate1_o <= NOT gate1_i;
		gate2_o <= NOT gate2_i;
	end if;
end process;

end rtl;
