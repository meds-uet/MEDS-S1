module baud_generator (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,

    input  logic [15:0] divider,

    output logic        tick
);

    logic [15:0] counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 16'd0;
            tick    <= 1'b0;
        end
        else if (!enable) begin
            counter <= 16'd0;
            tick    <= 1'b0;
        end
        else if (divider == 16'd0) begin
            counter <= 16'd0;
            tick    <= 1'b0;
        end
        else if (counter == divider - 16'd1) begin
            counter <= 16'd0;
            tick    <= 1'b1;
        end
        else begin
            counter <= counter + 16'd1;
            tick    <= 1'b0;
        end
    end

endmodule

