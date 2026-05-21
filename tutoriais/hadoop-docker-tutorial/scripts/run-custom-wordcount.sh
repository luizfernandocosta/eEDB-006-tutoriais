#!/bin/bash
set -e

WORDCOUNT_DIR=/home/hduser/wordcount
INPUT_HDFS=/user/hduser/custom-input
OUTPUT_HDFS=/user/hduser/custom-output

echo "============================================"
echo " Custom WordCount (Java MapReduce)"
echo "============================================"
echo ""

echo "[1/6] Compiling Java source files..."
mkdir -p $WORDCOUNT_DIR/build
HADOOP_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath)
javac -classpath "$HADOOP_CLASSPATH" -d $WORDCOUNT_DIR/build $WORDCOUNT_DIR/src/*.java
echo "   Compilation successful!"

echo "[2/6] Packaging JAR file..."
jar cf $WORDCOUNT_DIR/wordcount.jar -C $WORDCOUNT_DIR/build .
echo "   JAR created: $WORDCOUNT_DIR/wordcount.jar"

echo "[3/6] Uploading lorem.txt to HDFS..."
hdfs dfs -mkdir -p $INPUT_HDFS
hdfs dfs -put -f $WORDCOUNT_DIR/data/lorem.txt $INPUT_HDFS/
echo "   Upload complete!"

echo "[4/6] Running custom WordCount MapReduce job..."
hdfs dfs -rm -r -f $OUTPUT_HDFS 2>/dev/null || true
hadoop jar $WORDCOUNT_DIR/wordcount.jar WordCountApplication $INPUT_HDFS $OUTPUT_HDFS
echo "   Job complete!"

echo "[5/6] Results:"
echo "---"
hdfs dfs -cat $OUTPUT_HDFS/part-r-00000
echo "---"

echo "[6/6] Copying result to local file system..."
hdfs dfs -get $OUTPUT_HDFS/part-r-00000 $WORDCOUNT_DIR/result.txt
echo "   Saved to: $WORDCOUNT_DIR/result.txt"
echo "   Total words counted: $(wc -l < $WORDCOUNT_DIR/result.txt)"
echo ""
echo "============================================"
echo " Custom WordCount complete!"
echo "============================================"
