# ============================================================
#  Big Data All-in-One — Cours Big Data
#  Hadoop 3.3.6 | Hive 3.1.3 | Tez 0.10.3 | Sqoop 1.4.7
#  MapReduce (inclus Hadoop) | Zeppelin 0.11.1
# ============================================================
FROM ubuntu:22.04

LABEL maintainer="Cours Big Data"
LABEL description="Single-node Big Data cluster: HDFS, YARN, MapReduce, Hive, Tez, Sqoop, Zeppelin"

ENV DEBIAN_FRONTEND=noninteractive

# ── Versions ────────────────────────────────────────────────
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV HADOOP_VERSION=3.3.6
ENV HIVE_VERSION=3.1.3
ENV TEZ_VERSION=0.10.3
ENV SQOOP_VERSION=1.4.7
ENV ZEPPELIN_VERSION=0.11.1
# MySQL Connector/J (com.mysql depuis 8.1, encore sous mysql/ pour 8.0.x)
ENV MYSQL_CONNECTOR_VERSION=5.1.49

# ── Répertoires d'installation ───────────────────────────────
ENV HADOOP_HOME=/opt/hadoop
ENV HIVE_HOME=/opt/hive
ENV TEZ_HOME=/opt/tez
ENV SQOOP_HOME=/opt/sqoop
ENV ZEPPELIN_HOME=/opt/zeppelin

# ── PATH global ──────────────────────────────────────────────
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HIVE_HOME/bin:$SQOOP_HOME/bin:$ZEPPELIN_HOME/bin

# ── Variables HDFS / YARN ────────────────────────────────────
ENV HDFS_NAMENODE_USER=root
ENV HDFS_DATANODE_USER=root
ENV HDFS_SECONDARYNAMENODE_USER=root
ENV YARN_RESOURCEMANAGER_USER=root
ENV YARN_NODEMANAGER_USER=root

# ── 1. Dépendances système ───────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-8-jdk \
    ssh \
    rsync \
    curl \
    wget \
    netcat-openbsd \
    procps \
    python3 \
    python3-pip \
    default-mysql-client \
    net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── 2. SSH sans mot de passe ─────────────────────────────────
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa \
 && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys \
 && chmod 0600 ~/.ssh/authorized_keys \
 && echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

# ── 3. Hadoop ────────────────────────────────────────────────
RUN wget --tries=3 --timeout=120 -q \
    "https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
 && tar -xzf hadoop-${HADOOP_VERSION}.tar.gz -C /opt \
 && mv /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME} \
 && rm hadoop-${HADOOP_VERSION}.tar.gz

# ── 4. Hive (archive.apache.org) ─────────────────────────────
RUN wget --tries=3 --timeout=120 -q \
    "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" \
 && tar -xzf apache-hive-${HIVE_VERSION}-bin.tar.gz -C /opt \
 && mv /opt/apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME} \
 && rm apache-hive-${HIVE_VERSION}-bin.tar.gz

# ── 5. Tez (archive.apache.org) ──────────────────────────────
RUN mkdir -p ${TEZ_HOME}/conf \
 && wget --tries=3 --timeout=120 -q \
    "https://archive.apache.org/dist/tez/${TEZ_VERSION}/apache-tez-${TEZ_VERSION}-bin.tar.gz" \
 && tar -xzf apache-tez-${TEZ_VERSION}-bin.tar.gz -C ${TEZ_HOME} --strip-components=1 \
 && rm apache-tez-${TEZ_VERSION}-bin.tar.gz

# ── 6a. Sqoop (archive.apache.org) ───────────────────────────
# Séparé du connector pour identifier les échecs séparément
RUN wget --tries=3 --timeout=120 -v \
    "https://archive.apache.org/dist/sqoop/${SQOOP_VERSION}/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz" \
 && tar -xzf sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz -C /opt \
 && mv /opt/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0 ${SQOOP_HOME} \
 && rm sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz

