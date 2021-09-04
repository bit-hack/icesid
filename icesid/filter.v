// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module filter (
    input                clk,    // system clock
    input                clkEn,  // clock enable
    input  signed [15:0] iIn,    // filter input
    input                iWE,    // data write
    input         [ 4:0] iAddr,  // address bus
    input         [ 7:0] iData,  // data bus
    output signed [15:0] oLP,    // lowpass output
    output signed [15:0] oBP,    // bandpass output
    output signed [15:0] oHP     // highpass output
);

  reg signed [16:0] low;
  reg signed [16:0] high;
  reg signed [16:0] band;

  clipper oLPClipper (
      low,
      oLP
  );
  clipper oBPClipper (
      band,
      oBP
  );
  clipper oHPClipper (
      high,
      oHP
  );

  /* verilog_format: off */

  reg [15:0] fCurve[2048];
  initial begin
    // load in the coefficient table
    $readmemh("curve_6581.hex", fCurve);
  end

  // filter coefficient is calculated as follows:
  // coef = 2 * sin( pi * freq / sid_clock_rate ) * 0x10000
  reg [15:0] cutCoef;

  // filter cutoff smothing filter
  reg [15:0] cutCoefLag0;
  reg [15:0] cutCoefLag1;

  // note: the resonance coefficient is backwards and increases resonance
  //       as it aproaches zero. this is currently arbitaraly mapped
  //       into a useable range but should be tuned in the future.
  wire [15:0] resCoef = 16'hbfff - (regRes << 11);

  // 16x16 multiplier
  reg signed  [16:0] mulA;
  reg         [15:0] mulB;
  wire signed [15:0] mulOut;
  mult16x16 mul (
      .clk    (clk),
      .iSignal(mulA),
      .iCoef  (mulB),
      .oOut   (mulOut)
  );

  /* verilog_format: on */

  initial begin
    state       = 7;
    low         = 0;
    high        = 0;
    band        = 0;
    mulA        = 0;
    mulB        = 0;
    cutCoefLag0 = 0;
    cutCoefLag1 = 0;
    regFreq     = 0;
    regRes      = 0;
  end

  always @(posedge clk) begin
    cutCoef <= fCurve[regFreq];
    // simple filter to reduce pops with fast cutoff changes.
    if (clkEn) begin
      cutCoefLag0 <= (cutCoefLag0 + cutCoef) >> 1;
      cutCoefLag1 <= (cutCoefLag1 + cutCoefLag0) >> 1;
    end
  end

  // note: due to the registering of the multiplier inputs some extra
  //       wait states had to be added to the state machine. this should
  //       be fixed as its ugly.

  // note: the output of each filter mode is delayed by a number of cycles
  //       from each other which would cause the sum of multiple modes to
  //       be inaccurate. this should be fixed.

  reg [2:0] state;
  always @(posedge clk) begin
    if (clkEn) begin
      mulA  <= band;
      mulB  <= cutCoefLag1;
      state <= 0;
    end else begin
      case (state)
        0: state <= 1;  // delay - fixme
        1: begin
          low   <= low + mulOut;  // low + (cutoff * band)
          mulA  <= band;
          mulB  <= resCoef;
          state <= 2;
        end
        2: state <= 3;  // delay - fixme
        3: begin
          high  <= iIn - low - mulOut;  // in - low - (res * band)
          mulA  <= high;
          mulB  <= cutCoefLag1;
          state <= 4;
        end
        4: state <= 5;  // delay - fixme
        5: begin
          band  <= band + mulOut;  // band + (cutoff * High)
          state <= 6;
        end
      endcase
    end
  end

  // address/data decoder
  reg [10:0] regFreq;
  reg [ 3:0] regRes;
  always @(posedge clk) begin
    if (iWE) begin
      case (iAddr)
        'h15: begin
          regFreq <= {regFreq[10:3], iData[2:0]};
        end
        'h16: begin
          regFreq <= {iData[7:0], regFreq[2:0]};
        end
        'h17: begin
          regRes <= {iData[7:4]};
        end
      endcase
    end
  end
endmodule
