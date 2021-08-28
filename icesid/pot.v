module sid_pot(
    input CLK,
    input CLKen,
    output [7:0] DATA,
    inout POT_IO,
);

    reg [8:0] phi2_cycle_count;
    reg [7:0] pot_val;
    reg oe;
    wire pot_in;

    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
        .IO_STANDARD("SB_LVCMOS")
    ) pot_io (
        .PACKAGE_PIN(POT_IO),
        .OUTPUT_ENABLE(oe),
        .D_OUT_0(1'b0), // drive to ground
        .D_IN_1(pot_in)
    );

    always @(posedge CLK) begin
        if (CLKen) begin
            phi2_cycle_count <= phi2_cycle_count + 1;
        end
        if (phi2_cycle_count <= 255) begin
            // drive to ground for 256 cycles
            oe <= 1;
        end else begin
            // sample how long it takes to rise
            oe <= 0;
            if (pot_in) begin
                pot_val <= phi2_cycle_count[7:0];
                phi2_cycle_count <= 0;
            end
        end
    end

    assign DATA = pot_val;

endmodule
