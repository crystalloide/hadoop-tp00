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

mkdir -p /var/log

echo "============================================="
echo "  Big Data All-in-One — Démarrage du cluster"
echo "============================================="

# ── SSH ──────────────────────────────────────────────────────
echo "[1/7] Démarrage SSH..."
service ssh start

# ── Format NameNode (premier démarrage uniquement) ───────────
if [ ! -d "${HADOOP_HOME}/dfs/name/current" ]; then
    echo "[2/7] Formatage du NameNode (premier démarrage)..."
    $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
else
    echo "[2/7] NameNode déjà formaté — skip."
fi

# ── HDFS ─────────────────────────────────────────────────────
echo "[3/7] Démarrage HDFS..."
$HADOOP_HOME/sbin/start-dfs.sh

echo "   → Attente NameNode + DataNode..."
# Attendre que le NameNode soit sorti du safe mode ET qu'un DataNode soit enregistré
until $HADOOP_HOME/bin/hdfs dfsadmin -report 2>&1 | grep -q "Live datanodes.*[1-9]"; do
    sleep 30
done
# Forcer la sortie du safe mode (peut rester bloqué au redémarrage)
    $HADOOP_HOME/bin/hdfs dfsadmin -safemode leave > /dev/null 2>&1 || true
    echo "   ✓ HDFS opérationnel (DataNode enregistré)"

# ── YARN + MapReduce History ──────────────────────────────────
echo "[4/7] Démarrage YARN + MapReduce History Server..."
$HADOOP_HOME/sbin/start-yarn.sh
$HADOOP_HOME/bin/mapred --daemon start historyserver
sleep 3

# ── Répertoires HDFS ─────────────────────────────────────────
echo "[5/7] Création des répertoires HDFS..."
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/root
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hive/warehouse
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod 1777 /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod -R 777 /user/hive/warehouse

# Upload Tez sur HDFS (premier démarrage uniquement)
if ! $HADOOP_HOME/bin/hdfs dfs -test -e /apps/tez/tez.tar.gz 2>/dev/null; then
    echo "   → Upload Tez sur HDFS..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /apps/tez
    $HADOOP_HOME/bin/hdfs dfs -put ${TEZ_HOME}/share/tez.tar.gz /apps/tez/
fi

# ── Schéma Hive Metastore Derby ───────────────────────────────
echo "[6/7] Initialisation Hive..."

# Cas 1 : base Derby absente → init propre
if [ ! -d "${HIVE_HOME}/metastore_db" ]; then
    echo "   → Initialisation schéma Derby (premier démarrage)..."
    $HIVE_HOME/bin/schematool -dbType derby -initSchema 2>&1 \
        | grep -E "Initialization script|schemaTool|ERROR" || true

# Cas 2 : base présente mais schéma corrompu/incomplet → reset
else
    SCHEMA_OK=$($HIVE_HOME/bin/schematool -dbType derby -info 2>&1 | grep -c "Hive distribution version" || true)
    if [ "$SCHEMA_OK" -eq 0 ]; then
        echo "   ⚠ Schéma Derby corrompu — reset..."
        rm -rf ${HIVE_HOME}/metastore_db
        rm -f ${HIVE_HOME}/derby.log
        $HIVE_HOME/bin/schematool -dbType derby -initSchema 2>&1 \
            | grep -E "Initialization script|schemaTool|ERROR" || true
    else
        echo "   ✓ Schéma Derby OK"
    fi
fi

# Supprimer les verrous Derby résiduels (crash précédent)
rm -f ${HIVE_HOME}/metastore_db/*.lck 2>/dev/null || true

# ── Hive Metastore ────────────────────────────────────────────
echo "   → Démarrage Hive Metastore..."
nohup $HIVE_HOME/bin/hive --service metastore \
    > /var/log/hive-metastore.log 2>&1 &

echo "   → Attente port 9083..."
for i in $(seq 1 40); do
    nc -z localhost 9083 2>/dev/null && echo "   ✓ Metastore prêt (${i}x3s)" && break
    [ $i -eq 40 ] && echo "   ✗ Metastore timeout" && tail -20 /var/log/hive-metastore.log && exit 1
    sleep 3
done

# ── HiveServer2 ───────────────────────────────────────────────
echo "   → Démarrage HiveServer2..."
nohup $HIVE_HOME/bin/hiveserver2 \
    > /var/log/hiveserver2.log 2>&1 &

echo "   → Attente port 10000..."
for i in $(seq 1 40); do
    nc -z localhost 10000 2>/dev/null && echo "   ✓ HiveServer2 prêt (${i}x3s)" && break
    [ $i -eq 40 ] && echo "   ✗ HiveServer2 timeout" && tail -20 /var/log/hiveserver2.log && exit 1
    sleep 3
done

# ── Zeppelin ─────────────────────────────────────────────────
echo "[7/7] Démarrage Zeppelin..."
$ZEPPELIN_HOME/bin/zeppelin-daemon.sh start > /var/log/zeppelin.log 2>&1
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
echo "Processus actifs :"
jps
echo "============================================="

tail -f /dev/null
exit 0
