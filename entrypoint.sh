#!/bin/bash
# ============================================================
#  Entrypoint — démarrage séquentiel de tous les services
# ============================================================
set -e

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export TEZ_HOME=/opt/tez
export SQOOP_HOME=/opt/sqoop
export ZEPPELIN_HOME=/opt/zeppelin
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HIVE_HOME/bin:$SQOOP_HOME/bin

echo "============================================="
echo "  Big Data All-in-One — Démarrage du cluster"
echo "============================================="

# ── SSH (requis par Hadoop) ──────────────────────────────────
echo "[1/7] Démarrage SSH..."
service ssh start

# ── Formater le NameNode (uniquement au 1er démarrage) ──────
if [ ! -d "${HADOOP_HOME}/dfs/name/current" ]; then
    echo "[2/7] Formatage du NameNode HDFS (premier démarrage)..."
    $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
else
    echo "[2/7] NameNode déjà formaté — skip."
fi

# ── HDFS ─────────────────────────────────────────────────────
echo "[3/7] Démarrage HDFS (NameNode + DataNode)..."
$HADOOP_HOME/sbin/start-dfs.sh
sleep 5

# ── YARN + MapReduce ─────────────────────────────────────────
echo "[4/7] Démarrage YARN (ResourceManager + NodeManager)..."
$HADOOP_HOME/sbin/start-yarn.sh

echo "[4b]  Démarrage MapReduce Job History Server..."
$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver 2>/dev/null || \
  $HADOOP_HOME/bin/mapred --daemon start historyserver
sleep 3

# ── Répertoires HDFS ─────────────────────────────────────────
echo "[5/7] Création des répertoires HDFS..."
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/root
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hive/warehouse
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod g+w /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod g+w /user/hive/warehouse

# Copie de la lib Tez sur HDFS
if ! $HADOOP_HOME/bin/hdfs dfs -test -d /apps/tez; then
    echo "   → Upload de la lib Tez sur HDFS..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /apps/tez
    $HADOOP_HOME/bin/hdfs dfs -put ${TEZ_HOME}/share/tez.tar.gz /apps/tez/
fi

# ── Hive Metastore + HiveServer2 ─────────────────────────────
echo "[6/7] Démarrage Hive Metastore + HiveServer2..."
# Initialisation du schéma Derby (1er démarrage)
if [ ! -d "${HIVE_HOME}/metastore_db" ]; then
    echo "   → Initialisation du schéma Metastore..."
    $HIVE_HOME/bin/schematool -dbType derby -initSchema 2>&1 | tail -5
fi

nohup $HIVE_HOME/bin/hive --service metastore > /var/log/hive-metastore.log 2>&1 &
sleep 8
nohup $HIVE_HOME/bin/hiveserver2 > /var/log/hiveserver2.log 2>&1 &
sleep 5

# ── Zeppelin ─────────────────────────────────────────────────
echo "[7/7] Démarrage Apache Zeppelin..."
nohup $ZEPPELIN_HOME/bin/zeppelin-daemon.sh start > /var/log/zeppelin.log 2>&1 &
sleep 5

# ── Résumé ───────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  ✅  Cluster Big Data prêt !"
echo "============================================="
echo "  HDFS NameNode UI   → http://localhost:9870"
echo "  YARN ResourceMgr   → http://localhost:8088"
echo "  Job History Server → http://localhost:19888"
echo "  Zeppelin Notebooks → http://localhost:8080"
echo "  HiveServer2 JDBC   → jdbc:hive2://localhost:10000"
echo "============================================="
echo ""
echo "Commandes utiles :"
echo "  hdfs dfs -ls /                  # Lister HDFS"
echo "  beeline -u jdbc:hive2://localhost:10000  # Hive CLI"
echo "  sqoop list-databases --connect jdbc:mysql://host/db"
echo "============================================="

# ── Maintenir le conteneur actif ─────────────────────────────
tail -f /dev/null
