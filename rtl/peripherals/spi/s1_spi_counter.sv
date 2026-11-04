module spi_counter (
    input  logic       clk,
    input  logic       rst,

    input  logic       clear,
    input  logic       increment,

    output logic [3:0] count,
    output logic       done
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            count <= 4'd0;
        end

        else if (clear) begin
            count <= 4'd0;
        end

        else if (increment) begin
            count <= count + 4'd1;
        end

    end

    assign done = (count == 4'd8);

endmodule

