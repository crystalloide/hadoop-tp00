#!/bin/bash
# ============================================================
#  Entrypoint — Version Corrigée (Anti-Crash)
# ============================================================
set -e

# Mode debug (décommente la ligne suivante si le code 1 persiste)
# set -x 

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

# ── SSH ──────────────────────────────────────────────────────
echo "[1/7] Démarrage SSH..."
service ssh start || echo "⚠️ SSH déjà démarré ou erreur non critique"

# ── Formater le NameNode ─────────────────────────────────────
if [ ! -d "${HADOOP_HOME}/dfs/name/current" ]; then
    echo "[2/7] Formatage du NameNode HDFS..."
    $HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
else
    echo "[2/7] NameNode déjà formaté — skip."
fi

# ── HDFS ─────────────────────────────────────────────────────
echo "[3/7] Démarrage HDFS..."
$HADOOP_HOME/sbin/start-dfs.sh

# SÉCURITÉ : Attendre que HDFS sorte du mode "Safe Mode"
# Sinon, les commandes 'mkdir' suivantes échoueront (Code 1)
echo "   → Attente de la sortie du Safe Mode HDFS..."
$HADOOP_HOME/bin/hdfs dfsadmin -safemode wait

# ── YARN ─────────────────────────────────────────────────────
echo "[4/7] Démarrage YARN..."
$HADOOP_HOME/sbin/start-yarn.sh

echo "[4b] Démarrage MapReduce Job History Server..."
$HADOOP_HOME/sbin/mr-jobhistory-daemon.sh start historyserver 2>/dev/null || \
  $HADOOP_HOME/bin/mapred --daemon start historyserver || true

# ── Répertoires HDFS ─────────────────────────────────────────
echo "[5/7] Création des répertoires HDFS..."
# On utilise || true pour éviter que set -e n'arrête le script si le dossier existe déjà bizarrement
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/root || true
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hive/warehouse || true
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /user/hive/warehouse || true
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp || true
$HADOOP_HOME/bin/hdfs dfs -chmod g+w /tmp || true
$HADOOP_HOME/bin/hdfs dfs -chmod g+w /user/hive/warehouse || true
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /tmp || true

if ! $HADOOP_HOME/bin/hdfs dfs -test -d /apps/tez; then
    echo "   → Upload de la lib Tez..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /apps/tez || true
    $HADOOP_HOME/bin/hdfs dfs -put ${TEZ_HOME}/share/tez.tar.gz /apps/tez/ || true
    $HADOOP_HOME/bin/hdfs dfs -chmod 777 /apps/tez/tez.tar.gz || true
fi

# ── Hive ──────────────────────────────────────────────────────
echo "[6/7] Initialisation Hive..."
if [ ! -d "${HIVE_HOME}/metastore_db" ]; then
    echo "   → Initialisation schéma Derby..."
    $HIVE_HOME/bin/schematool -dbType derby -initSchema || true
fi

rm -f ${HIVE_HOME}/metastore_db/*.lck 2>/dev/null || true

echo "   → Démarrage Hive Metastore..."
nohup $HIVE_HOME/bin/hive --service metastore > /var/log/hive-metastore.log 2>&1 &

# Augmentation du timeout à 60 itérations (3 minutes au lieu de 2)
echo "   → Attente port 9083 (Metastore)..."
for i in $(seq 1 60); do
    nc -z localhost 9083 2>/dev/null && echo "   ✓ Metastore prêt" && break
    if [ $i -eq 60 ]; then
        echo "   ✗ Metastore timeout - Check /var/log/hive-metastore.log"
        # On ne quitte pas forcément (exit 1) pour laisser l'utilisateur inspecter le conteneur
    fi
    sleep 3
done

echo "   → Démarrage HiveServer2..."
nohup $HIVE_HOME/bin/hiveserver2 > /var/log/hiveserver2.log 2>&1 &

echo "   → Attente port 10000 (HS2)..."
for i in $(seq 1 60); do
    nc -z localhost 10000 2>/dev/null && echo "   ✓ HiveServer2 prêt" && break
    [ $i -eq 60 ] && echo "   ✗ HiveServer2 timeout"
    sleep 3
done

# ── Zeppelin ─────────────────────────────────────────────────
echo "[7/7] Démarrage Zeppelin..."
$ZEPPELIN_HOME/bin/zeppelin-daemon.sh start || echo "⚠️ Erreur démarrage Zeppelin"

echo "============================================="
echo "  ✅  Cluster Big Data prêt !"
echo "============================================="

# ── Maintien en vie ──────────────────────────────────────────
tail -f /dev/null
