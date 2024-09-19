#!/bin/sh
prog=$0

usage() {
    echo "Usage $prog (no)io (no)llc lat"
    exit 1
}

if [ "$1" == "" ]; then
    usage
fi
io="$1"
if [ "$2" == "" ]; then
    usage
fi
llc="$2"
if [ "$3" == "" ]; then
    usage
fi
lat=$3

outputdir=$(date "+%H%M%S")

rm -rf $outputdir
mkdir -p $outputdir

for k in 0
do
for s in 0
do
    length=65536
    echo -- $length -- >> $outputdir/ms_${io}_${llc}_${lat}.out
    ./merge_sort_snitch_cluster.elf $length 0 >> $outputdir/ms_${io}_${llc}_${lat}.out
    tail -n 17 $outputdir/ms_${io}_${llc}_${lat}.out

    length=512
    echo -- $length -- >> $outputdir/gesummv_${io}_${llc}_${lat}.out
    ./gesummv_snitch_cluster.elf $length $length >> $outputdir/gesummv_${io}_${llc}_${lat}.out
    tail -n 17 $outputdir/gesummv_${io}_${llc}_${lat}.out

    length=128
    echo -- $length -- >> $outputdir/gemm_${io}_${llc}_${lat}.out
    ./gemm_snitch_cluster.elf $length $length $length >> $outputdir/gemm_${io}_${llc}_${lat}.out
    tail -n 17 $outputdir/gemm_${io}_${llc}_${lat}.out

    length=64
    echo -- $length -- >> $outputdir/h3d_${io}_${llc}_${lat}.out
    ./heat3d_snitch_cluster.elf $length $length $length 2 >> $outputdir/h3d_${io}_${llc}_${lat}.out
    tail -n 17 $outputdir/h3d_${io}_${llc}_${lat}.out

done
done

sz $outputdir/*
