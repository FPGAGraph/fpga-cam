----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    11:17:32 10/22/2012 
-- Design Name: 
-- Module Name:    HARRIS_TESSELATION - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;



library work ;
use work.generic_components.all ;
use work.camera.all ;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity HARRIS_TESSELATION is
	generic(WIDTH : positive := 640 ; HEIGHT : positive := 480; TILE_NBX : positive := 8 ; TILE_NBY : positive := 6 ; IGNORE_STRIPES : positive := 5 );
	port (
			clk : in std_logic; 
			resetn : in std_logic; 
			pixel_clock, hsync, vsync : in std_logic; 
			harris_score_in : in std_logic_vector(15 downto 0 ); 
			feature_coordx	:	out std_logic_vector((nbit(WIDTH) - 1) downto 0 );
			feature_coordy	:	out std_logic_vector((nbit(HEIGHT) - 1) downto 0 );
			end_of_block	:	out std_logic ;
			harris_score_out	: 	out std_logic_vector(15 downto 0 );
			latch_maxima	:	out std_logic 
	);
end HARRIS_TESSELATION;

architecture Behavioral of HARRIS_TESSELATION is

	signal pixel_count : std_logic_vector((nbit(WIDTH) - 1) downto 0);
	signal line_count : std_logic_vector((nbit(HEIGHT) - 1) downto 0);
	signal block_xaddress, block_xaddress_old : std_logic_vector((nbit(TILE_NBX) - 1) downto 0);
	signal block_xpos, high_score_xpos : std_logic_vector((nbit(WIDTH/TILE_NBX) - 1) downto 0);
	signal block_yaddress, block_yaddress_old : std_logic_vector((nbit(TILE_NBY) - 1) downto 0);
	signal block_ypos, high_score_ypos : std_logic_vector((nbit(HEIGHT/TILE_NBY) - 1) downto 0);
	
	
	signal ram_addr : std_logic_vector((nbit(TILE_NBX) - 1) downto 0);
	signal highest_score : std_logic_vector(15 downto 0);
	signal top_left_cornerx	:	std_logic_vector((nbit(WIDTH) - 1) downto 0);
	signal top_left_cornery : std_logic_vector((nbit(HEIGHT) - 1) downto 0);
	signal ram_in, ram_out : std_logic_vector(31 downto 0);
	signal new_high_score : std_logic ;
	signal hsync_old, hsync_fe, hsync_re : std_logic ;
begin

process(clk, resetn)
begin
	if resetn ='0' then
		hsync_old <= '0' ;
		block_xaddress_old <= (others => '0') ;
	elsif clk'event and clk = '1' then
		hsync_old <= hsync ;
		block_xaddress_old <= block_xaddress ;
	end if ;
end process ;
hsync_fe <= hsync_old and (not hsync) ;
hsync_re <= (NOT hsync_old) and hsync ;

ram_in <= (std_logic_vector(to_unsigned(0, 32 - (1 + nbit(WIDTH/TILE_NBX) + nbit(WIDTH/TILE_NBY) + 16)))& '1' & block_ypos & block_xpos & harris_score_in) when block_xaddress_old = block_xaddress else
			 (others => '0');

highest_score <= ram_out(15 downto 0) ;
high_score_xpos <= ram_out(((nbit(WIDTH/TILE_NBX) + 16) - 1) downto 16);
high_score_ypos <= ram_out(((nbit(WIDTH/TILE_NBY) + (nbit(WIDTH/TILE_NBX) + 16)) - 1) downto (nbit(WIDTH/TILE_NBX) + 16));


harris_score_out <= harris_score_in when signed(harris_score_in) > signed(highest_score) else	
						  highest_score ;
feature_coordx <= high_score_xpos + top_left_cornerx ;
feature_coordy <= high_score_ypos + top_left_cornery ;


new_high_score <= '1' when block_xaddress_old /= block_xaddress and block_ypos = 0	 else
						'0' when ((unsigned(pixel_count) < IGNORE_STRIPES) OR (unsigned(line_count) < IGNORE_STRIPES)) else
						'1' when signed(harris_score_in) > signed(highest_score) else				
						'0';
						
latch_maxima <= new_high_score ;

score_ram : dpram_NxN
	generic map(SIZE => TILE_NBX , NBIT => 32 , ADDR_WIDTH => nbit(TILE_NBX))
	port map(
 		clk => clk,  
 		we => new_high_score,
 		di => ram_in,
		a	=> ram_addr, 
 		dpra => (others => '0'),
		spo => ram_out,
		dpo => open 		
	); 
ram_addr <=  block_xaddress when block_xaddress < TILE_NBX else
				  (others => '0') ;

end_of_block <= '1' when block_xpos = (WIDTH/TILE_NBX - 1) and block_ypos = (HEIGHT/TILE_NBY - 1) else
					 '0' ;

pixel_counter0 : pixel_counter
		generic map(MAX => WIDTH)
		port map(
			clk => clk,
			resetn => resetn,
			pixel_clock => pixel_clock, hsync => hsync,
			pixel_count => pixel_count
			);
	
		process(clk, resetn)
		begin
			if resetn = '0' then
				block_xaddress <= (others => '0') ;
				block_xpos <= (others => '0') ;
				top_left_cornerx <= (others => '0') ;
			elsif clk'event and clk = '1' then
				if hsync = '1' then
					block_xaddress <= (others => '0') ;
					top_left_cornerx <= (others => '0') ;
					block_xpos <= (others => '0') ;
				elsif pixel_clock = '1'  then
						if block_xpos = (WIDTH/TILE_NBX - 1) then
							block_xaddress <= block_xaddress  + 1  ;
							top_left_cornerx <= pixel_count ;
							block_xpos <= (others => '0');
						else
							block_xpos <= block_xpos + 1 ;
						end if;
				end if ;
			end if ;
		end process ;

	
	line_counter0: line_counter 
		generic map(MAX => HEIGHT)
		port map(
			clk => clk, 
			resetn => resetn, 
			hsync => hsync, vsync => vsync,
			line_count => line_count );
	
	
		process(clk, resetn)
		begin
			if resetn = '0' then
				block_yaddress <= (others => '0') ;
				block_ypos <= (others => '0') ;
				top_left_cornery <= (others => '0') ;
			elsif clk'event and clk = '1' then
				if vsync = '1' then
					block_yaddress <= (others => '0') ;
					top_left_cornery <= (others => '0') ;
					block_ypos <= (others => '0') ;
				elsif hsync_re = '1' then
					if  block_ypos = (HEIGHT/TILE_NBY - 1) then
						block_yaddress <= block_yaddress  + 1  ;
						top_left_cornery <= line_count ;
						block_ypos <= (others => '0');
					else
						block_ypos <= block_ypos + 1;
					end if ;
				end if ;
			end if ;
		end process ;	
		
		

end Behavioral;

