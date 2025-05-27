#!/usr/bin/env bash
#
# generate_pgtune.sh
# Auto-generate a PostgreSQL tuning file (99pgtune.conf) for various use-cases,
# using integer MB/kB values so there are no fractional-GB tokens.

# Usage:
#   DB_TYPE=[web|oltp|dw|desktop|mixed] \
#   DB_VERSION=<major version: e.g. 9.6,10,11,...> \
#   TOTAL_MEMORY=<numeric> \
#   MEMORY_UNIT=[KB|MB|GB] \
#   CPU_COUNT=<number> \
#   CONNECTIONS=<number; optional> \
#   HD_TYPE=[ssd|hdd|san] \
#   ./generate_pgtune.sh

# If HD_TYPE is already set in the environment, respect it;
# otherwise auto-detect from /sys/block.
if [[ -z "${HD_TYPE:-}" ]]; then
  ROOT_FS_DEV=$(df --output=source / | tail -1)
  DEV_NAME=$(basename "$ROOT_FS_DEV" | sed 's/[0-9]\+$//')
  if [[ -r "/sys/block/$DEV_NAME/queue/rotational" ]]; then
    if [[ "$(cat /sys/block/$DEV_NAME/queue/rotational)" -eq 0 ]]; then
      DETECTED_HD_TYPE=ssd
    else
      DETECTED_HD_TYPE=hdd
    fi
  else
    DETECTED_HD_TYPE=ssd
  fi
  HD_TYPE="$DETECTED_HD_TYPE"
fi

echo "Using storage type: $HD_TYPE"

DB_TYPE="${DB_TYPE:-dw}"
DB_VERSION="${DB_VERSION:-${PG_MAJOR:-13}}"
TOTAL_MEMORY="${TOTAL_MEMORY:-$(awk '/MemTotal/ {print $2}' /proc/meminfo)}"
MEMORY_UNIT="${MEMORY_UNIT:-KB}"
CPU_COUNT="${CPU_COUNT:-$(nproc)}"
MAX_CONNECTIONS="${CONNECTIONS:-}"
HD_TYPE="${HD_TYPE:-ssd}"

# Convert TOTAL_MEMORY to kB
declare -A UNIT_TO_KB=( ["KB"]=1 ["MB"]=1024 ["GB"]=$((1024*1024)) )
TOTAL_MEM_KB=$(( TOTAL_MEMORY * UNIT_TO_KB[$MEMORY_UNIT] ))

# default max_connections by DB_TYPE
if [[ -z "$MAX_CONNECTIONS" ]]; then
  case "$DB_TYPE" in
    web)     MAX_CONNECTIONS=200 ;;
    oltp)    MAX_CONNECTIONS=300 ;;
    dw)      MAX_CONNECTIONS=40  ;;
    desktop) MAX_CONNECTIONS=20  ;;
    mixed)   MAX_CONNECTIONS=100 ;;
    *)       MAX_CONNECTIONS=100 ;;
  esac
fi

# Calculate shared_buffers (all in kB until we convert for output)
case "$DB_TYPE" in
  desktop)
    SB_KB=$(( TOTAL_MEM_KB / 16 )) ;;
  *)
    SB_KB=$(( TOTAL_MEM_KB / 4  )) ;;
esac

# On Windows (< v10), cap SB to 512MB
if [[ "$(uname -s)" == "MINGW"* || "$(expr "$DB_VERSION" \< 10)" -eq 1 ]]; then
  WIN_LIMIT_KB=$(( 512 * 1024 ))
  (( SB_KB > WIN_LIMIT_KB )) && SB_KB=$WIN_LIMIT_KB
fi

# effective_cache_size
case "$DB_TYPE" in
  desktop)
    EC_KB=$(( TOTAL_MEM_KB / 4 )) ;;
  *)
    EC_KB=$(( TOTAL_MEM_KB * 3 / 4 )) ;;
esac

# maintenance_work_mem
case "$DB_TYPE" in
  dw)      MW_KB=$(( TOTAL_MEM_KB / 8  )) ;;
  desktop) MW_KB=$(( TOTAL_MEM_KB / 16 )) ;;
  *)       MW_KB=$(( TOTAL_MEM_KB / 16 )) ;;
esac
# cap at 2GB
LIMIT_KB=$(( 2 * 1024 * 1024 ))
if (( MW_KB > LIMIT_KB )); then
  if [[ "$(uname -s)" == "MINGW"* ]]; then
    MW_KB=$(( LIMIT_KB - 1024 ))
  else
    MW_KB=$LIMIT_KB
  fi
fi

# checkpoint sizes (kB)
declare -A MIN_WAL_KB=( [web]=$((1024*1024)) [oltp]=$((2048*1024)) [dw]=$((4096*1024)) [desktop]=$((100*1024)) [mixed]=$((1024*1024)) )
declare -A MAX_WAL_KB=( [web]=$((4096*1024)) [oltp]=$((8192*1024)) [dw]=$((16384*1024)) [desktop]=$((2048*1024)) [mixed]=$((4096*1024)) )
MIN_WAL_KB=${MIN_WAL_KB[$DB_TYPE]}
MAX_WAL_KB=${MAX_WAL_KB[$DB_TYPE]}

