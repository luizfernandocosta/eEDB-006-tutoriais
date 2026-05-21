#!/bin/bash
set -e

echo "============================================"
echo " Hadoop WordCount Tests"
echo "============================================"
echo ""

echo "--- Test 1: Built-in WordCount (XML files) ---"
echo ""

echo "[1/5] Creating HDFS directories..."
hdfs dfs -mkdir -p /user/hduser/input

echo "[2/5] Uploading sample data to HDFS..."
hdfs dfs -put -f $HADOOP_HOME/etc/hadoop/*.xml /user/hduser/input

echo "[3/5] Running built-in WordCount MapReduce job..."
hdfs dfs -rm -r -f /user/hduser/output 2>/dev/null || true
hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar wordcount /user/hduser/input /user/hduser/output

echo "[4/5] Listing output files..."
hdfs dfs -ls /user/hduser/output

echo "[5/5] Built-in WordCount results (top 20):"
echo "---"
hdfs dfs -cat /user/hduser/output/part-r-00000 | head -20
echo "..."
echo ""

echo "--- Test 2: Custom Java WordCount (lorem.txt) ---"
echo ""

/home/hduser/run-custom-wordcount.sh
