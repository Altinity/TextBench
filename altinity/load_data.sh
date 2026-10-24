#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 6 || $# -gt 8 ]]; then
    echo "Usage: $0 <DATA_DIRECTORY> <DB_NAME> <TABLE_NAME> <MAX_FILES> <SUCCESS_LOG> <ERROR_LOG> [PARALLEL_WORKERS]"
    echo
    echo "Remote Altinity Cloud connection (optional env vars):"
    echo "  export FQDN=<host>        e.g. wjgkgcnnmt.us-east-2.aws.altinity.cloud"
    echo "  export PASSWORD=<password>"
    echo "  export CH_USER=<user>     (default: default)"
    exit 1
fi

DATA_DIRECTORY="$1"
DB_NAME="$2"
TABLE_NAME="$3"
MAX_FILES="$4"
SUCCESS_LOG="$5"
ERROR_LOG="$6"
PARALLEL_WORKERS="${7:-1}"
ORIGINAL="${8:-0}"

[[ ! "$MAX_FILES" =~ ^[0-9]+$ ]] && { echo "Error: MAX_FILES must be a positive integer."; exit 1; }
[[ ! "$PARALLEL_WORKERS" =~ ^[0-9]+$ ]] && { echo "Error: PARALLEL_WORKERS must be a positive integer."; exit 1; }
[[ "$PARALLEL_WORKERS" -lt 1 ]] && { echo "Error: PARALLEL_WORKERS must be >= 1."; exit 1; }

# ---------------------------------------------------------------------------
# Build ClickHouse connection flags.
# When FQDN and PASSWORD are set, connect to ClickHouse Cloud over TLS.
# Otherwise fall back to the default localhost connection.
# ---------------------------------------------------------------------------
CH_OPTS=()

PART_SIZE_ROWS=5000000
PART_SIZE_BYTES=5000000000 

if [[ "$ORIGINAL" -eq 1 ]]; then
   PART_SIZE_ROWS=2000000
   PART_SIZE_BYTES=2000000000
fi

if [[ -n "${FQDN:-}" && -n "${PASSWORD:-}" ]]; then
    CH_USER="${CH_USER:-default}"
    CH_OPTS=(
        --host="$FQDN"
        --user="$CH_USER"
        --password="$PASSWORD"
        --secure
        --enable_full_text_index=1
        --max_insert_threads=6
        --input_format_parquet_use_native_reader_v3=0
        --min_insert_block_size_bytes=$PART_SIZE_BYTES
        --max_insert_block_size_bytes=$PART_SIZE_BYTES
        --min_insert_block_size_rows=$PART_SIZE_ROWS
        --max_insert_block_size_rows=$PART_SIZE_ROWS
        --materialize_skip_indexes_on_insert=0
    )
fi

touch "$SUCCESS_LOG" "$ERROR_LOG"

echo "=== Load started at $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Database:         $DB_NAME"
echo "Table:            $TABLE_NAME"
echo "Data directory:   $DATA_DIRECTORY"
echo "Max files:        $MAX_FILES"
echo "Parallel workers: $PARALLEL_WORKERS"
if [[ ${#CH_OPTS[@]} -gt 0 ]]; then
    echo "Target:           ${CH_USER:-default}@${FQDN} (secure)"
else
    echo "Target:           localhost (default)"
fi
echo


completed=0
failed=0

load_one_file() {
    local file="$1"

    echo "[$(date '+%H:%M:%S')] START  $file"

    if clickhouse client "${CH_OPTS[@]}" \
        --async_insert=0 \
        --query "INSERT INTO ${DB_NAME}.${TABLE_NAME} SELECT * EXCEPT 'TimestampTime' FROM s3('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_0${file}.parquet', NOSIGN)";
    then
        echo "[$(date '+%H:%M:%S')] DONE   $file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully imported $file." >> "$SUCCESS_LOG"
        return 0
    else
        echo "[$(date '+%H:%M:%S')] FAIL   $file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Import failed for $file." >> "$ERROR_LOG"
        return 1
    fi
}

# Export so subshells spawned by & can see CH_OPTS
export -f load_one_file
export CH_OPTS DB_NAME TABLE_NAME SUCCESS_LOG ERROR_LOG

for file in $(seq -w 00 $((MAX_FILES - 1))); do
    load_one_file "$file" &

    while [[ $(jobs -p -r | wc -l) -ge $PARALLEL_WORKERS ]]; do
        if wait -n; then
            completed=$((completed + 1))
        else
            failed=$((failed + 1))
        fi
        echo "Progress: $completed completed, $failed failed"
    done
done

while [[ $(jobs -p -r | wc -l) -gt 0 ]]; do
    if wait -n; then
        completed=$((completed + 1))
    else
        failed=$((failed + 1))
    fi
    echo "Progress: $completed completed, $failed failed"
done

echo
echo "=== Load finished at $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Total files: ${MAX_FILES}"
echo "Completed:   $completed"
echo "Failed:      $failed"
