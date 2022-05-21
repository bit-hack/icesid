cmake_minimum_required(VERSION 3.0)
project(icesid)

find_package(verilator HINTS $ENV{VERILATOR_ROOT} ${VERILATOR_ROOT})
if (NOT verilator_FOUND)
  message(FATAL_ERROR "Verilator not found. Set VERILATOR_ROOT env var.")
endif()

add_executable(icesid verilator/icesid.cpp verilator/csid-light.c)

file(GLOB VLG_SRC icesid/*.v)

verilate(icesid
  SOURCES ${VLG_SRC} verilator/ice40.v
  TOP_MODULE sid
  PREFIX Vsid
  TRACE
  VERILATOR_ARGS 
)
