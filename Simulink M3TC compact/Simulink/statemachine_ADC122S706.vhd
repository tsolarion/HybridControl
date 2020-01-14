LIBRARY IEEE;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY statemachine_ADC122S706 IS
	GENERIC(
		bits_resolution : integer := 12; 
		CONV_CYCLE_G	: integer := 2; -- wait for main clock cycles (minimum 161 ns)  4 cycles / it's maybe 3... 
		WAIT_CYCLE_G	: integer := 8; 
		CONV_WAIT_CYCLE_G : integer:= 2; -- wait 2 cycles
		Total_cycle_G : integer := 20 -- total cycle count / it's maybe 20 (with 21 it is 4.76 MSps)
		);

  PORT(
			clk_i 		: IN STD_LOGIC;  		--clock from PLL representing the SPI CLK
			data_clk_i: in std_logic;
			data_V1_i 	: IN STD_LOGIC;  	--input V1
			data_V2_i 	: IN STD_LOGIC;  	--input V2
			sample_V1_o : OUT STD_LOGIC_VECTOR(11 downto 0);
			sample_V2_o : OUT STD_LOGIC_VECTOR(11 downto 0);
			CS_out 		: OUT STD_LOGIC := '0';
			nreset_i 		: IN STD_LOGIC;
			SPI_CLK_out : OUT STD_LOGIC
		); --output
	  
END statemachine_ADC122S706;


ARCHITECTURE logic OF statemachine_ADC122S706 IS

	type my_states IS (IDLE, CONV, SAMPLE ,ACQ); 
	signal state_s, state_next_s : my_states := CONV; 
	signal cnt_s, cnt_next_s : integer range 0 to Total_cycle_G:= 0; 
	signal raw_ADC_stream_V1_next_s,raw_ADC_stream_V1_s : STD_LOGIC_VECTOR(Total_cycle_G-1 DOWNTO 0) := (others => '0');
	signal raw_ADC_stream_V2_next_s,raw_ADC_stream_V2_s : STD_LOGIC_VECTOR(Total_cycle_G-1 DOWNTO 0) := (others => '0');
	signal sample_V1_s, sample_V1_next_s : STD_LOGIC_VECTOR(11 downto 0);
	signal sample_V2_s, sample_V2_next_s : STD_LOGIC_VECTOR(11 downto 0);
	signal data_clk_vec_s : std_logic_vector(1 downto 0); -- vector storing last two data_clk_i values 

	SIGNAL cnv_s : STD_LOGIC := '0'; 
	signal sck_s : STD_LOGIC := '1'; -- sck_s signal
	-- definitions for testing of read_i and nreset
	signal read_i : STD_LOGIC := '1';
	
	signal top_val_s : integer := 0; 
	signal cnt_top_s, cnt_top_next_s : std_logic := '0'; 
	

BEGIN
REG: PROCESS(clk_i, nreset_i)
	begin 
		if nreset_i= '0' then 
			state_s <= IDLE;
			raw_ADC_stream_V1_s <= (others => '0'); 
			cnt_s <= 0;
			data_clk_vec_s <= (others => '0');
			sample_V1_s <= (others => '0');
			sample_V2_s <= (others => '0');
			cnt_top_s <= '0'; 
		elsif rising_edge(clk_i) then 
			state_s <= state_next_s; 
			raw_ADC_stream_V1_s <= raw_ADC_stream_V1_next_s; 
			raw_ADC_stream_V2_s <= raw_ADC_stream_V2_next_s; 
			cnt_s <= cnt_next_s;
			data_clk_vec_s <= data_clk_vec_s(0)& data_clk_i; 
			sample_V1_s <= sample_V1_next_s;
			sample_V2_s <= sample_V2_next_s;			
			cnt_top_s <= cnt_top_next_s; 
		end if; 
	end process; 
	
