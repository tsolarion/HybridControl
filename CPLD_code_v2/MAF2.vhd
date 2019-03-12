------------------------------------------------------------------------
--Moving average
--RST and softreset can be 0
--Valid data needs to be 1 otherwise the average function stops
-- this works for a filter with 2 elements but could work for other powers of 2.. 
------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MAF2 is
	generic(
		INW 		: natural range 1 to 64 := 13; 		 --input width
		LEN			: natural range 1 to 2**20 := 2;		--filter length
		LOG2LEN		: natural range 1 to 20	:= 2			-- choosing a power of two greatly simplifies the adder tree generation
	);

	port( 
		CLK_CI			: in std_logic; 								--clock 
		DATAVALID_SI	: in std_logic;								--filter is only updated on data valid
		RST_RBI			: in std_logic; 								--asynchronous reset, active
		SOFTRST_SBI		: in std_logic; 								--synchronous reset
		DATA_DI			: in std_logic_vector(12 downto 0); -- Input Data
		DATA_DO			: out std_logic_vector(12 downto 0)	-- Output Data
	);
end MAF2;

architecture structural of MAF2 is
	signal OldData_D 				: signed(INW-1 downto 0);
	signal Reg_DN 			: signed(LEN*INW -1  downto 0):= (others =>'0');
 	signal Reg_DP 			: signed(LEN*INW -1  downto 0):= (others =>'0');-- shift register
	signal Sum_DN 			: signed(INW+LOG2LEN-1 downto 0):= (others =>'0');
	signal Sum_DP			: signed(INW+LOG2LEN-1 downto 0):= (others =>'0');

begin --structural
	
	assert(2**LOG2LEN >= LEN) report "LOG2LEN must be ceil(log2(LEN))" severity error;
	
	-- make shift register connections
	shift_gen: for i in 1 to LEN -1 generate
		Reg_DN((i+1)*INW -1 downto i*INW) <= Reg_DP(i*INW -1 downto (i-1)*INW);
	end generate; --shift_gen
	
	--last sample to be discarded
	OldData_D <= Reg_DP(LEN*INW - 1 downto (LEN-1)*INW); 
	
	-- input connections
	Reg_DN(INW-1 downto 0) <= signed(DATA_DI);
	
	--output connection
	DATA_DO <= std_logic_vector(SHIFT_right(Sum_DP,1));

	-- summing signals
	Sum_DN <= Sum_DP + signed(DATA_DI) - OldData_D;
	
	--registers
	p_memzing : process (CLK_CI)--, RST_RBI)
	begin
		if RST_RBI= '1' then -- asynchronous
			Reg_DP <= (others =>'0');
			Sum_DP <= (others =>'0');
		elsif CLK_CI'event and CLK_CI= '1' then
			if SOFTRST_SBI = '1' then -- synchronous reset
				Reg_DP <= (others =>'0');
				Sum_DP <= (others =>'0');
			elsif DATAVALID_SI = '1' then
				Reg_DP <= Reg_DN;
				Sum_DP <= Sum_DN;
			else
				--keep the registers as they are ie no update
			end if;
		end if;
	end process p_memzing;
	
end structural; -- of MAF2
