library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity vga_ctrl is
    Port ( CLK_I : in  STD_LOGIC;
         rst : in std_logic;
         VGA_HS_O : out  STD_LOGIC;
         VGA_VS_O : out  STD_LOGIC;
         VGA_R : out  STD_LOGIC_VECTOR (3 downto 0);
         VGA_B : out  STD_LOGIC_VECTOR (3 downto 0);
         VGA_G : out  STD_LOGIC_VECTOR (3 downto 0);
         sw : in std_logic_vector (2 downto 0);
         btn : in std_logic_vector (3 downto 0);
         seg : out std_logic_vector(6 downto 0);
         c : out std_logic --digit selection signal
        );
end vga_ctrl;

architecture Behavioral of vga_ctrl is

    component clk_wiz_0
        port(
            CLK_IN1           : in     std_logic;
            CLK_OUT1          : out    std_logic
        );
    end component;

    component ssd_ctrl is
        Port (
            value : in std_logic_vector (3 downto 0);
            segOut : out std_logic_vector (6 downto 0)
        );
    end component;
    
--    component pwm_enhanced is
--    generic (
--        R : integer := 8
--    );
--    port(
--        clk : in std_logic ;
--        reset : in std_logic ;
--        dvsr : in std_logic_vector (31 downto 0);
--        duty : in std_logic_vector (R downto 0);
--        pwm_out : out std_logic
--    );
--    end component;
    --Sync Generation constants

    --***1920x1080@60Hz***-- Requires 148.5 MHz pxl_clk
    constant FRAME_WIDTH : natural := 1920;
    constant FRAME_HEIGHT : natural := 1080;

    constant eighteenth : integer := FRAME_HEIGHT/18;
    constant H_FP : natural := 88; --H front porch width (pixels)
    constant H_PW : natural := 44; --H sync pulse width (pixels)
    constant H_MAX : natural := 2200; --H total period (pixels)

    constant V_FP : natural := 4; --V front porch width (lines)
    constant V_PW : natural := 5; --V sync pulse width (lines)
    constant V_MAX : natural := 1125; --V total period (lines)

    constant H_POL : std_logic := '1';
    constant V_POL : std_logic := '1';

    --Moving Box constants
    constant BOX_WIDTH : natural := 20;
    constant BOX_CLK_DIV : natural := 300_000;--500_000;--1_000_000; --MAX=(2^25 - 1)

    constant BOX_X_MAX : natural := FRAME_WIDTH-10;
    constant BOX_Y_MAX : natural := (FRAME_HEIGHT - BOX_WIDTH);

    constant BOX_X_MIN : natural := 0;
    constant BOX_Y_MIN : natural := 0;

    constant BOX_X_INIT : std_logic_vector(11 downto 0) := x"3B6"; --950
    constant BOX_Y_INIT : std_logic_vector(11 downto 0) := x"208"; --0x208, 520

    constant PADDLE_WIDTH : natural := 15;
    constant PADDLE_LENGTH : natural := FRAME_HEIGHT/10;
    constant PADDLE_Y_MAX : natural := FRAME_HEIGHT - PADDLE_LENGTH;
    constant PADDLE_Y_MIN : natural := 0;

    constant LEFT_PADDLE_X_INIT : std_logic_vector(11 downto 0) := x"032"; --50
    constant RIGHT_PADDLE_X_INIT : std_logic_vector(11 downto 0) := x"74E"; --1870
    constant PADDLE_Y_INIT : std_logic_vector(11 downto 0) := x"1C2"; --450

    signal vsComp : std_logic;
    signal pxl_clk : std_logic;
    signal active : std_logic;

    signal h_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');
    signal v_cntr_reg : std_logic_vector(11 downto 0) := (others =>'0');

    signal h_sync_reg : std_logic := not(H_POL);
    signal v_sync_reg : std_logic := not(V_POL);

    signal h_sync_dly_reg : std_logic := not(H_POL);
    signal v_sync_dly_reg : std_logic :=  not(V_POL);

    signal vga_red_reg : std_logic_vector(3 downto 0) := (others =>'0');
    signal vga_green_reg : std_logic_vector(3 downto 0) := (others =>'0');
    signal vga_blue_reg : std_logic_vector(3 downto 0) := (others =>'0');

    signal vga_red : std_logic_vector(3 downto 0);
    signal vga_green : std_logic_vector(3 downto 0);
    signal vga_blue : std_logic_vector(3 downto 0);

    signal box_x_reg : std_logic_vector(11 downto 0) := BOX_X_INIT;
    signal box_x_dir : std_logic := '1';
    signal box_y_reg : std_logic_vector(11 downto 0) := BOX_Y_INIT;
    signal box_y_dir : std_logic := '1';
    signal box_cntr_reg : std_logic_vector(24 downto 0) := (others =>'0');

    signal left_paddle_x_reg : std_logic_vector(11 downto 0) := LEFT_PADDLE_X_INIT;
    signal left_paddle_y_reg : std_logic_vector(11 downto 0) := PADDLE_Y_INIT;
    signal left_paddle_dir : std_logic;
    signal right_paddle_x_reg : std_logic_vector(11 downto 0) := RIGHT_PADDLE_X_INIT;
    signal right_paddle_y_reg : std_logic_vector(11 downto 0) := PADDLE_Y_INIT;
    signal right_paddle_dir : std_logic;

    signal update_box : std_logic;
    signal pixel_in_box : std_logic;

    signal pixel_in_lpaddle : std_logic;
    signal pixel_in_rpaddle : std_logic;

    type rom_type is array (0 to 19) of std_logic_vector(19 downto 0); -- circle box data
    -- ROM definition
    constant BALL_ROM: rom_type :=
 (
        "00000111111111100000",
        "00001111111111110000",
        "00111111111111111100",
        "00111111111111111100",
        "01111111111111111110",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "11111111111111111111",
        "01111111111111111110",
        "00111111111111111100",
        "00111111111111111100",
        "00001111111111110000",
        "00000111111111100000"
    );

    signal ball_point : std_logic;

    signal win  : std_logic;
    signal loss : std_logic;
    
    --seven segment display
    signal left_score : std_logic_vector(3 downto 0);
    signal right_score : std_logic_vector(3 downto 0);
    signal seg0 : std_logic_vector(6 downto 0);
    signal seg1 : std_logic_vector(6 downto 0);
    signal clk_cnt : unsigned(20 downto 0); --148500000/60 = 2475000; log2(2475000) = 22


