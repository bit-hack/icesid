// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

/* verilator lint_off WIDTH */

module filter (
    input                clk,     // system clock
    input                clkEn,   // clock enable
    input  signed [15:0] iIn,     // filter input
    input                iWE,     // data write
    input         [ 4:0] iAddr,   // address bus
    input         [ 7:0] iData,   // data bus
    input                i6581,   // use filter curve lookup table
    output signed [15:0] oLP,     // lowpass output
    output signed [15:0] oBP,     // bandpass output
    output signed [15:0] oHP      // highpass output
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
  // note: multiplier takes 2 cycles from setting mulA/B to reading mulOut
  reg  signed [16:0] mulA;
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
    state       = 0;
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

  // 2 * sin( pi * 12500 / 1000000 ) * 0x10000 = 5145 max
  // reg freq = 11bits = 8191 max
  // 8191 / 2 + (8191 / 8) = 5119
  wire [15:0] cutCoef8580 = regFreq[10:1] + regFreq[10:3];

  always @(posedge clk) begin

    // the filter curve is optionally enabled
    cutCoef <= i6581 ? fCurve[regFreq] : cutCoef8580;

    // simple filter to reduce pops with fast cutoff changes.
    if (clkEn) begin
      cutCoefLag0 <= (cutCoefLag0 + cutCoef) >> 1;
      cutCoefLag1 <= (cutCoefLag1 + cutCoefLag0) >> 1;
    end
  end

  // note: the output of each filter mode is delayed by a number of cycles
  //       from each other which would cause the sum of multiple modes to
  //       be inaccurate. this should be fixed.

  // state variable filter loop:
  //
  // low  =      low + (band * cutoff)
  // high = in - low - (band * res   )
  // band = band     + (High * cutoff)
  //

  reg [2:0] state;
  always @(posedge clk) begin
    case (state)
      0: state <= clkEn ? 1 : 0;
      1: state <= 2;
      2: state <= 3;
      3: state <= 4; // delay for `high` to propagate
      4: state <= 0;
      default: state <= 0;
    endcase
  end

  // setup multiplier one clock ahead
  always @(posedge clk) begin
    case (state)
      0: begin mulA <= band; mulB <= cutCoefLag1; end
      1: begin mulA <= band; mulB <= resCoef;     end
      3: begin mulA <= high; mulB <= cutCoefLag1; end
      default ;
    endcase
  end

  // compute filter stages
  always @(posedge clk) begin
    case (state)
      1: low  <= low + mulOut;
      2: high <= iIn - low - mulOut;
      4: band <= band + mulOut;
      default ;
    endcase
  end

  // address/data decoder
  reg [10:0] regFreq;  // 0 -> 8191 (0x1fff)
  reg [ 3:0] regRes;   // 0 -> 15   (0xf)
  always @(posedge clk) begin
    if (iWE) begin
      case (iAddr)
        'h15: regFreq <= {regFreq[10:3], iData[2:0]};
        'h16: regFreq <= {iData[7:0], regFreq[2:0]};
        'h17: regRes  <= {iData[7:4]};
      endcase
    end
  end
endmodule
