`default_nettype none

module clipper(
  input  signed [16:0] in,
  output signed [15:0] out
);
  assign out =
    (in[16:15] == 2'b10) ? 16'h8000 :  // clip negative
    (in[16:15] == 2'b01) ? 16'h7fff :  // clip positive
     in[15:0];                         // unclipped
endmodule