# ── 6b. MySQL Connector/J (Maven Central) ────────────────────
# Utilise curl avec fallback pour éviter les timeout silencieux de wget
RUN curl --retry 3 --max-time 120 --location --fail \
    -o ${SQOOP_HOME}/lib/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar \
    "https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar" \
 && echo "Taille JAR : $(du -sh ${SQOOP_HOME}/lib/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar)" \
 && echo "MySQL connector téléchargé : $(ls -lh ${SQOOP_HOME}/lib/mysql-connector-java-*.jar)"

# ── 6c. Fix commons-lang manquant (Sqoop 1.4.7 + Hadoop 3.x) ───────────
# Hadoop 3.x ne fournit que commons-lang3 ; Sqoop attend commons-lang 2.x
RUN curl -L -o ${SQOOP_HOME}/lib/commons-lang-2.6.jar \
    "https://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar"

# ── 6d. Fix conflit Guava Sqoop vs Hadoop 3 ─────────────────
# Hadoop 3.x embarque Guava 27+ ; Sqoop 1.4.7 attend Guava 11/14 → NoSuchMethodError
# On remplace le vieux guava dans les libs Sqoop par celui de Hadoop
RUN cp ${HADOOP_HOME}/share/hadoop/common/lib/guava-*.jar ${SQOOP_HOME}/lib/ \
 && rm -f ${SQOOP_HOME}/lib/guava-11*.jar \
 && rm -f ${SQOOP_HOME}/lib/guava-14*.jar \
 && echo "Guava Sqoop remplacé : $(ls ${SQOOP_HOME}/lib/guava-*.jar)"

# ── 7. Zeppelin (archive.apache.org) ─────────────────────────
RUN wget --tries=3 --timeout=300 -q \
    "https://archive.apache.org/dist/zeppelin/zeppelin-${ZEPPELIN_VERSION}/zeppelin-${ZEPPELIN_VERSION}-bin-all.tgz" \
 && tar -xzf zeppelin-${ZEPPELIN_VERSION}-bin-all.tgz -C /opt \
 && mv /opt/zeppelin-${ZEPPELIN_VERSION}-bin-all ${ZEPPELIN_HOME} \
 && rm zeppelin-${ZEPPELIN_VERSION}-bin-all.tgz

# ── 8. Configuration Hadoop ───────────────────────────────────
COPY config/hadoop/core-site.xml         ${HADOOP_HOME}/etc/hadoop/core-site.xml
COPY config/hadoop/hdfs-site.xml         ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml
COPY config/hadoop/mapred-site.xml       ${HADOOP_HOME}/etc/hadoop/mapred-site.xml
COPY config/hadoop/yarn-site.xml         ${HADOOP_HOME}/etc/hadoop/yarn-site.xml
COPY config/hadoop/hadoop-env.sh         ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# ── 9. Configuration Hive + Tez ───────────────────────────────
COPY config/hive/hive-site.xml           ${HIVE_HOME}/conf/hive-site.xml
COPY config/hive/hive-env.sh             ${HIVE_HOME}/conf/hive-env.sh
COPY config/hive/tez-site.xml            ${HIVE_HOME}/conf/tez-site.xml
COPY config/tez/tez-site.xml             ${TEZ_HOME}/conf/tez-site.xml

# ── 10. Configuration Zeppelin ────────────────────────────────
COPY config/zeppelin/zeppelin-site.xml   ${ZEPPELIN_HOME}/conf/zeppelin-site.xml
COPY config/zeppelin/zeppelin-env.sh     ${ZEPPELIN_HOME}/conf/zeppelin-env.sh
COPY config/zeppelin/interpreter.json    ${ZEPPELIN_HOME}/conf/interpreter.json

# ── 11. Entrypoint ────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9870 9864 8088 19888 10000 9083 8080

ENTRYPOINT ["/entrypoint.sh"]
