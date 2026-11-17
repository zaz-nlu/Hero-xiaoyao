#!/bin/bash
# 校验：1) 全部测试通过  2) 小镇场景 headless 运行几帧没有任何 SCRIPT ERROR / Parse Error
cd "$(dirname "$0")/.." || exit 9
G='D:/godot/Godot_v4.7.2-stable_win64_console.exe'
OUT1=$(timeout 280 "$G" --headless --path godot -s res://tests/run_tests.gd 2>&1)
RC1=$?
echo "$OUT1" | grep -E "FAIL|PASS [0-9]|SCRIPT ERROR|Parse Error" | head -40
if [ $RC1 -ne 0 ]; then echo "CHECK FAILED: tests rc=$RC1"; exit 1; fi
if echo "$OUT1" | grep -qE "SCRIPT ERROR"; then echo "CHECK FAILED: SCRIPT ERROR during tests"; exit 1; fi
OUT2=$(timeout 120 "$G" --headless --path godot res://world/town.tscn --quit-after 5 2>&1)
RC2=$?
if echo "$OUT2" | grep -qE "SCRIPT ERROR|Parse Error"; then
  echo "$OUT2" | grep -E "SCRIPT ERROR|Parse Error|   at:" | sort | uniq -c | sort -rn | head -20
  echo "CHECK FAILED: town scene has script errors"; exit 1
fi
if [ $RC2 -ne 0 ]; then echo "CHECK FAILED: town scene rc=$RC2"; exit 1; fi
OUT5=$(timeout 120 "$G" --headless --path godot res://world/tavern.tscn --quit-after 5 2>&1)
RC5=$?
if echo "$OUT5" | grep -qE "SCRIPT ERROR|Parse Error"; then
  echo "$OUT5" | grep -E "SCRIPT ERROR|Parse Error|   at:" | sort | uniq -c | sort -rn | head -20
  echo "CHECK FAILED: tavern scene has script errors"; exit 1
fi
if [ $RC5 -ne 0 ]; then echo "CHECK FAILED: tavern scene rc=$RC5"; exit 1; fi
OUT3=$(timeout 120 "$G" --headless --path godot --quit-after 5 2>&1)
RC3=$?
if echo "$OUT3" | grep -qE "SCRIPT ERROR|Parse Error"; then
  echo "$OUT3" | grep -E "SCRIPT ERROR|Parse Error|   at:" | sort | uniq -c | sort -rn | head -20
  echo "CHECK FAILED: main scene has script errors"; exit 1
fi
if [ $RC3 -ne 0 ]; then echo "CHECK FAILED: main scene rc=$RC3"; exit 1; fi
OUT4=$(timeout 120 "$G" --headless --path godot -s res://tools/smoke_game.gd 2>&1)
RC4=$?
echo "$OUT4" | grep -E "SMOKE|SCRIPT ERROR" | head -5
if [ $RC4 -ne 0 ] || echo "$OUT4" | grep -qE "SCRIPT ERROR"; then echo "CHECK FAILED: game smoke test"; exit 1; fi
echo "CHECK OK"
exit 0