CNT_TOPVAL_PROC: process(cnt_s, top_val_s)
begin 
	if cnt_s >= top_val_s-1 then 
		cnt_top_next_s <= '1'; 
	else	
		cnt_top_next_s <= '0'; 
	end if; 

end process; 
	
IN_LOG: PROCESS(data_clk_vec_s, state_s,read_i,cnt_s,data_clk_i,raw_ADC_stream_V1_s,sample_V1_s,cnt_top_s,data_V1_i,data_V2_i,raw_ADC_stream_V2_s,sample_V2_s)
	begin 
	-- default assignments 
	sample_V1_next_s 	<= sample_V1_s; 
	sample_V2_next_s 	<= sample_V2_s; 
	state_next_s	<= state_s; 
	cnt_next_s		<= cnt_s; 
	raw_ADC_stream_V1_next_s<= raw_ADC_stream_V1_s; 
	raw_ADC_stream_V2_next_s<= raw_ADC_stream_V2_s; 
	top_val_s		<= 0; 
	-- case 
	case state_s is 
		when IDLE => 
			if read_i = '1' then
				state_next_s <= CONV;
			else
				state_next_s <= IDLE;
			end if;
		
		when CONV => -- 1 cycles ...
			top_val_s <= CONV_CYCLE_G-1; 
			sample_V1_next_s <= raw_ADC_stream_V1_s(11 downto 0);
			sample_V2_next_s <= raw_ADC_stream_V2_s(11 downto 0);
			if cnt_s >=CONV_CYCLE_G-1 and data_clk_vec_s = "01" then -- next will be data_clk_i = '0' 
				state_next_s <= ACQ;
				cnt_next_s <= 0;
			else 
				cnt_next_s <= cnt_s+ 1;
			end if;		
		
		when ACQ => -- 1 cycles ...
			top_val_s <= WAIT_CYCLE_G-1; 
			if cnt_s >=WAIT_CYCLE_G-1 then -- next will be data_clk_i = '0' 
				state_next_s <= SAMPLE;
				cnt_next_s <= 0;
			else 
				cnt_next_s <= cnt_s+ 1;
			end if;	
		

		when SAMPLE => --Go into sample mode. This is 14 clock cycles...
			top_val_s <= bits_resolution-1; 
			if data_clk_vec_s = "01" then 
				if cnt_s = bits_resolution-1 then 
					cnt_next_s <= 0;
					state_next_s <= CONV;
					raw_ADC_stream_V1_next_s <= raw_ADC_stream_V1_s(Total_cycle_G-2 DOWNTO 0) & data_V1_i;
					raw_ADC_stream_V2_next_s <= raw_ADC_stream_V2_s(Total_cycle_G-2 DOWNTO 0) & data_V2_i;
					-- add V2
				else -- sample here!! 
					cnt_next_s <= cnt_s+ 1; 
					raw_ADC_stream_V1_next_s <= raw_ADC_stream_V1_s(Total_cycle_G-2 DOWNTO 0) & data_V1_i;
					raw_ADC_stream_V2_next_s <= raw_ADC_stream_V2_s(Total_cycle_G-2 DOWNTO 0) & data_V2_i;
					-- add V2
				end if; 
			end if;
		
		
	end case;
end process; 

OUT_LOG: PROCESS (data_clk_i,state_s)
	begin
		case state_s is 
			when CONV => 
				cnv_s <= '1';
				sck_s <= data_clk_i;
			when SAMPLE => 
				cnv_s <= '0';
				sck_s <= data_clk_i;
			when ACQ => 
				cnv_s <= '0';
				sck_s <= data_clk_i;
			when others => 
				cnv_s <= '1';
				sck_s <= data_clk_i;
		end case;
end process;

-- signals to outputs
CS_out <= cnv_s;
SPI_CLK_out <= sck_s;
sample_V1_o <= sample_V1_s;
sample_V2_o <= sample_V2_s;
-- add V2

--raw_stream_out <= raw_ADC_stream_V1_out_buffer;
END logic;