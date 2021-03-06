----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    15:23:24 10/11/2012 
-- Design Name: 
-- Module Name:    HARRIS - Behavioral 
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

library work ;
use work.camera.all ;
use work.generic_components.all ;


entity HARRIS is
generic(WIDTH : positive := 640 ; HEIGHT : positive := 480; WINDOW_SIZE : positive := 8; DS_FACTOR : natural := 2);
port (
		clk : in std_logic; 
 		resetn : in std_logic; 
 		pixel_clock, hsync, vsync : in std_logic; 
 		pixel_clock_out, hsync_out, vsync_out : out std_logic; 
 		pixel_data_in : in std_logic_vector(7 downto 0 ); 
 		harris_out : out std_logic_vector(15 downto 0 )
);
end HARRIS;

architecture Behavioral of HARRIS is
	signal pixel_from_sobel : std_logic_vector(7 downto 0);
	signal pixel_from_gauss : std_logic_vector(7 downto 0);
	
	signal pxclk_from_gauss, href_from_gauss, vsync_from_gauss : std_logic ;
	signal pxclk_from_sobel, href_from_sobel, vsync_from_sobel : std_logic ;


	signal xgrad, ygrad : signed(7 downto 0);
	signal xgrad_square, ygrad_square, xygrad, xgrad_square_sum, ygrad_square_sum, xygrad_sum : signed(15 downto 0);
	signal xgrad_square_sum_latched, ygrad_square_sum_latched, xygrad_sum_latched : signed(15 downto 0);
	signal xgrad_square_sum_latched_divn, ygrad_square_sum_latched_divn, xygrad_sum_latched_divn : signed(15 downto 0);
	signal xgrad_square_sum_ram, ygrad_square_sum_ram, xygrad_sum_ram : signed(15 downto 0);
	signal xgrad_square_acc, ygrad_square_acc, xygrad_acc : signed(15 downto 0);

	signal pixel_count : std_logic_vector((nbit(WIDTH) - 1) downto 0);
	signal line_count : std_logic_vector((nbit(HEIGHT) - 1) downto 0);
	signal block_xaddress, block_xaddress_old : std_logic_vector((nbit(WIDTH/WINDOW_SIZE) - 1) downto 0);
	signal block_xpos : std_logic_vector((nbit(WINDOW_SIZE) - 1) downto 0);
	signal block_yaddress, block_yaddress_old : std_logic_vector((nbit(HEIGHT/WINDOW_SIZE) - 1) downto 0);
	signal block_ypos : std_logic_vector((nbit(WINDOW_SIZE) - 1) downto 0);
	
	signal ram_in, ram_out : std_logic_vector(47 downto 0);
	signal ram_address : std_logic_vector(nbit(WIDTH/WINDOW_SIZE)-1 downto 0);
	
	signal store_grads, store_grads_re, store_grads_old : std_logic ;
	
	signal pxclk_from_sobel_old, pxclk_from_sobel_re : std_logic ;
	signal href_from_sobel_old, href_from_sobel_re : std_logic ;
	signal end_of_window : std_logic ;
	
	signal hsync_delayed, vsync_delayed : std_logic ;
	
