#!/bin/bash
# hive-env.sh — Variables d'environnement Hive
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export TEZ_HOME=/opt/tez

# CLASSPATH : ajouter les JARs Tez pour l'exécution
export HIVE_AUX_JARS_PATH=${TEZ_HOME}

# Mémoire JVM pour Hive CLI
export HADOOP_HEAPSIZE=512
