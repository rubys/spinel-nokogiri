#!/bin/sh
# Oracle harness: run the conformance test under CRuby with the REAL
# nokogiri gem and diff against the committed snapshot. No -I, so
# `require "nokogiri"` resolves to the gem, not this package: the snapshot
# is what the gem answers, and `spin test` holds the compiled port to it.
# Zero hand-authored expectations; a diff on either side is a contract
# divergence.
#
# Usage: sh oracle/run.sh          (from the repo root)
# Needs: ruby with the nokogiri gem (gem install nokogiri -v 1.19.4).
#

OUTDIR=build/oracle
mkdir -p "$OUTDIR"
fails=0
ran=0
for t in test/*_test.rb; do
  name=$(basename "$t" .rb)
  ruby "$t" > "$OUTDIR/$name.out" 2>&1
  ran=$((ran + 1))
  if diff -u "$t.expected" "$OUTDIR/$name.out" > "$OUTDIR/$name.diff" 2>&1; then
    echo "ok   $name"
    rm -f "$OUTDIR/$name.diff"
  else
    echo "FAIL $name (see $OUTDIR/$name.diff)"
    fails=$((fails + 1))
  fi
done
echo "$((ran - fails))/$ran match nokogiri"
[ $fails -eq 0 ]

