#pragma once
#include <cstdint>

typedef int32_t fc_point[2];

static const fc_point f0_points_6581[] = {
  //  FC      f         FCHI FCLO
  // ----------------------------
  {    0,   220 },   // 0x00      - repeated end point
  {    0,   220 },   // 0x00
  {  128,   230 },   // 0x10
  {  256,   250 },   // 0x20
  {  384,   300 },   // 0x30
  {  512,   420 },   // 0x40
  {  640,   780 },   // 0x50
  {  768,  1600 },   // 0x60
  {  832,  2300 },   // 0x68
  {  896,  3200 },   // 0x70
  {  960,  4300 },   // 0x78
  {  992,  5000 },   // 0x7c
  { 1008,  5400 },   // 0x7e
  { 1016,  5700 },   // 0x7f
  { 1023,  6000 },   // 0x7f 0x07
  { 1023,  6000 },   // 0x7f 0x07 - discontinuity
  { 1024,  4600 },   // 0x80      -
  { 1024,  4600 },   // 0x80
  { 1032,  4800 },   // 0x81
  { 1056,  5300 },   // 0x84
  { 1088,  6000 },   // 0x88
  { 1120,  6600 },   // 0x8c
  { 1152,  7200 },   // 0x90
  { 1280,  9500 },   // 0xa0
  { 1408, 12000 },   // 0xb0
  { 1536, 14500 },   // 0xc0
  { 1664, 16000 },   // 0xd0
  { 1792, 17100 },   // 0xe0
  { 1920, 17700 },   // 0xf0
  { 2047, 18000 },   // 0xff 0x07
  { 2047, 18000 }    // 0xff 0x07 - repeated end point
};

static const fc_point f0_points_8580[] = {
  //  FC      f         FCHI FCLO
  // ----------------------------
  {    0,     0 },   // 0x00      - repeated end point
  {    0,     0 },   // 0x00
  {  128,   800 },   // 0x10
  {  256,  1600 },   // 0x20
  {  384,  2500 },   // 0x30
  {  512,  3300 },   // 0x40
  {  640,  4100 },   // 0x50
  {  768,  4800 },   // 0x60
  {  896,  5600 },   // 0x70
  { 1024,  6500 },   // 0x80
  { 1152,  7500 },   // 0x90
  { 1280,  8400 },   // 0xa0
  { 1408,  9200 },   // 0xb0
  { 1536,  9800 },   // 0xc0
  { 1664, 10500 },   // 0xd0
  { 1792, 11000 },   // 0xe0
  { 1920, 11700 },   // 0xf0
  { 2047, 12500 },   // 0xff 0x07
  { 2047, 12500 }    // 0xff 0x07 - repeated end point
};

static const double f0_6581_approx(double x) {

  // 6th order polynomial aproximation
  //
  // because of the lower order of this curve it does not exhibit any
  // discontinuities.

  const double A = 200.17233570154443;
  const double B =   1.969703033388254;
  const double C =  -0.011122031244297738;
  const double D =   0.00001405092015559062;
  const double E =   0.000000006810684246034039;
  const double F =  -0.000000000009139136228824852;
  const double G =   0.0000000000000020211640198279443;

  return A +
         B * x +
         C * x*x +
         D * x*x*x +
         E * x*x*x*x +
         F * x*x*x*x*x +
         G * x*x*x*x*x*x;
}