begin

	gauss3x3_0	: gauss3x3 
		generic map(WIDTH => WIDTH,
				  HEIGHT => HEIGHT)
		port map(
					clk => clk ,
					resetn => resetn ,
					pixel_clock => pixel_clock, hsync => hsync, vsync =>  vsync,
					pixel_clock_out => pxclk_from_gauss, hsync_out => href_from_gauss, vsync_out => vsync_from_gauss, 
					pixel_data_in => pixel_data_in,  
					pixel_data_out => pixel_from_gauss
		);		
		
		
	sobel0: sobel3x3
		generic map(
		  WIDTH => WIDTH,
		  HEIGHT => HEIGHT)
		port map(
			clk => clk ,
			resetn => resetn ,
			pixel_clock => pxclk_from_gauss, hsync => href_from_gauss, vsync =>  vsync_from_gauss,
			pixel_clock_out => pxclk_from_sobel, hsync_out => href_from_sobel, vsync_out => vsync_from_sobel, 
			pixel_data_in => pixel_from_gauss,  
			pixel_data_out => pixel_from_sobel,
			x_grad => xgrad ,
			y_grad => ygrad
		);	
	
	pixel_counter0 : pixel_counter
		generic map(MAX => WIDTH)
		port map(
			clk => clk,
			resetn => resetn,
			pixel_clock => pxclk_from_sobel, hsync => href_from_sobel,
			pixel_count => pixel_count
			);
	
		process(clk, resetn)
		begin
			if resetn = '0' then
				block_xaddress <= (others => '0') ;
				block_xpos <= (others => '0') ;
			elsif clk'event and clk = '1' then
				if href_from_sobel = '1' then
					block_xaddress <= (others => '0') ;
					block_xpos <= (others => '0') ;
				elsif pxclk_from_sobel_re = '1'  then
						if block_xpos = (WINDOW_SIZE - 1) then
							block_xaddress <= block_xaddress  + 1  ;
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
			hsync => href_from_sobel, vsync => vsync_from_sobel,
			line_count => line_count );
	
	
		process(clk, resetn)
		begin
			if resetn = '0' then
				block_yaddress <= (others => '0') ;
				block_ypos <= (others => '0') ;
			elsif clk'event and clk = '1' then
				if vsync_from_sobel = '1' then
					block_yaddress <= (others => '0') ;
					block_ypos <= (others => '0') ;
				elsif href_from_sobel_re = '1' then
					if  block_ypos = (WINDOW_SIZE - 1) then
						block_yaddress <= block_yaddress  + 1  ;
						block_ypos <= (others => '0');
					else
						block_ypos <= block_ypos + 1;
					end if ;
				end if ;
			end if ;
		end process ;	
		
		
		xgrad_square <= xgrad * xgrad ;
		ygrad_square <= ygrad * ygrad ;
		xygrad <= xgrad * ygrad ;
	
		xgrad_square_sum <= SHIFT_RIGHT(xgrad_square,DS_FACTOR) + xgrad_square_sum_latched ; -- accumulating in register
		ygrad_square_sum <= SHIFT_RIGHT(ygrad_square,DS_FACTOR) + ygrad_square_sum_latched ; -- need to control overflow
		xygrad_sum <= SHIFT_RIGHT(xygrad,DS_FACTOR) + xygrad_sum_latched ;

		process(clk, resetn)
		begin
			if resetn = '0' then
				xgrad_square_sum_latched <= (others => '0');
				ygrad_square_sum_latched <= (others => '0');
				xygrad_sum_latched <= (others => '0');
			elsif clk'event and clk = '1' then 
				pxclk_from_sobel_old <= pxclk_from_sobel ;
				href_from_sobel_old <= href_from_sobel ;
				if (block_xpos = 0) then
						xgrad_square_sum_latched <= (others => '0');
						ygrad_square_sum_latched <= (others => '0');
						xygrad_sum_latched <= (others => '0');
				elsif pxclk_from_sobel_re = '1' then
					xgrad_square_sum_latched <= xgrad_square_sum;
					ygrad_square_sum_latched <= ygrad_square_sum;
					xygrad_sum_latched <= xygrad_sum;
				end if ;
			end if ;
		end process ;
		pxclk_from_sobel_re <= pxclk_from_sobel AND (NOT pxclk_from_sobel_old);
		href_from_sobel_re <= href_from_sobel AND (NOT href_from_sobel_old);


		xgrad_square_sum_latched_divn <= SHIFT_RIGHT(xgrad_square_sum_latched,nbit(WINDOW_SIZE));  -- need to evaluate shift dependeing on window size
		ygrad_square_sum_latched_divn <= SHIFT_RIGHT(ygrad_square_sum_latched,nbit(WINDOW_SIZE));
		xygrad_sum_latched_divn <= SHIFT_RIGHT(xygrad_sum_latched,nbit(WINDOW_SIZE)) ;

		xgrad_square_acc <= xgrad_square_sum_latched_divn + xgrad_square_sum_ram when block_ypos /= 0 else -- need to consider overflow
								xgrad_square_sum_latched_divn; -- accumulating in RAM

		ygrad_square_acc  <= ygrad_square_sum_latched_divn + ygrad_square_sum_ram when block_ypos /= 0 else -- need to consider overflow
									ygrad_square_sum_latched_divn	; 

		xygrad_acc <=  xygrad_sum_latched_divn + xygrad_sum_ram  when block_ypos /= 0 else  -- need to consider overflow
							xygrad_sum_latched_divn;
		
		ram_in(47 downto 32) <= std_logic_vector(xgrad_square_acc) ;
		ram_in(31 downto 16) <= std_logic_vector(ygrad_square_acc)	; 
		ram_in(15 downto 0) <= std_logic_vector(xygrad_acc);
		
		
		xgrad_square_sum_ram  <= signed(ram_out(47 downto 32)) ;
		ygrad_square_sum_ram <= signed(ram_out(31 downto 16)) ;
		xygrad_sum_ram <= signed(ram_out(15 downto 0)) ;
		
		ram_address <= block_xaddress_old when block_xaddress_old /= WIDTH/WINDOW_SIZE else
						   (others => '0');
		
		harris_window_ram : dpram_NxN 
			generic map(SIZE => WIDTH/WINDOW_SIZE , NBIT => 48, ADDR_WIDTH => nbit(WIDTH/WINDOW_SIZE))
			port map(
				clk => clk,  
				we => store_grads, 		
				di =>  ram_in,
				a	=> ram_address,
				dpra => std_logic_vector(to_unsigned(0, nbit(WIDTH/WINDOW_SIZE))),
				spo => ram_out
				--dpo =>  		
			); 
			
		process(clk, resetn)
		begin
			if resetn = '0' then
				block_yaddress_old <= (others => '0') ;
				block_xaddress_old <= (others => '0') ;
			elsif clk'event and clk = '1' then
				block_yaddress_old <= block_yaddress ;
				block_xaddress_old <= block_xaddress ;
			end if ;
		end process ;
		
		store_grads <= '1' when block_xaddress_old /= block_xaddress and href_from_sobel = '0' else
							'0' ;
		
