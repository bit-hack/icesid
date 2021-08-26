`default_nettype none

// I2S slave module
// sample rate is 96Khz
module i2s(
        input CLK,              // system clock (24Mhz)
        input signed [15:0] IN, // 16bit signed sample input
        input i2s_sclk,         // I2S clock
        input i2s_lrclk,        // I2S LR clock
        output i2s_din,         // I2S DAC data in
        output i2s_sampled      // asserted at sample-rate
    );

    reg [1:0] i2s_sclk_sync;
    reg       i2s_sclk_rise;
    reg       i2s_sclk_fall;

    reg [1:0] i2s_lrclk_sync;

    always @(posedge CLK) begin
        i2s_sclk_sync  <= { i2s_sclk_sync[0],   i2s_sclk };
        i2s_sclk_rise  <=   i2s_sclk_sync[0] & ~i2s_sclk_sync[1];
        i2s_sclk_fall  <=  ~i2s_sclk_sync[0] &  i2s_sclk_sync[1];
        i2s_lrclk_sync <= { i2s_lrclk_sync[0], i2s_lrclk };
    end

    reg w;                      // word select delay
    reg [15:0] data;            // output shift register
    assign i2s_din = data[15];  // output msb

    reg sampled;
    assign i2s_sampled = sampled;

    always @(posedge CLK) begin
        i2s_sampled <= 0;
        if (i2s_sclk_rise) begin
            // Reload on word select change
            if (i2s_lrclk_sync[1] ^ w) begin
                data <= IN;
                i2s_sampled <= i2s_lrclk_sync[1];
            end
            // Save word select
            w <= i2s_lrclk_sync[1];
        end else if (i2s_sclk_fall) begin
            // Shift on falling edge
            data <= { data[14:0], 1'b0 };
        end
    end
endmodule
