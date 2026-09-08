module cs_register (
    input  logic        clk,
    input  logic        rst,

    input  logic        write_en,
    input  logic [31:0] write_data,

    output logic        cs
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            cs <= 1'b1;      //again 1 at reset
        end

        else if (write_en) begin
            cs <= ~write_data[0];  // write_data[0]=1 → cs=0 (asserted, active-low)
                                   // write_data[0]=0 → cs=1 (deasserted)
        end

    end

endmodule