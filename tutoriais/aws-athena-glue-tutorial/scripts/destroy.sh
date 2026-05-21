#!/bin/bash
set -e

echo "=== Tutorial AWS Athena + Glue - Destroy Script ==="
echo ""

BUCKET="${BUCKET:-$(terraform output -raw s3_bucket 2>/dev/null || echo "leandro-athena-lab")}"
DATABASE="athena_lab"
REGION="us-east-1"

echo "Bucket: $BUCKET"
echo "Database: $DATABASE"
echo "Region: $REGION"
echo ""

echo "[1/4] Deleting Glue tables..."
for table in clientes produtos vendas resultado_vendas; do
    echo "  Deleting table: $table"
    aws glue delete-table \
        --database-name "$DATABASE" \
        --name "$table" \
        --region "$REGION" \
        2>/dev/null || echo "    (Table may not exist, skipping)"
done

echo ""
echo "[2/4] Deleting Glue database..."
aws glue delete-database \
    --name "$DATABASE" \
    --region "$REGION" \
    2>/dev/null || echo "  (Database may not exist, skipping)"

echo ""
echo "[3/4] Destroying Terraform resources..."
cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve 2>/dev/null || echo "  (Terraform destroy completed with some warnings)"

echo ""
echo "[4/4] Verifying cleanup..."
echo "  S3 buckets remaining:"
aws s3 ls 2>/dev/null | grep athena-lab || echo "    No athena-lab buckets found"
echo "  Glue databases remaining:"
aws glue get-databases --region "$REGION" 2>/dev/null | grep Name || echo "    No databases found"

echo ""
echo "=== Destroy complete ==="