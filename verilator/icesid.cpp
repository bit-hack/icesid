#include <cstdint>
#include <cstdio>

#include "verilated.h"
#include "Vsid.h"
#include "Vsid___024root.h"

#include <queue>


static const bool trace = true;

static Vsid *rtl;
static std::queue<std::pair<uint16_t, uint8_t>> writes;
static uint32_t time;

static int64_t seconds = 60 * 2;
static int64_t timeout = 1000000 * seconds;

FILE *outFile;

double sc_time_stamp() {
  return double(time);
}

extern "C" {
extern void icesid_write      (uint8_t sid_reg, uint8_t addr);
extern void icesid_cpu_clock  (uint32_t clocks);
extern void icesid_init       (int argc, char **args);
extern int  icesid_should_stop(void);
extern void icesid_finish     (void);
extern void icesid_reference  (int16_t sample);
extern void icesid_model      (int is6581);
}  // extern "C"

struct biquad {

  biquad(float b0, float b1, float b2, float a1, float a2)
    : b0(b0), b1(b1), b2(b2), a1(a1), a2(a2)
    , t0(.0f), t1(.0f), t2(.0f), t3(.0f)
  {
  }

  const float b0, b1, b2, a1, a2;
  float t0, t1, t2, t3;
};

// 1Mhz sample rate, 22050 cutoff
static biquad bq0{ 0.004949567490326946f, 0.009899134980653892f, 0.004949567490326946f, 1.75670035983922f,   -0.7736957551969215f };
static biquad bq1{ 0.00390625f,           0.0078125f,            0.00390625f,           1.8814055219615045f, -0.8996073914464207f };

static float filter(biquad *bq, float in) {

  float x0 = in;
  float x1 = bq->t0;
  float x2 = bq->t1;
  float y1 = bq->t2;
  float y2 = bq->t3;

  float ac = x2 * bq->b2;
  ac += x1 * bq->b1;
  ac += x0 * bq->b0;

  x2 = x1;
  x1 = x0;

  ac += y2 * bq->a2;
  ac += y1 * bq->a1;

  y2 = y1;
  y1 = ac;

  bq->t0 = x1;
  bq->t1 = x2;
  bq->t2 = y1;
  bq->t3 = y2;

  return ac;
}

static float noise() {
  static uint32_t x = 12345;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  return .5f - float( x & 0xffff ) / float( UINT16_MAX );
}

void icesid_model(int is6581) {
  rtl->rootp->sid__DOT__regIs6581 = is6581;
}

void icesid_write(uint8_t sid_reg, uint8_t value) {
  writes.push(std::pair<uint16_t, uint8_t>(sid_reg, value));
}

static void cycle() {
  rtl->clk = 0;
  rtl->eval();
  Verilated::timeInc(1);
  rtl->clk = 1;
  rtl->eval();
  Verilated::timeInc(1);
}

void icesid_reference(int16_t sample) {
  fwrite(&sample, 1, 2, outFile);
}

// CPU clocks at 0.985 Mhz
// Sid also clocks at the same rate
void icesid_cpu_clock(uint32_t clocks) {

  timeout -= clocks;

  float filtered = 0.f;

  while (clocks--) {

    if (!writes.empty()) {
      std::pair<uint16_t, uint8_t> write = writes.front();
      writes.pop();

      rtl->iAddr = write.first;
      rtl->iDataW = write.second;
      rtl->iWE = 1;
    }

    rtl->clkEn = 1;
    cycle();

    // run the filter
    const float sample = float(int16_t(rtl->oOut));
    filtered = filter(&bq1, filter(&bq0, sample));

    // deassert write enable
    rtl->iWE = 0;
    rtl->clkEn = 0;

    // non clock enable cycles
    // 8 cycles minimum for the DAC model to complate
    for (int i = 0; i < 10; ++i) {
      cycle();
    }
  }

  // write output to file
  if (outFile) {

    // clip
    int32_t s = int32_t(filtered + noise());
    if (s >= INT16_MAX) s = INT16_MAX;
    if (s <= INT16_MIN) s = INT16_MIN;

    const int16_t sample = int16_t(s);
    fwrite(&sample, 1, 2, outFile);
  }
}

void icesid_init(int argc, char **args) {
  Verilated::commandArgs(argc, args);
  if (trace) {
    Verilated::traceEverOn(true);
  }

  outFile = fopen("output.bin", "wb");

  rtl = new Vsid;
}

int icesid_should_stop(void) {
  return timeout <= 0;
}

void icesid_finish(void) {
  if (outFile) {
    fclose(outFile);
    outFile = nullptr;
  }

  if (rtl) {
    delete rtl;
    rtl = nullptr;
  }
}
