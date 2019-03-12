--==========================================================
-- Unit		:	signal_generator(rtl)
-- File		:	signal_generator.vhd
-- Purpose	:	
-- Author	:	Michael Hersche - HPE - ETH Zuerich
-- Device	:	Altera FPGA - Cyclone V
-- EDA syn	:	Altera Quartus II
-- EDA sim	:	Modelsim SE 10.1c
-- misc		:	--
-- depdcy	:	
--==========================================================

--! @file signal_generator.vhd
--! @author Michael Hersche
--! @date  22.11.2018
--! @version 1.0

-- use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;
--! Use numeric elements
use ieee.numeric_std.all;


--! @brief Signal generator
--! @details Select signal shifted cosine or ramp 
--! @details Determine slope with fcw_i 
--! @details Setting of signal period: 
--! @details Base counter period 	Tb = MAX_DIV_CNT_G / fclk
--! @details Signal period 			Ts = (Tb * 2^CNT_BIT_G) / fcw_i  
entity signal_generator is
generic(
	OUTW_G 			: natural := 13; 
	MAX_DIV_CNT_G	: natural := 10000000; -- number of clocks for help counter 
	CNT_BIT_G		: natural := 8
	);
port (
  clk_i         : in  std_logic;
  nreset_i		: in std_logic; 
  enable_i		: in std_logic; 
  sig_select_i	: in std_logic; --! signal selection '0': sine, '1': ramp , can only be changed when enable_i = 0
  fcw_i 		: in std_logic_vector(7 downto 0); --! set frequency/period of signal 
  amp_i 		: in std_logic_vector(15 downto 0); --! amplification (1 is amplitude of 10) 
  sig_o			: out std_logic_vector(OUTW_G-1 downto 0)
 ); 
end signal_generator;

architecture rtl of signal_generator is
-- ================== CONSTANTS ==================================================

-- =================== STATES ====================================================


-- =================== SIGNALS ===================================================
signal div_cnt_s, div_cnt_next_s: integer range 0 to MAX_DIV_CNT_G-1 := 0; 
signal cnt_s, cnt_next_s		: unsigned(CNT_BIT_G-1 downto 0) :=  (others => '0'); 

signal addr_s, addr_next_s 		: std_logic_vector(CNT_BIT_G-1 downto 0) := (others => '0'); 

signal sig_select_s, sig_select_next_s : std_logic := '0'; 

signal  data_sin_s			: std_logic_vector(OUTW_G-1 downto 0):= (others => '0');
signal  data_ramp_s			: std_logic_vector(OUTW_G-1 downto 0):= (others => '0');
signal data_s,data_next_s 	: std_logic_vector(OUTW_G-1 downto 0):= (others => '0');

-- ================== COMPONENTS =================================================
component sin_table is
generic(
	OUTW_G : natural := 13
	);
port (
  clk_i          : in  std_logic;
  nreset_i		 : in std_logic; 
  addr_i         : in  std_logic_vector(4 downto 0);
  amp_i 		 : in std_logic_vector(15 downto 0); --! amplification (1 is amplitude of 10) 
  data_o         : out std_logic_vector(OUTW_G-1 downto 0));
end component;

component ramp_table is
generic(
	OUTW_G : natural := 13
	);
port (
  clk_i          : in  std_logic;
  nreset_i		 : in std_logic; 
  addr_i         : in  std_logic_vector(4 downto 0);
  amp_i 		 : in std_logic_vector(15 downto 0); --! amplification (1 is amplitude of 10) 
  data_o         : out std_logic_vector(OUTW_G-1 downto 0));
end component;


begin

--------------------------------------------------------------------
reg_proc : process(clk_i,nreset_i)
begin
	if nreset_i = '0' then 
		div_cnt_s	<= 0; 
		cnt_s 		<= (others => '0'); 
		addr_s		<= (others => '0'); 
		data_s		<= (others => '0');
		sig_select_s<= '0'; 
	elsif(rising_edge(clk_i)) then
		div_cnt_s 	<= div_cnt_next_s;
		cnt_s 		<= cnt_next_s; 
		addr_s 		<= addr_next_s; 
		data_s		<= data_next_s;
		sig_select_s<= sig_select_next_s; 
	end if;
end process;


log_proc: process(div_cnt_s,enable_i,fcw_i,cnt_s,sig_select_i,sig_select_s)
begin 
	
	-- default assignments to suppresss latches 
	cnt_next_s <= cnt_s; 
	sig_select_next_s <= sig_select_s;

	-- update sig_select_s only if enable is off (before signal generation) 
	if enable_i = '0' then 
		sig_select_next_s <= sig_select_i; 
	end if; 
		
	-- always increase help counter 
	if div_cnt_s = MAX_DIV_CNT_G -1 then 
		div_cnt_next_s <= 0; 
	else 
		div_cnt_next_s <= div_cnt_s + 1;
	end if; 
	-- address counter 
	if div_cnt_s = 1 and enable_i = '1' then -- new "edge" 
		cnt_next_s <= cnt_s + (unsigned(fcw_i)); 
	elsif enable_i = '0' then 
		cnt_next_s <= (others => '0');
	end if; 
	-- address generation 
	addr_next_s <= std_logic_vector(cnt_s);
	
	-- signal select
	if sig_select_s = '0' then 
		data_next_s <= data_sin_s; 
	else 
		data_next_s <= data_ramp_s; 
	end if; 

end process; 


inst_sin_table: sin_table 
generic map (OUTW_G => OUTW_G)
port map (clk_i 	=> clk_i,     
         nreset_i	=> nreset_i, 
         addr_i    	=> addr_s(CNT_BIT_G-1 downto CNT_BIT_G-5),  -- read most significant bits 
		 amp_i		=> amp_i, 
         data_o     => data_sin_s
		 ); 
		 

inst_ramp_table: ramp_table
generic map (OUTW_G => OUTW_G)
port map (clk_i 	=> clk_i,     
         nreset_i	=> nreset_i, 
         addr_i    	=> addr_s(CNT_BIT_G-1 downto CNT_BIT_G-5),  -- read most significant bits 
		 amp_i		=> amp_i, 
         data_o     => data_ramp_s 
		 ); 

sig_o <= data_s; 


end rtl;