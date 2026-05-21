#!/usr/bin/env bash
set -e

HADOOP_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath)
BUILD_DIR=/home/hadoop/wordcount-build
S3_SRC=$1
S3_JARS=$2

echo "[compile-on-emr] Criando diretorio de build..."
mkdir -p ${BUILD_DIR}/src ${BUILD_DIR}/build

echo "[compile-on-emr] Baixando fontes Java do S3..."
aws s3 sync ${S3_SRC} ${BUILD_DIR}/src/

echo "[compile-on-emr] Compilando com Hadoop classpath do cluster..."
javac -classpath "${HADOOP_CLASSPATH}" -d ${BUILD_DIR}/build ${BUILD_DIR}/src/*.java

echo "[compile-on-emar] Empacotando JAR..."
cd ${BUILD_DIR}/build
jar cf ${BUILD_DIR}/wordcount.jar *.class
cd -

echo "[compile-on-emr] Enviando JAR para S3..."
aws s3 cp ${BUILD_DIR}/wordcount.jar ${S3_JARS}/wordcount.jar

echo "[compile-on-emr] Compilacao no EMR concluida com sucesso!"
