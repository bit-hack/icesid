#define _CRT_SECURE_NO_WARNINGS
#include <cmath>
#include <cstdio>

#include "filter.h"
#include "spline.h"
#include "dac.h"

static double PI           = 3.14159265359;
static double SID_CLK_PAL  = 985248.0;
static double SID_CLK_NTSC = 1022727.0;

// frequency to filter coefficient
static double filter_coef(double freq) {
  return 2.0 * sin(PI * freq / SID_CLK_NTSC);
}

// write arbitary data to a hex file
template <typename type_t, bool hex=true>
static void write_table(const char *name, const type_t *data, uint32_t count) {
    // open output file
    FILE *fd = fopen(name, "w");
    if (!fd) {
      fprintf(stderr, "Unable to generate '%s'!\n", name);
      return;
    }
    // write out all coefficients
    for (; count--; ++data) {
      fprintf(fd, hex ? "%04x\n" : "%u\n", uint32_t(*data));
    }
    // close output file
    fclose(fd);
}

// write out a filter coefficient lookup table
static void write_filter_table(const char *name, const int32_t *f, uint32_t count) {
  // open output file
  FILE *fd = fopen(name, "w");
  if (!fd) {
    fprintf(stderr, "Unable to generate '%s'!\n", name);
    return;
  }
  // write out all coefficients
  for (; count--; ++f) {
    uint32_t coef = uint32_t(filter_coef(double(*f)) * 65536.0);
    fprintf(fd, "%04x\n", coef);
  }
  // close output file
  fclose(fd);
}

// generate both 6581 and 8580 filter coefficient lookup tables
static void gen_filter_tables(void) {

  // note: the filter curves and interpolation code are taken from reSID-0.16

  static const size_t points = 2048;

  static int32_t f0_6581[points];
  static int32_t f0_8580[points];

  interpolate(
    f0_points_6581,
    f0_points_6581 + sizeof(f0_points_6581) / sizeof(*f0_points_6581) - 1,
    PointPlotter<int32_t>(f0_6581),
    1.0);

  interpolate(
    f0_points_8580,
    f0_points_8580 + sizeof(f0_points_8580) / sizeof(*f0_points_8580) - 1,
    PointPlotter<int32_t>(f0_8580),
    1.0);

  write_filter_table("curve_6581.hex", f0_6581, points);
  write_filter_table("curve_8580.hex", f0_8580, points);
}

static void gen_dac_tables() {

  // note: dac.h was taken from Dag Lem's reSID WIP e2ed92c 24/05/22

  reSID::DAC<12> dac12{ 2.2, false };
  write_table<uint16_t>("dac12.hex", dac12.dac_bits, 12);

  uint16_t ref12[4096];
  for (uint32_t i = 0; i < 4096; ++i) {
    ref12[i] = dac12(i);
  }
  write_table<uint16_t, false>("dac12_ref.txt", ref12, 4096);

  reSID::DAC<8>  dac8 { 2.2, false };
  write_table<uint16_t>("dac8.hex", dac8.dac_bits, 8);

  uint16_t ref8[256];
  for (uint32_t i = 0; i < 256; ++i) {
    ref8[i] = dac8(i);
  }
  write_table<uint16_t, false>("dac8_ref.txt", ref8, 256);
}

int main(int argc, char **args) {

  // generate filter coefficient lookup tables
  gen_filter_tables();

  // generate DAC tables
  gen_dac_tables();

  return 0;
}
