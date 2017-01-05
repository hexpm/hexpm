#!/bin/bash

set -e

host="$1"
pw="$2"

until PGPASSWORD="$pw" psql -h "$host" -U "postgres" -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done