--		store_grads <= '1' when block_xpos = (WINDOW_SIZE - 1) else
--							'0' ;
--		process(clk, resetn)
--		begin
--			if resetn = '0' then
--				store_grads_old <= '0' ;
--			elsif clk'event and clk = '1' then 
--				store_grads_old <= store_grads ;
--			end if ;
--		end process ;		
--		store_grads_re <= store_grads and (NOT store_grads_old);
		
--		end_of_window <= pxclk_from_sobel_re when block_ypos = WINDOW_SIZE - 1 else
--						  '0' ;

		end_of_window <= '1' when block_xaddress_old /= block_xaddress and block_ypos = WINDOW_SIZE - 1 and href_from_sobel = '0' else
							  '0' ;
		
		
	harris_rep0: HARRIS_RESPONSE 
	port map(
			clk => clk, resetn => resetn,
			en => end_of_window,
			xgrad_square_sum => xgrad_square_acc, ygrad_square_sum => ygrad_square_acc, xygrad_sum => xygrad_acc,
			dv	=> pixel_clock_out,
			harris_response => harris_out
	);
		
	vsync_out <= vsync_delayed when 	block_yaddress = 0  and block_xaddress = 0 else
					 '0' ;
	hsync_out <= hsync_delayed when  block_xaddress = 0 and block_ypos = 0 else
					 '0' ;
		
		delay_sync: generic_delay
		generic map( WIDTH =>  2 , DELAY => 7)
		port map(
			clk => clk, resetn => resetn ,
			input(0) => href_from_sobel ,
			input(1) => vsync_from_sobel ,
			output(0) => hsync_delayed ,
			output(1) => vsync_delayed
		);	
		

end Behavioral;

