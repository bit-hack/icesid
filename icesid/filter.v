`default_nettype none

// 16x16 multiplier for the filter
module mult(
    input                CLK,
    input signed  [16:0] iSignal,
    input         [15:0] iCoef,
    output signed [15:0] oOut
    );

  wire signed [31:0] product;          // 16x16 product
  assign oOut = product[31:16];

  wire signed [15:0] clipped;
  clipper clip(iSignal, clipped);

  SB_MAC16 mac(
    .A(clipped),
    .B(iCoef),
    .O(product),
    .CLK(CLK));

  defparam mac.A_SIGNED = 1'b1;             // input is signed
  defparam mac.B_SIGNED = 1'b0;             // coefficient is unsigned
  defparam mac.TOPOUTPUT_SELECT = 2'b11;    // Mult16x16 data output
  defparam mac.BOTOUTPUT_SELECT = 2'b11;    // Mult16x16 data output
endmodule

module filter(
    input clk,
    input clkEn,
    input signed [15:0] iIn,

    input WR,            // data write
    input [4:0] ADDR,    // address bus
    input [7:0] DATA,    // data bus

    output signed [15:0] oLP,
    output signed [15:0] oBP,
    output signed [15:0] oHP
    );

  reg signed [16:0] low;
  reg signed [16:0] high;
  reg signed [16:0] band;

  clipper oLPClipper(low,  oLP);
  clipper oBPClipper(band, oBP);
  clipper oHPClipper(high, oHP);

  reg [15:0] fCurve[2048];
  initial begin
    // load in the coefficient table
    $readmemh("curve_6581.hex", fCurve);
  end

  // filter coefficient is calculated as follows:
  //
  //    coef = 2 * sin( pi * freq / sid_clock_rate ) * 0x10000
  //
  reg [15:0] cutCoef;

  // filter cutoff smothing filter
  reg [15:0] cutCoefLag0;
  reg [15:0] cutCoefLag1;

  // note: the resonance coefficient is backwards and increases resonance
  //       as it aproaches zero. this is currently arbitaraly mapped
  //       into a useable range but should be tuned in the future.
  wire [15:0] resCoef = 16'hbfff - (reg_res << 11);

  // 16x16 multiplier
  reg  signed [16:0] mulA;
  reg         [15:0] mulB;
  wire signed [15:0] mulOut;
  mult mul(clk, mulA, mulB, mulOut);

  initial begin
    state       = 7;
    low         = 0;
    high        = 0;
    band        = 0;
    mulA        = 0;
    mulB        = 0;
    cutCoefLag0 = 0;
    cutCoefLag1 = 0;
  end

  // find the filter coefficient for the frequency register
  always @(posedge clk) begin
    cutCoef <= fCurve[reg_freq];

    // very simple filter to smooth the cutoff control to reduce pops with
    // fast changes.
    if (clkEn) begin
      cutCoefLag0 <= (cutCoefLag0 + cutCoef    ) >> 1;
      cutCoefLag1 <= (cutCoefLag1 + cutCoefLag0) >> 1;
    end
  end

  // note: due to the registering of the multiplier inputs some extra
  //       wait states had to be added to the state machine. this should
  //       be fixed as its ugly.

  // note: this filter uses 0:16 fixed point format and thus has no extra
  //       headroom from the main 16bit audio path. large resonance values
  //       can and will cause it to clip. we should use saturating arithetic
  //       here so its not so harsh.

  // note: the output of each filter mode is delayed by a number of cycles
  //       from each other which would cause the sum of multiple modes to
  //       be inaccurate. this should be fixed.

  // note: quick changes in cutoff can cause the filter to pop, and thus
  //       some form of smoohing should be used to reduce this.

/*
  // multiplier lookahead
  always @(*) begin
    case (state)
    0: begin
      mulA <= band;
      mulB <= resCoef;
    end
    1: begin
      mulA <= high;
      mulB <= cutCoef;
    end
    default:
      mulA <= band;
      mulB <= cutCoef;
    end
    endcase
  end
*/

  reg [2:0] state;
  always @(posedge clk) begin
    if (clkEn) begin
      mulA  <= band;
      mulB  <= cutCoefLag1;
      state <= 0;
    end else begin
      case (state)
      0: state <= 1;                    // delay - fixme
      1: begin
        low   <= low + mulOut;          // low + (cutoff * band)
        mulA  <= band;
        mulB  <= resCoef;
        state <= 2;
      end
      2: state <= 3;                    // delay - fixme
      3: begin
        high  <= iIn - low - mulOut;    // in - low - (res * band)
        mulA  <= high;
        mulB  <= cutCoefLag1;
        state <= 4;
      end
      4: state <= 5;                    // delay - fixme
      5: begin
        band  <= band + mulOut;         // band + (cutoff * High)
        state <= 6;
      end
      endcase
    end
  end

  // address/data decoder
  reg [10:0] reg_freq;
  reg [ 3:0] reg_res;
  always @(posedge clk) begin
    if (WR) begin
      case (ADDR)
      'h15: begin reg_freq <= { reg_freq[10:3], DATA[2:0] }; end
      'h16: begin reg_freq <= { DATA[7:0], reg_freq[2:0] };  end
      'h17: begin reg_res  <= { DATA[7:4] };                 end
      endcase
    end
  end
endmodule
