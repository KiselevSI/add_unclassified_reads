#!/usr/bin/env bash
# add_unclassified_one.sh
#
# Добавляет строку "Unclassified" (U + missing) в ОДИН *.bracken.tsv
#
# usage:
#   ./add_unclassified_one.sh [-o out.tsv] <bracken.tsv> <kraken.report> <fastq …>
#
#   -o out.tsv   — имя выходного файла (по умолчанию <sample>.bracken_withU.tsv)
#
# пример:
#   ./add_unclassified_one.sh -o SRR34316421.fixed.tsv \
#       SRR34316421.bracken.tsv SRR34316421.kraken.report \
#       SRR34316421_1.fastq SRR34316421_2.fastq
#
set -euo pipefail

##### ─── опция -o ──────────────────────────────────────────────────
out=""
while getopts ":o:" opt; do
  case $opt in
    o) out=$OPTARG ;;
    \?) echo "❌ неизвестная опция -$OPTARG" >&2; exit 1 ;;
    :)  echo "❌ опция -$OPTARG требует аргумент" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

##### ─── позиционные аргументы ────────────────────────────────────
[[ $# -lt 2 ]] && {
  echo "Использование: $0 [-o out.tsv] <bracken.tsv> <kraken.report>" >&2
  exit 1
}
brk=$1; rpt=$2; shift 2


for f in "$brk" "$rpt"; do
  [[ -f $f ]] || { echo "❌ файл '$f' не найден" >&2; exit 1; }
done
sample=${brk%.bracken.tsv}
[[ -z $out ]] && out="${sample}.bracken_withU.tsv"

##### ─── 1. полное число ридов (seqkit) ───────────────────────────

read root unc2 < <(
  awk -F'\t' '
    $4=="R" {gsub(/,/,"",$2); root=$2}       # строка ранга R (root)
    $4=="U" {gsub(/,/,"",$2); uncl=$2}       # строка ранга U
    END {print root, uncl}
  ' "$rpt"
)

total=$(( root + unc2 ))  

##### ─── 2. неклассифицированные Kraken-ом ────────────────────────
unc=$(awk '$4=="U"{gsub(/,/,""); print $2}' "$rpt")

##### ─── 3. классифицированные Bracken-ом ─────────────────────────
cla=$(awk -F'\t' '{sum+=$6} END{print sum}' "$brk")

##### ─── 4. потерянные (undistributed) ────────────────────────────
miss=$(( total - cla - unc ))
[[ $miss -lt 0 ]] && { echo "⚠️ отрицательный miss ($miss) – проверьте входные данные" >&2; miss=0; }

##### ─── 5. объединяем всё в Unclassified ────────────────────────
unc_total=$(( unc + miss ))
frac_unc=$(awk -v u="$unc_total" -v t="$total" 'BEGIN{printf "%.6f", u/t}')

##### ─── 6. формируем файл ────────────────────────────────────────
{
  cat "$brk"
  printf "Unclassified\t0\tS\t0\t0\t%s\t%s\n" "$unc_total" "$frac_unc"
} > "$out"

##### ─── 7. отчёт ─────────────────────────────────────────────────
printf "✅ %s создан\n" "$out"
printf "   total              : %'d\n" "$total"
printf "   unclassified+miss  : %'d (%.2f%%)\n" \
       "$unc_total" "$(awk -v x=$unc_total -v t=$total 'BEGIN{print 100*x/t}')"
printf "   miss              : %'d\n" "$miss"
printf "   unc              : %'d\n" "$unc"
printf "   cla              : %'d\n" "$cla"