# checkpoint_completion_target
CCT=0.9

# wal_buffers: 3% of shared_buffers, capped at 16MB, minimum 32kB; round up near 14MB→16MB
WB_KB=$(( SB_KB * 3 / 100 ))
MAX_WB_KB=$(( 16 * 1024 ))
(( WB_KB > MAX_WB_KB )) && WB_KB=$MAX_WB_KB
NEAR_KB=$(( 14 * 1024 ))
(( WB_KB > NEAR_KB && WB_KB < MAX_WB_KB )) && WB_KB=$MAX_WB_KB
(( WB_KB < 32 )) && WB_KB=32

# default_statistics_target
case "$DB_TYPE" in
  dw)      DST=500 ;;
  *)        DST=100 ;;
esac

# random_page_cost
case "$HD_TYPE" in
  hdd) rpg=4   ;;
  ssd) rpg=1.1 ;;
  san) rpg=1.1 ;;
esac

# effective_io_concurrency (Linux only)
if [[ "$(uname -s)" == "Linux" ]]; then
  case "$HD_TYPE" in
    hdd) eio=2   ;;
    ssd) eio=200 ;;
    san) eio=300 ;;
  esac
else
  eio=""
fi

# huge_pages
HPAGE=$(( TOTAL_MEM_KB >= 33554432 ? 1 : 0 ))  # 32GB in kB
HUGE_PAGES=$([[ $HPAGE -eq 1 ]] && echo "try" || echo "off")

# parallel settings
if (( CPU_COUNT >= 4 )); then
  # max_worker_processes
  MWP=$CPU_COUNT
  # workers_per_gather
  WPG=$(( (CPU_COUNT + 1) / 2 ))
  if [[ "$DB_TYPE" != "dw" && WPG -gt 4 ]]; then
    WPG=4
  fi
  PPWPG="$WPG"
  # max_parallel_workers
  MPW=$CPU_COUNT
  (( $(echo "$DB_VERSION < 10" | bc) == 1 )) && MPW=""
  # max_parallel_maintenance_workers (v11+)
  if (( $(echo "$DB_VERSION >= 11" | bc) == 1 )); then
    PMW=$(( (CPU_COUNT + 1) / 2 ))
    (( PMW > 4 )) && PMW=4
  else
    PMW=""
  fi
else
  MWP=""
  PPWPG=""
  MPW=""
  PMW=""
fi

# work_mem: (total - sb) / ((max_conn + max_workers) * 3), floor, then per-DB_TYPE fraction
PARALLEL_FOR_WM=${MWP:-1}
BASE_WM=$(( (TOTAL_MEM_KB - SB_KB) / ( (MAX_CONNECTIONS + PARALLEL_FOR_WM) * 3 ) ))
case "$DB_TYPE" in
  dw)      WM_KB=$(( BASE_WM / 2 )) ;;
  desktop) WM_KB=$(( BASE_WM / 6 )) ;;
  mixed)   WM_KB=$(( BASE_WM / 2 )) ;;
  *)       WM_KB=$BASE_WM      ;;
esac
(( WM_KB < 64 )) && WM_KB=64

# Write out to conf.d/99pgtune.conf if needed
# mkdir -p conf.d
# cat > conf.d/99pgtune.conf <<EOF
cat > 99pgtune.conf <<EOF
# Auto-generated pgtune settings for DB_TYPE=$DB_TYPE, DB_VERSION=$DB_VERSION
max_connections = ${MAX_CONNECTIONS}
shared_buffers = $(( SB_KB / 1024 ))MB
effective_cache_size = $(( EC_KB / 1024 ))MB
maintenance_work_mem = $(( MW_KB / 1024 ))MB
checkpoint_completion_target = ${CCT}
min_wal_size = $(( MIN_WAL_KB / 1024 ))MB
max_wal_size = $(( MAX_WAL_KB / 1024 ))MB
wal_buffers = $(( WB_KB / 1024 ))MB
default_statistics_target = ${DST}
random_page_cost = ${rpg}
effective_io_concurrency = ${eio}
work_mem = ${WM_KB}kB
huge_pages = ${HUGE_PAGES}
$( (( MWP )) && echo "max_worker_processes = ${MWP}" )
$( (( PPWPG )) && echo "max_parallel_workers_per_gather = ${PPWPG}" )
$( [[ -n "$MPW" ]] && echo "max_parallel_workers = ${MPW}" )
$( [[ -n "$PMW" ]] && echo "max_parallel_maintenance_workers = ${PMW}" )
EOF

echo "Generated 99pgtune.conf for DB_TYPE=${DB_TYPE}:"
echo "  shared_buffers = $(( SB_KB / 1024 ))MB"
echo "  effective_cache_size = $(( EC_KB / 1024 ))MB"
echo "  maintenance_work_mem = $(( MW_KB / 1024 ))MB"
echo "  wal_buffers = $(( WB_KB / 1024 ))MB"
echo "  work_mem = ${WM_KB}kB"
