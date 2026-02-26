#!/bin/bash
# hadoop-env.sh — Variables d'environnement Hadoop
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export HADOOP_LOG_DIR=/var/log/hadoop

# Taille JVM des démons (adapter si besoin)
export HADOOP_HEAPSIZE=512
export YARN_HEAPSIZE=512

# Autoriser l'exécution en root (environnement cours uniquement)
export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root
export YARN_RESOURCEMANAGER_USER=root
export YARN_NODEMANAGER_USER=root
