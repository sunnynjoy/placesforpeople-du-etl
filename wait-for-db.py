#!/usr/bin/env python

import subprocess
import time
import sys
import os

host = sys.argv[1]
user = sys.argv[2]
password = sys.argv[3]
database = sys.argv[4]

print("Waiting for postgres to be ready...")

while True:
    try:
        result = subprocess.run(
            ["psql", "-h", host, "-U", user, "-d", database, "-c", "SELECT 1"],
            env={**os.environ, "PGPASSWORD": password},
            capture_output=True,
            timeout=5
        )
        if result.returncode == 0:
            print("Postgres is up - executing pipeline")
            break
    except Exception as e:
        pass

    print("Postgres is unavailable - sleeping")
    time.sleep(1)

# Run ETL
subprocess.run(["python", "-m", "src.etl"])