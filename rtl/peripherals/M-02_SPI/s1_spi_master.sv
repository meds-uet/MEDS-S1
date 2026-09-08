// https://edaplayground.com/x/LzDv

module spi_master #(
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    // ---------------------------------------------------------
    // Control
    // ---------------------------------------------------------

    input  logic             enable,
    input  logic             start,

    // ---------------------------------------------------------
    // SPI Mode
    // ---------------------------------------------------------

    input  logic             cpol,
    input  logic             cpha,

    // ---------------------------------------------------------
    // Baud Rate
    // ---------------------------------------------------------

    input  logic [15:0]      divider,

    // ---------------------------------------------------------
    // Parallel Data
    // ---------------------------------------------------------

    input  logic [WIDTH-1:0] tx_data,
    output logic [WIDTH-1:0] rx_data,

    output logic             rx_valid,
    output logic             busy,

    // ---------------------------------------------------------
    // SPI Pins
    // ---------------------------------------------------------

    output logic             sclk,
    output logic             mosi,

    input  logic             miso,

    output logic             cs
);


    // =========================================================
    // INTERNAL SIGNALS
    // =========================================================

    logic tick;

    logic sck_rising;
    logic sck_falling;

    logic tx_load;
    logic tx_shift_en;

    logic rx_shift_en;

    logic counter_clear;
    logic counter_increment;

    logic rx_capture;

    logic cs_active;

    logic [3:0] bit_count;
    logic       bits_done;

    logic [WIDTH-1:0] tx_shift_data;
    logic [WIDTH-1:0] rx_shift_data;


    // =========================================================
    // BAUD RATE GENERATOR
    // =========================================================

    baud_generator baud_gen (
        .clk     (clk),
        .rst     (rst),
        .enable  (busy),
        .divider (divider),
        .tick    (tick)
    );


    // =========================================================
    // SCLK GENERATOR
    // =========================================================

    sclk_generator sclk_gen (
        .clk         (clk),
        .rst         (rst),

        .enable      (busy),
        .tick        (tick),

        .cpol        (cpol),

        .sclk        (sclk),

        .sck_rising  (sck_rising),
        .sck_falling (sck_falling)
    );


    // =========================================================
    // TX SHIFT REGISTER
    //
    // No MUX.
    //
    // load     = parallel load
    // shift_en = shift
    // =========================================================

    tx_shift_register #(
        .WIDTH(WIDTH)
    ) tx_shift (
        .clk           (clk),
        .rst           (rst),

        .load          (tx_load),
        .shift_en      (tx_shift_en),

        .parallel_data (tx_data),

        .mosi          (mosi),
        .data          (tx_shift_data)
    );


    // =========================================================
    // RX SHIFT REGISTER
    //
    // No MUX.
    // =========================================================

    rx_shift_register #(
        .WIDTH(WIDTH)
    ) rx_shift (
        .clk      (clk),
        .rst      (rst),

        .shift_en (rx_shift_en),

        .miso     (miso),

        .data     (rx_shift_data)
    );


    // =========================================================
    // BIT COUNTER
    // =========================================================

    spi_counter bit_counter (
        .clk       (clk),
        .rst       (rst),

        .clear     (counter_clear),
        .increment (counter_increment),

        .count     (bit_count),
        .done      (bits_done)
    );


    // =========================================================
    // FSM
    // =========================================================

    spi_fsm controller (
        .clk                (clk),
        .rst                (rst),

        .start              (enable & start),

        .cpol               (cpol),
        .cpha               (cpha),

        .sck_rising         (sck_rising),
        .sck_falling        (sck_falling),

        .bits_done          (bits_done),

        .busy               (busy),
        .cs_active          (cs_active),

        .tx_load            (tx_load),
        .tx_shift_en        (tx_shift_en),
        .rx_shift_en        (rx_shift_en),

        .counter_clear      (counter_clear),
        .counter_increment  (counter_increment),

        .rx_capture         (rx_capture)
    );


    // =========================================================
    // CHIP SELECT
    //
    // CS is active LOW. cs_active from the FSM is active HIGH.
    // =========================================================

    assign cs = ~cs_active;


    // =========================================================
    // RX DATA OUTPUT REGISTER
    //
    // Reuses rxdata_register instead of duplicating the same
    // capture logic inline.
    // =========================================================

    rxdata_register #(
        .WIDTH(WIDTH)
    ) rx_data_reg (
        .clk           (clk),
        .rst           (rst),

        .capture_en    (rx_capture),
        .rx_shift_data (rx_shift_data),

        .rx_data       (rx_data)
    );


    // =========================================================
    // RX VALID PULSE
    //
    // rx_valid trails rx_data by construction: rxdata_register
    // captures rx_shift_data on the same rx_capture edge that
    // sets rx_valid here, so both update on the same clock.
    // =========================================================

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            rx_valid <= 1'b0;
        end

        else begin
            rx_valid <= rx_capture;
        end

    end

endmodule