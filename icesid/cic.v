`default_nettype none

module cic_filter(
  input                CLK,
  input                CLKen_in,
  input                CLKen_out,
  input  signed [15:0] SMPin,
  output signed [15:0] SMPout
);

  // D             = 1000000 / ~44100   = ~23
  // bits required = log2(2^16 * 23)    = ~21

  reg signed [21:0] inAcc;
  reg signed [21:0] outLag;
  reg signed [21:0] out;

  assign SMPout = out[21:6];

  initial begin
    inAcc  <= 0;
    outLag <= 0;
    out    <= 0;
  end

  always @(posedge CLK) begin
    if (CLKen_in) begin
      inAcc <= inAcc + SMPin;
    end
  end

  always @(posedge CLK) begin
    if (CLKen_out) begin
      out    <= inAcc - outLag;
      outLag <= inAcc;
    end
  end
endmodule
