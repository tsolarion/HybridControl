LIBRARY IEEE;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY statemachine IS
	GENERIC(
		bits_resolution : integer := 14; 
		CONV_CYCLE_G	: integer := 3; -- wait for main clock cycles (minimum 161 ns)  4 cycles / it's maybe 3... 
		WAIT_CYCLE_G	: integer := 3; 
		CONV_WAIT_CYCLE_G : integer:= 2; -- wait 2 cycles
		Total_cycle_G : integer := 20 -- total cycle count / it's maybe 20 (with 21 it is 4.76 MSps)
		);

  PORT(
			clk_i : IN STD_LOGIC;  	--clock
			nreset_i : IN STD_LOGIC; --reset
			data_clk_i: in std_logic; 
			clk_p : IN STD_LOGIC;  	--clock_p Do not use this one
			data_p_i : IN STD_LOGIC;  --input p
			data_n_i : IN STD_LOGIC;  --input n
			--read_i : IN STD_LOGIC; --read input external
			cnv_o : OUT STD_LOGIC;
			sample_o : OUT STD_LOGIC_VECTOR(12 downto 0);
			--clock_MAF : OUT STD_LOGIC;
			--raw_stream_out : OUT	STD_LOGIC_VECTOR(19 downto 0);
			sck_P_o : OUT STD_LOGIC;	
			sck_N_o : OUT STD_LOGIC
		); --output
	  
END statemachine;

ARCHITECTURE logic OF statemachine IS

	type my_states IS (IDLE, CONV, WAIT_SAMPLE, SAMPLE, WAIT_CONV); 
	signal state_s, state_next_s : my_states := CONV; 
	signal cnt_s, cnt_next_s : integer range 0 to Total_cycle_G:= 0; 
	signal raw_ADC_stream_next_s,raw_ADC_stream_s : STD_LOGIC_VECTOR(Total_cycle_G-1 DOWNTO 0) := (others => '0');
	signal sample_s, sample_next_s : STD_LOGIC_VECTOR(12 downto 0);
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
			raw_ADC_stream_s <= (others => '0'); 
			cnt_s <= 0;
			data_clk_vec_s <= (others => '0');
			sample_s <= (others => '0');
			cnt_top_s <= '0'; 
		elsif rising_edge(clk_i) then 
			state_s <= state_next_s; 
			raw_ADC_stream_s <= raw_ADC_stream_next_s; 
			cnt_s <= cnt_next_s;
			data_clk_vec_s <= data_clk_vec_s(0)& data_clk_i; 
			sample_s <= sample_next_s; 
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
	
IN_LOG: PROCESS(data_clk_vec_s, state_s,read_i,cnt_s,data_clk_i,raw_ADC_stream_s,sample_s,data_p_i,cnt_top_s)
	begin 
	-- default assignments 
	sample_next_s 	<= sample_s; 
	state_next_s	<= state_s; 
	cnt_next_s		<= cnt_s; 
	raw_ADC_stream_next_s<= raw_ADC_stream_s; 
	top_val_s		<= 0; 
	-- case 
	case state_s is 
		when IDLE => 
			if read_i = '1' then
				state_next_s <= CONV;
			else
				state_next_s <= IDLE;
			end if;
			
		when CONV => --waits 3 cycles ...
			top_val_s <= CONV_CYCLE_G-1; 
			if cnt_s >=CONV_CYCLE_G-1 and data_clk_i = '1' then -- next will be data_clk_i = '0' 
				state_next_s <= WAIT_SAMPLE;
				cnt_next_s <= 0;
			else 
				cnt_next_s <= cnt_s+ 1;
			end if;
			
		when WAIT_SAMPLE => --waits 3 until it can sample for the first time 
			top_val_s <= WAIT_CYCLE_G-1; 
			
			if cnt_s >= WAIT_CYCLE_G-1 then 
				state_next_s <= SAMPLE;
				cnt_next_s <= 1;
			else 
				cnt_next_s <= cnt_s+ 1;
			end if; 
			
		when SAMPLE => --Go into sample mode. This is 14 clock cycles...
			top_val_s <= bits_resolution-1; 
			if data_clk_vec_s = "10" then 
				if cnt_s = bits_resolution-1 then 
					cnt_next_s <= 0;
					state_next_s <= WAIT_CONV;
					raw_ADC_stream_next_s <= raw_ADC_stream_s(Total_cycle_G-2 DOWNTO 0) & data_p_i;
				else -- sample here!! 
					cnt_next_s <= cnt_s+ 1; 
					raw_ADC_stream_next_s <= raw_ADC_stream_s(Total_cycle_G-2 DOWNTO 0) & data_p_i;
				end if; 
			end if;
		when WAIT_CONV => -- Wait for 2 cycles more
			sample_next_s <= raw_ADC_stream_s(12 downto 0); 
			if cnt_s >= CONV_WAIT_CYCLE_G-1 then 
				state_next_s <= CONV;
				cnt_next_s <= 0;
			else 
				cnt_next_s <= cnt_s+ 1;
			end if;
		
	end case;
end process; 



OUT_LOG: PROCESS (data_clk_i,state_s)
	begin
		case state_s is 
			when CONV => 
				cnv_s <= '0';
				sck_s <= '1';
			when WAIT_SAMPLE =>
				cnv_s <= '0';
				sck_s <= data_clk_i;
			when SAMPLE => 
				cnv_s <= '0';
				sck_s <= data_clk_i;
			when WAIT_CONV => 
				cnv_s <= '1';
				sck_s <= '1';
			when others => 
				cnv_s <= '1';
				sck_s <= '1';
		end case;
end process;

-- signals to outputs
cnv_o <= cnv_s;
sck_P_o <= sck_s;
sck_N_o <= not(sck_s);
sample_o <= sample_s;

--raw_stream_out <= raw_ADC_stream_out_buffer;
END logic;
