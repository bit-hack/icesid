// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module clipper (
    input  signed [16:0] iIn,
    output signed [15:0] oOut
);
  /* verilog_format: off */
  assign oOut =
      (iIn[16:15] == 2'b10) ? 16'h8000 :  // clip negative
      (iIn[16:15] == 2'b01) ? 16'h7fff :  // clip positive
       iIn[15:0];                         // unclipped
  /* verilog_format: on */
endmodule
