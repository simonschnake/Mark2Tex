#!/bin/sh
set -eu

version=$1
destination=$2
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
work=$(mktemp -d "$destination/bootstrap.XXXXXX")
trap 'rm -rf "$work"' EXIT

cd "$work"
luarocks unpack "https://luarocks.org/tl-$version-1.src.rock"
luarocks unpack https://luarocks.org/argparse-0.7.1-1.src.rock

cp "tl-$version-1/tl/tl.lua" "$destination/tl.lua"
cp argparse-0.7.1-1/argparse-0.7.1/src/argparse.lua "$destination/argparse.lua"
{
    printf '%s\n' 'local script_dir = arg[0]:match("^(.*[/])") or "./"' \
        'package.path = script_dir .. "?.lua;" .. package.path'
    sed '1{/^#!/d;}' "tl-$version-1/tl/tl"
} > "$work/tl"
mv "$work/tl" "$destination/tl"
