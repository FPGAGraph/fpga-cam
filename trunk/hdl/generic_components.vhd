--
--	Package File Template
--
--	Purpose: This package defines supplemental types, subtypes, 
--		 constants, and functions 
--
--   To use any of the example code shown below, uncomment the lines and modify as necessary
--

library IEEE;
 use IEEE.STD_LOGIC_1164.all;
 use ieee.math_real.log2;
 use ieee.math_real.ceil;

package generic_components is

Function nbit(max : integer) return integer;

type slv8_array is array (natural range <>) of std_logic_vector(7 downto 0);

component simple_counter is
	 generic(MODULO : positive := 16 ; NBIT : positive := 4);
    Port ( clk : in  STD_LOGIC;
           arazb : in  STD_LOGIC;
           sraz : in  STD_LOGIC;
           en : in  STD_LOGIC;
           Q : out  STD_LOGIC_VECTOR(NBIT - 1 downto 0)
			  );
end component;

component generic_mux is
	generic(NB_INPUTS : natural := 4 );
    Port ( s : in  STD_LOGIC_VECTOR(nbit(NB_INPUTS) - 1 downto 0);
           inputs : in  slv8_array(0 to (NB_INPUTS - 1));
           output : out  STD_LOGIC_VECTOR(7 downto 0));
end component;

component generic_latch is
	 generic(NBIT : positive := 8);
    Port ( clk : in  STD_LOGIC;
           arazb : in  STD_LOGIC;
           sraz : in  STD_LOGIC;
           en : in  STD_LOGIC;
           d : in  STD_LOGIC_VECTOR((NBIT - 1) downto 0);
           q : out  STD_LOGIC_VECTOR((NBIT - 1) downto 0));
end component;


component ram_NxN is
	generic(SIZE : natural := 64 ; NBIT : natural := 8; ADDR_WIDTH : natural := 6);
	port(
 		clk : in std_logic; 
 		we, en : in std_logic; 
 		do : out std_logic_vector(NBIT-1 downto 0 ); 
 		di : in std_logic_vector(NBIT-1 downto 0 ); 
 		addr : in std_logic_vector((ADDR_WIDTH - 1) downto 0 )
	); 
end component;

component ram_Nx8 is
	generic(N : natural := 645; A : natural := 10);
	port(
 		clk : in std_logic; 
 		we, en : in std_logic; 
 		do : out std_logic_vector(7 downto 0 ); 
 		di : in std_logic_vector(7 downto 0 ); 
 		addr : in std_logic_vector( (A - 1) downto 0 )
	); 
end component;

component fifo_Nx8 is
	generic(N : natural := 64);
	port(
 		clk, arazb, sraz : in std_logic; 
 		wr, rd : in std_logic; 
		empty, full, data_rdy : out std_logic ;
 		data_out : out std_logic_vector(7 downto 0 ); 
 		data_in : in std_logic_vector(7 downto 0 )
	); 
end component;

component hold is
	 generic(HOLD_TIME : positive := 4; HOLD_LEVEL : std_logic := '1');
    Port ( clk : in  STD_LOGIC;
           arazb : in  STD_LOGIC;
           sraz : in  STD_LOGIC;
           input: in  STD_LOGIC;
			  output: out  STD_LOGIC;
			  holding : out std_logic 
			  );
end component;

end generic_components;

Package body generic_components is

 Function nbit (max : integer) return integer is
 begin
   return (integer(ceil(log2(real(max)))));
 end nbit;
end generic_components;