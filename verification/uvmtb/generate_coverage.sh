#!/bin/bash
set -e
SIM=simv

vcs -full64 ../../rtl/*.sv testbench_top.sv -cm line+tgl+cond+fsm && ./simv -cm line+tgl+cond+fsm
ucd report ucdb ucdb/formal.ucdb