--    --pwm
--    signal counter : integer;
--    signal pxl_clk_60Hz : std_logic;
--    constant pxl_clk_60Hz_half_period : integer := 1237500; --148500000/(60*2)

--    constant resolution : integer := 8;
--    constant dvsr : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(4882, 32)); --125_000_000/(2**8) * 100; 125_000_000/(2**resolution) * pwm_freq;
--    signal pwm_rainbow_reg : std_logic;
--    signal duty_rainbow : std_logic_vector( resolution downto 0);
--    signal rainbow_cntr : unsigned(10 downto 0);

begin

--        pwm0: pwm_enhanced
--            generic map(
--                 R => resolution
--            )
--            port map(
--                clk => pxl_clk,
--                reset => rst,
--                dvsr => dvsr,
--                duty => duty_rainbow,
--                pwm_out => pwm_rainbow_reg
--           );

    clk_div_inst : clk_wiz_0
        port map(
            CLK_IN1 => CLK_I,
            CLK_OUT1 => pxl_clk
        );

    SD0 : ssd_ctrl
        port map (
            value => left_score, segOut => seg0
        );
    SD1 : ssd_ctrl
        port map (
            value => right_score, segOut => seg1
        );

    --------------------------------------------------
    -----             CLOCK LOGIC              -------
    --------------------------------------------------   
--    process(pxl_clk, rst) --slow clock
--    begin
--        if rst = '1' then
--            counter <= 0;
--            pxl_clk_60Hz <= '0';
--        elsif rising_edge(pxl_clk) then
--            if counter < pxl_clk_60Hz_half_period - 1 then
--                counter <= counter + 1;
--            else
--                counter <= 0;
--                pxl_clk_60Hz <= NOT pxl_clk_60Hz;
--            end if;
--        end if;
--    end process;

