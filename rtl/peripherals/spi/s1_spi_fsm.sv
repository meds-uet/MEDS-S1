module spi_fsm (
    input  logic clk,
    input  logic rst,

    input  logic start,

    input  logic cpol,
    input  logic cpha,

    input  logic sck_rising,
    input  logic sck_falling,

    input  logic bits_done,

    output logic busy,
    output logic cs_active,

    output logic tx_load,
    output logic tx_shift_en,
    output logic rx_shift_en,

    output logic counter_clear,
    output logic counter_increment,

    output logic rx_capture
);

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        TRANSFER,
        FINISH
    } state_t;

    state_t state;
    state_t next_state;


    // =========================================================
    // STATE REGISTER
    // =========================================================

    always_ff @(posedge clk or posedge rst) begin

        if (rst)
            state <= IDLE;
        else
            state <= next_state;

    end


    // =========================================================
    // NEXT STATE LOGIC
    // =========================================================

    always_comb begin

        next_state = state;

        case (state)

            IDLE: begin
                if (start)
                    next_state = LOAD;
            end

            LOAD: begin
                next_state = TRANSFER;
            end

            TRANSFER: begin
                if (bits_done)
                    next_state = FINISH;
            end

            FINISH: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase

    end


    // =========================================================
    // OUTPUT LOGIC
    // =========================================================

    always_comb begin

        busy              = 1'b0;
        cs_active         = 1'b0;

        tx_load           = 1'b0;
        tx_shift_en       = 1'b0;
        rx_shift_en       = 1'b0;

        counter_clear     = 1'b0;
        counter_increment = 1'b0;

        rx_capture        = 1'b0;


        case (state)

            // -------------------------------------------------
            // IDLE
            // -------------------------------------------------

            IDLE: begin

                busy      = 1'b0;
                cs_active = 1'b0;

            end


            // -------------------------------------------------
            // LOAD
            // -------------------------------------------------

            LOAD: begin

                busy          = 1'b1;
                cs_active     = 1'b1;

                tx_load       = 1'b1;
                counter_clear = 1'b1;

            end


            // -------------------------------------------------
            // TRANSFER
            // -------------------------------------------------

            TRANSFER: begin

                busy      = 1'b1;
                cs_active = 1'b1;


                // =============================================
                // SPI CPHA = 0
                // =============================================

                if (!cpha) begin

                    // -----------------------------------------
                    // CPOL = 0
                    // Leading edge  = Rising
                    // Trailing edge = Falling
                    // -----------------------------------------

                    if (!cpol) begin

                        if (sck_rising) begin
                            rx_shift_en       = 1'b1;
                            counter_increment = 1'b1;
                        end

                        if (sck_falling) begin
                            tx_shift_en = 1'b1;
                        end

                    end


                    // -----------------------------------------
                    // CPOL = 1
                    // Leading edge  = Falling
                    // Trailing edge = Rising
                    // -----------------------------------------

                    else begin

                        if (sck_falling) begin
                            rx_shift_en       = 1'b1;
                            counter_increment = 1'b1;
                        end

                        if (sck_rising) begin
                            tx_shift_en = 1'b1;
                        end

                    end

                end


                // =================================================
                // SPI CPHA = 1
                // =================================================

                else begin

                    // -----------------------------------------
                    // CPOL = 0
                    // Leading edge  = Rising
                    // Trailing edge = Falling
                    // -----------------------------------------

                    if (!cpol) begin

                        if (sck_rising) begin
                            tx_shift_en = 1'b1;
                        end

                        if (sck_falling) begin
                            rx_shift_en       = 1'b1;
                            counter_increment = 1'b1;
                        end

                    end


                    // -----------------------------------------
                    // CPOL = 1
                    // Leading edge  = Falling
                    // Trailing edge = Rising
                    // -----------------------------------------

                    else begin

                        if (sck_falling) begin
                            tx_shift_en = 1'b1;
                        end

                        if (sck_rising) begin
                            rx_shift_en       = 1'b1;
                            counter_increment = 1'b1;
                        end

                    end

                end

            end


            // -------------------------------------------------
            // FINISH
            // -------------------------------------------------

            FINISH: begin

                busy       = 1'b0;
                cs_active  = 1'b0;
                rx_capture = 1'b1;

            end

        endcase

    end

endmodule