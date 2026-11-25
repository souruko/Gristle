#!/bin/sh
# Run the Gristle suite as both an English client and a German/French one.
#
# The euro pass matters because those clients cannot round-trip numbers through the savefile
# serialiser, so every number is stringified on the way in and turned back on the way out -- a
# whole second code path through load, normalise and save.
#
#   cd Gristle && sh tests/run_all.sh

set -e

LUA=${LUA:-lua5.1}

echo "--- English client ---"
$LUA tests/run.lua
$LUA tests/legacy.lua

echo
echo "--- German / French client ---"
$LUA tests/run.lua euro
$LUA tests/legacy.lua euro

echo
echo "both locales pass"