--    rainbow_counter: process(pxl_clk, rst)
--    begin
--        if rst = '1' then
--            rainbow_cntr <= (others => '0');
--        elsif rising_edge(pxl_clk) then
--            if rainbow_cntr < 256 * 6 then
--                rainbow_cntr <= rainbow_cntr + 1;
--            else
--                rainbow_cntr <= (others => '0');
--            end if;
--        end if;
--    end process;
    
    clk_cntr:process(pxl_clk, rst) --seven segment display clock
    begin
        if rst = '1' then
            clk_cnt <= (others => '0');
        elsif rising_edge(pxl_clk) then
            clk_cnt <= clk_cnt + 1;
        end if;
    end process;
    ----------------------------------------------------
    -------         TEST PATTERN LOGIC           -------
    ----------------------------------------------------          
    process(active, h_cntr_reg, v_cntr_reg, sw)
    begin
        if active = '1' then
            case sw is
                when "0000" =>
                    vsComp <= '0';                    
                    if pixel_in_lpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif pixel_in_rpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif ball_point = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif h_cntr_reg >= 950 and h_cntr_reg <= 970 then
                        if v_cntr_reg >= 30 and v_cntr_reg <= eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 2*eighteenth + 30 and v_cntr_reg <= 3*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 4*eighteenth + 30 and v_cntr_reg <= 5*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 6*eighteenth + 30 and v_cntr_reg <= 7*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 8*eighteenth + 30 and v_cntr_reg <= 9*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 10*eighteenth + 30 and v_cntr_reg <= 11*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 12*eighteenth + 30 and v_cntr_reg <= 13*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 14*eighteenth + 30 and v_cntr_reg <= 15*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 16*eighteenth + 30 and v_cntr_reg <= 17*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        else
                            vga_red <= (others => '0');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        end if;
                    else
                        vga_red <= (others => '0');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    end if;
                when "0010" =>
                    vsComp <= '0';                    
                    if pixel_in_lpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    elsif pixel_in_rpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '1');
                    elsif ball_point = '1' then
                        vga_red <= (others => '0');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '0');
                    elsif h_cntr_reg >= 950 and h_cntr_reg <= 970 then
                        if v_cntr_reg >= 30 and v_cntr_reg <= eighteenth + 30 then --red
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 2*eighteenth + 30 and v_cntr_reg <= 3*eighteenth + 30 then --orange
                            vga_red <= (others => '1');
                            vga_green <= "1100";
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 4*eighteenth + 30 and v_cntr_reg <= 5*eighteenth + 30 then --yellow
                            vga_red <= "1100";
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 6*eighteenth + 30 and v_cntr_reg <= 7*eighteenth + 30 then --green
                            vga_red <= (others => '0');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 8*eighteenth + 30 and v_cntr_reg <= 9*eighteenth + 30 then --light blue
                            vga_red <= (others => '0');
                            vga_green <= "1101";
                            vga_blue <= "1101";
                        elsif v_cntr_reg >= 10*eighteenth + 30 and v_cntr_reg <= 11*eighteenth + 30 then --indigo
                            vga_red <= "0011";
                            vga_green <= (others => '0');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 12*eighteenth + 30 and v_cntr_reg <= 13*eighteenth + 30 then -- violet
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 14*eighteenth + 30 and v_cntr_reg <= 15*eighteenth + 30 then -- red
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 16*eighteenth + 30 and v_cntr_reg <= 17*eighteenth + 30 then --orange
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        else
                            vga_red <= (others => '0');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        end if;
                    else
                        vga_red <= (others => '0');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    end if;
                    
                when "0100" => --vsComp ; Black and White
                    vsComp <= '1';                    
                    if pixel_in_lpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif pixel_in_rpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif ball_point = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '1');
                    elsif h_cntr_reg >= 950 and h_cntr_reg <= 970 then
                        if v_cntr_reg >= 30 and v_cntr_reg <= eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 2*eighteenth + 30 and v_cntr_reg <= 3*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 4*eighteenth + 30 and v_cntr_reg <= 5*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 6*eighteenth + 30 and v_cntr_reg <= 7*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 8*eighteenth + 30 and v_cntr_reg <= 9*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 10*eighteenth + 30 and v_cntr_reg <= 11*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 12*eighteenth + 30 and v_cntr_reg <= 13*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 14*eighteenth + 30 and v_cntr_reg <= 15*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 16*eighteenth + 30 and v_cntr_reg <= 17*eighteenth + 30 then
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '1');
                        else
                            vga_red <= (others => '0');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        end if;
                    else
                        vga_red <= (others => '0');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    end if;
                when "0110" => --vsComp ; colored
                    vsComp <= '1';
                    if pixel_in_lpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    elsif pixel_in_rpaddle = '1' then
                        vga_red <= (others => '1');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '1');
                    elsif ball_point = '1' then
                        vga_red <= (others => '0');
                        vga_green <= (others => '1');
                        vga_blue <= (others => '0');
                    elsif h_cntr_reg >= 950 and h_cntr_reg <= 970 then
                        if v_cntr_reg >= 30 and v_cntr_reg <= eighteenth + 30 then --red
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 2*eighteenth + 30 and v_cntr_reg <= 3*eighteenth + 30 then --orange
                            vga_red <= (others => '1');
                            vga_green <= "1100";
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 4*eighteenth + 30 and v_cntr_reg <= 5*eighteenth + 30 then --yellow
                            vga_red <= "1100";
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 6*eighteenth + 30 and v_cntr_reg <= 7*eighteenth + 30 then --green
                            vga_red <= (others => '0');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 8*eighteenth + 30 and v_cntr_reg <= 9*eighteenth + 30 then --light blue
                            vga_red <= (others => '0');
                            vga_green <= "1101";
                            vga_blue <= "1101";
                        elsif v_cntr_reg >= 10*eighteenth + 30 and v_cntr_reg <= 11*eighteenth + 30 then --indigo
                            vga_red <= "0011";
                            vga_green <= (others => '0');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 12*eighteenth + 30 and v_cntr_reg <= 13*eighteenth + 30 then -- violet
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '1');
                        elsif v_cntr_reg >= 14*eighteenth + 30 and v_cntr_reg <= 15*eighteenth + 30 then -- red
                            vga_red <= (others => '1');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        elsif v_cntr_reg >= 16*eighteenth + 30 and v_cntr_reg <= 17*eighteenth + 30 then --orange
                            vga_red <= (others => '1');
                            vga_green <= (others => '1');
                            vga_blue <= (others => '0');
                        else
                            vga_red <= (others => '0');
                            vga_green <= (others => '0');
                            vga_blue <= (others => '0');
                        end if;
                    else
                        vga_red <= (others => '0');
                        vga_green <= (others => '0');
                        vga_blue <= (others => '0');
                    end if;
                    
                when others =>
                    vsComp <= '0';                    
                    vga_red <= (others=>'0');
                    vga_green <= (others=>'0');
                    vga_blue <= (others=>'0');
            end case;
        else
            vsComp <= '0';                    
            vga_red <= (others=>'0');
            vga_green <= (others=>'0');
            vga_blue <= (others=>'0');
        end if;
    end process;


    ------------------------------------------------------
    -------          MOVING BALL LOGIC              ------
    ------------------------------------------------------

    ball_dir: process (pxl_clk, rst, loss)
    begin
        if rst = '1' then
            box_x_reg <= BOX_X_INIT;
            box_y_reg <= BOX_Y_INIT;
            left_score <= (others => '0');
            right_score <= (others => '0');
            left_paddle_y_reg <= PADDLE_Y_INIT;
            right_paddle_y_reg <= PADDLE_Y_INIT;
        elsif (rising_edge(pxl_clk)) then
            if (update_box = '1') then
                --ball movement
                if (box_x_dir = '1') then
                    box_x_reg <= box_x_reg + 1;
                else
                    box_x_reg <= box_x_reg - 1;
                end if;
                if (box_y_dir = '1') then
                    box_y_reg <= box_y_reg + 1;
                else
                    box_y_reg <= box_y_reg - 1;
                end if;

                --left wall boundary
                if (box_x_dir = '0' and (box_x_reg = BOX_X_MIN + 1)) then
                    if left_score < 15 then
                        box_x_reg <= BOX_X_INIT;
                        box_y_reg <= BOX_Y_INIT;
                        left_score <= left_score + 1;
                    else
                        box_x_reg <= BOX_X_INIT;
                        box_y_reg <= BOX_Y_INIT;
                        left_score <= (others => '0');
                        right_score <= (others => '0');
                    end if;
                end if;
                
                --right wall boundary
                if ((box_x_dir = '1' and (box_x_reg = BOX_X_MAX - 1))) then
                    if right_score < 15 then
                        box_x_reg <= BOX_X_INIT;
                        box_y_reg <= BOX_Y_INIT;
                        right_score <= right_score + 1;
                    else
                        box_x_reg <= BOX_X_INIT;
                        box_y_reg <= BOX_Y_INIT;
                        left_score <= (others => '0');
                        right_score <= (others => '0');
                    end if;
                end if;

                --left paddle top boundary
                if (box_x_dir = '0') and (box_x_reg = LEFT_PADDLE_X_INIT + 10) and ((box_y_reg <= (left_paddle_y_reg + PADDLE_LENGTH/2)) and (box_y_reg >= left_paddle_y_reg - 15)) then -- added -10 to ensure edge of ball collides with paddle
                    box_x_dir <= not(box_x_dir);
                    box_y_dir <= '0';
                end if;
                
                --left paddle bottom boundary
                if (box_x_dir = '0') and (box_x_reg = LEFT_PADDLE_X_INIT + 10) and ((box_y_reg <= (left_paddle_y_reg + PADDLE_LENGTH)) and (box_y_reg >= left_paddle_y_reg + PADDLE_LENGTH/2)) then
                    box_x_dir <= not(box_x_dir);
                    box_y_dir <= '1';
                end if;
                
                --right paddle top boundary
                if (box_x_dir = '1') and (box_x_reg = RIGHT_PADDLE_X_INIT - 10) and ((box_y_reg <= (right_paddle_y_reg + PADDLE_LENGTH/2)) and (box_y_reg >= right_paddle_y_reg - 10)) then
                    box_x_dir <= not(box_x_dir);
                    box_y_dir <= '0';
                end if;
                
                --right paddle bottom boundary
                if (box_x_dir = '1') and (box_x_reg = RIGHT_PADDLE_X_INIT - 10) and ((box_y_reg <= (right_paddle_y_reg + PADDLE_LENGTH)) and (box_y_reg >= right_paddle_y_reg + PADDLE_LENGTH/2)) then
                    box_x_dir <= not(box_x_dir);
                    box_y_dir <= '1';                    
                end if;
                
                --top/bottom wall ball boundary
                if ((box_y_dir = '1' and (box_y_reg = BOX_Y_MAX - 1)) or (box_y_dir = '0' and (box_y_reg = BOX_Y_MIN + 1))) then
                    box_y_dir <= not(box_y_dir);
                end if;
                
    ------------------------------------------------------
    -------         MOVING PADDLE LOGIC             ------
    ------------------------------------------------------   
                
                --left paddle dir and boundaries
                if btn(3) = '1' then
                    if (left_paddle_y_reg < PADDLE_Y_MAX) then --top boundary
                        left_paddle_y_reg <= left_paddle_y_reg + 1; --move up
                    else
                        left_paddle_y_reg <= left_paddle_y_reg; --dont move
                    end if;
                elsif btn(2) = '1' then
                    if (left_paddle_y_reg > PADDLE_Y_MIN) then --bottom boundary
                        left_paddle_y_reg <= left_paddle_y_reg - 1; --move down
                    else
                        left_paddle_y_reg <= left_paddle_y_reg;  --dont move
                    end if;
                end if;
                
                --right paddle dir and boundaries
                if vsComp = '1' then
                    if box_x_reg >= BOX_X_INIT then
                        if right_paddle_y_reg < PADDLE_Y_MAX + 1 then 
                            if (right_paddle_y_reg <= box_y_reg) then
                                right_paddle_y_reg <= right_paddle_y_reg + 2;--box_y_reg; --- 5;    
                            end if; 
                        else
                            right_paddle_y_reg <= right_paddle_y_reg;             
                        end if;  
                        
                        if right_paddle_y_reg > PADDLE_Y_MIN - 1 then
                            if (right_paddle_y_reg > box_y_reg) then
                                right_paddle_y_reg <= right_paddle_y_reg - 2;--box_y_reg; --- 5;
                            end if;                        
                        else
                            right_paddle_y_reg <= right_paddle_y_reg;      
                        end if;
                    end if;
                else 
                    if btn(0) = '1' then
                        if (right_paddle_y_reg < PADDLE_Y_MAX) then --top boundary
                            right_paddle_y_reg <= right_paddle_y_reg + 1; --move up
                        else
                            right_paddle_y_reg <= right_paddle_y_reg; --dont move
                        end if;
                    elsif btn(1) = '1' then
                        if (right_paddle_y_reg > PADDLE_Y_MIN) then --bottom boundary
                            right_paddle_y_reg <= right_paddle_y_reg - 1; --move down
                        else
                            right_paddle_y_reg <= right_paddle_y_reg;  --dont move
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ball_and_paddle_speed: process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            if (box_cntr_reg = (BOX_CLK_DIV - 1)) then
                box_cntr_reg <= (others=>'0');
            else
                box_cntr_reg <= box_cntr_reg + 1;
            end if;
        end if;
    end process;

    update_box <= '1' when box_cntr_reg = (BOX_CLK_DIV - 1) else
                  '0';

    pixel_in_box <= '1' when (((h_cntr_reg >= box_x_reg) and (h_cntr_reg < (box_x_reg + BOX_WIDTH))) and
                             ((v_cntr_reg >= box_y_reg) and (v_cntr_reg < (box_y_reg + BOX_WIDTH)))) else
                    '0';

    pixel_in_lpaddle <= '1' when (((h_cntr_reg >= left_paddle_x_reg) and (h_cntr_reg < (left_paddle_x_reg + PADDLE_WIDTH))) and
                                 ((v_cntr_reg >= left_paddle_y_reg) and (v_cntr_reg < (left_paddle_y_reg + PADDLE_LENGTH)))) else
                        '0';

    pixel_in_rpaddle <= '1' when (((h_cntr_reg >= right_paddle_x_reg) and (h_cntr_reg < (right_paddle_x_reg + PADDLE_WIDTH))) and
                                 ((v_cntr_reg >= right_paddle_y_reg) and (v_cntr_reg < (right_paddle_y_reg + PADDLE_LENGTH)))) else
                        '0';

    seg <= seg0 when clk_cnt(clk_cnt'high) = '0' else --clk_cnt'high is the MSB of the vector, possible because it is unsigned
           seg1;

    c <= clk_cnt(clk_cnt'high);

    ball_point <= BALL_ROM(conv_integer(v_cntr_reg(4 downto 0) - box_y_reg))(conv_integer(h_cntr_reg(4 downto 0) - box_x_reg)) when pixel_in_box = '1' else
                  '0';

    ------------------------------------------------------
    -------         SYNC GENERATION                 ------
    ------------------------------------------------------

    process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            if (h_cntr_reg = (H_MAX - 1)) then
                h_cntr_reg <= (others =>'0');
            else
                h_cntr_reg <= h_cntr_reg + 1;
            end if;
        end if;
    end process;

    process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            if ((h_cntr_reg = (H_MAX - 1)) and (v_cntr_reg = (V_MAX - 1))) then
                v_cntr_reg <= (others =>'0');
            elsif (h_cntr_reg = (H_MAX - 1)) then
                v_cntr_reg <= v_cntr_reg + 1;
            end if;
        end if;
    end process;

    process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            if (h_cntr_reg >= (H_FP + FRAME_WIDTH - 1)) and (h_cntr_reg < (H_FP + FRAME_WIDTH + H_PW - 1)) then
                h_sync_reg <= H_POL;
            else
                h_sync_reg <= not(H_POL);
            end if;
        end if;
    end process;


    process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            if (v_cntr_reg >= (V_FP + FRAME_HEIGHT - 1)) and (v_cntr_reg < (V_FP + FRAME_HEIGHT + V_PW - 1)) then
                v_sync_reg <= V_POL;
            else
                v_sync_reg <= not(V_POL);
            end if;
        end if;
    end process;


    active <= '1' when ((h_cntr_reg < FRAME_WIDTH) and (v_cntr_reg < FRAME_HEIGHT))else
              '0';

    process (pxl_clk)
    begin
        if (rising_edge(pxl_clk)) then
            v_sync_dly_reg <= v_sync_reg;
            h_sync_dly_reg <= h_sync_reg;
            vga_red_reg <= vga_red;
            vga_green_reg <= vga_green;
            vga_blue_reg <= vga_blue;
        end if;
    end process;

    VGA_HS_O <= h_sync_dly_reg;
    VGA_VS_O <= v_sync_dly_reg;
    VGA_R <= vga_red_reg;
    VGA_G <= vga_green_reg;
    VGA_B <= vga_blue_reg;
end Behavioral;
