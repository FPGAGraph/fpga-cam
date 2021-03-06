----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    10:25:52 03/03/2012 
-- Design Name: 
-- Module Name:    sobel3x3 - Behavioral 
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
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library WORK ;
USE WORK.CAMERA.ALL ;
USE WORK.GENERIC_COMPONENTS.ALL ;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity sobel3x3 is
generic(WIDTH: natural := 640;
		  HEIGHT: natural := 480);
port(
 		clk : in std_logic; 
 		resetn : in std_logic; 
 		pixel_clock, hsync, vsync : in std_logic; 
 		pixel_clock_out, hsync_out, vsync_out : out std_logic; 
 		pixel_data_in : in std_logic_vector(7 downto 0 ); 
 		pixel_data_out : out std_logic_vector(7 downto 0 );
		x_grad	:	out signed(7 downto 0);
		y_grad	:	out signed(7 downto 0)
);
end sobel3x3;



architecture RTL of sobel3x3 is
	
	signal pxclk_from_conv1, hsync_from_conv1, vsync_from_conv1 : std_logic ;
	signal pxclk_from_conv2, hsync_from_conv2, vsync_from_conv2 : std_logic ;
	signal new_conv1, new_conv2, new_conv : std_logic;
	signal busy1, busy2, busy : std_logic;
	signal pixel_from_conv1, pixel_from_conv2, pixel_from_conv : std_logic_vector(7 downto 0);
	signal raw_from_conv1, raw_from_conv2, sobel_response : signed(15 downto 0);
	signal block3x3_sig : matNM(0 to 2, 0 to 2) ;
	signal new_block, pxclk_state : std_logic ;
	signal pixel_clock_old, hsync_old, new_conv_old : std_logic ;
--	for block0 : block3X3 use entity block3X3(RTL) ;
--	for conv3x3_0 : conv3x3 use entity conv3x3(RTL) ;
--	for conv3x3_1 : conv3x3 use entity conv3x3(RTL) ;
begin

		block0:  block3X3 
		generic map(WIDTH =>  WIDTH, HEIGHT => HEIGHT)
		port map(
			clk => clk ,
			resetn => resetn , 
			pixel_clock => pixel_clock , hsync => hsync , vsync => vsync,
			pixel_data_in => pixel_data_in ,
			new_block => new_block,
			block_out => block3x3_sig);
		
		
		conv3x3_0 :  conv3x3 
		generic map(KERNEL =>((1, 2, 1),(0, 0, 0),(-1, -2, -1)),
		  NON_ZERO	=> ((0, 0), (0, 1), (0, 2), (2, 0), (2, 1), (2, 2), (3, 3), (3, 3), (3, 3) ), -- (3, 3) indicate end  of non zero values
		  IS_POWER_OF_TWO => 0
		  )
		port map(
				clk => clk,
				resetn => resetn, 
				new_block => new_block,
				block3x3 => block3x3_sig,
				new_conv => new_conv1,
				busy => busy1,
				abs_res => pixel_from_conv1,
				raw_res => raw_from_conv1
		);
		
		conv3x3_1 :  conv3x3 
		generic map(KERNEL =>((1, 0, -1),(2, 0, -2),(1, 0, -1)),
		  NON_ZERO	=> ((0, 0), (0, 2), (1, 0), (1, 2), (2, 0), (2, 2), (3, 3), (3, 3), (3, 3) ), -- (3, 3) indicate end  of non zero values
		  IS_POWER_OF_TWO => 0
		  )
		port map(
				clk => clk,
				resetn => resetn, 
				new_block => new_block,
				block3x3 => block3x3_sig,
				new_conv => new_conv2,
				busy => busy2,
				abs_res => pixel_from_conv2,
				raw_res => raw_from_conv2
		);
		
	
		delay_sync: generic_delay
		generic map( WIDTH =>  2 , DELAY => 4)
		port map(
			clk => clk, resetn => resetn ,
			input(0) => hsync ,
			input(1) => vsync ,
			output(0) => hsync_out ,
			output(1) => vsync_out
		);		
	
		-- todo convolution takes 4 cycles, block takes one, hsync, vsync signals should be delayed by 5 cycles
		process(clk, resetn)
		begin
			if resetn = '0' then
				pixel_clock_out <= '0' ;
			elsif clk'event and clk = '1' and busy = '0' then
				pixel_clock_out <= new_conv ;
			end if ;
		end process ;
	
	
		
		sobel_response <= abs(raw_from_conv1) + abs(raw_from_conv2) ;
		--pixel_data_out <= pixel_from_conv1 + pixel_from_conv2 ;
		pixel_data_out <= std_logic_vector(sobel_response(9 downto 2));
		x_grad <= raw_from_conv1(10 downto 3) ;
		y_grad <= raw_from_conv2(10 downto 3) ;
		new_conv <= (new_conv1 AND new_conv2) ;
		busy <= (busy1 AND busy2) ;
	

end RTL;

