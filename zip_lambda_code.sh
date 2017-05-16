#!/bin/bash
# Zip the lambda content to the zip directory.

set -e

cd lambda_code

archive_file="../dist/scheduled_task.zip"

zip -vr --exclude=*.pyc "${archive_file}" .

echo ""
echo "Successfully re-created zip file."
