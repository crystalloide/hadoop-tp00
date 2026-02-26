#!/bin/bash
# zeppelin-env.sh — Variables d'environnement Zeppelin
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export HIVE_HOME=/opt/hive
export TEZ_HOME=/opt/tez

# Mémoire JVM Zeppelin
export ZEPPELIN_MEM="-Xms512m -Xmx1024m"

# Port Zeppelin
export ZEPPELIN_PORT=8080
