#!/bin/bash
set -e

sudo chown -R hduser:hduser /tmp/hadoop-hduser 2>/dev/null || true
sudo service ssh start

if [ ! -d "/tmp/hadoop-hduser/dfs/name" ]; then
    $HADOOP_HOME/bin/hdfs namenode -format && echo "OK: HDFS namenode format finished successfully!"
fi

$HADOOP_HOME/sbin/start-dfs.sh

echo "YARNSTART = $YARNSTART"
if [[ -z $YARNSTART || $YARNSTART -ne 0 ]]; then
    echo "Starting YARN..."
    $HADOOP_HOME/sbin/start-yarn.sh
fi

$HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /users
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /jars
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /users
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /jars

$HADOOP_HOME/bin/hdfs dfsadmin -safemode leave

echo ""
echo "=========================================="
echo " Hadoop Single Node Cluster is ready!"
echo " HDFS Web UI:  http://localhost:9870"
echo " YARN Web UI:  http://localhost:8088"
echo "=========================================="
echo ""

tail -f $HADOOP_HOME/logs/hadoop-*-namenode-*.log
