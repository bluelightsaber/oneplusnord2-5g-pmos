# Read host WFDMA0/1 registers directly via /dev/mem with devmem2 (phys 0x18024000 / 0x18025000 = chip 0x7c024000 / 0x7c025000)
r() { printf "%s " "$(devmem2 $(printf 0x%x $1) w 2>/dev/null | sed -n 's/.*: \(0x[0-9A-Fa-f]*\)$/\1/p')"; }
for b in $((0x18024000)) $((0x18025000)); do
  echo "== $(printf 0x%x $b) INT_STA INT_MASK GLO_CFG: $(r $((b+0x200)); r $((b+0x204)); r $((b+0x208)))"
  for t in 0 1 2 16 17; do o=$((b+0x300+t*16)); echo "TX$t base/cnt/cidx/didx: $(r $o; r $((o+4)); r $((o+8)); r $((o+12)))"; done
  for x in 0 1 2 3; do o=$((b+0x500+x*16)); echo "RX$x base/cnt/cidx/didx: $(r $o; r $((o+4)); r $((o+8)); r $((o+12)))"; done
done
