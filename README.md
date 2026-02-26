# 🐘 Big Data All-in-One — Docker

Environnement complet mono-conteneur pour un **cours Big Data**.

| Composant | Version | Rôle |
|-----------|---------|------|
| **HDFS** | Hadoop 3.3.6 | Système de fichiers distribué (1 NameNode + 1 DataNode) |
| **YARN** | Hadoop 3.3.6 | Gestionnaire de ressources cluster |
| **MapReduce** | Hadoop 3.3.6 | Modèle de traitement distribué |
| **Hive** | 3.1.3 | SQL sur Hadoop (HQL) |
| **Tez** | 0.10.3 | Moteur DAG (remplace MR pour Hive) |
| **Sqoop** | 1.4.7 | Import/export SGBDR ↔ HDFS |
| **Zeppelin** | 0.11.1 | Notebook interactif (SQL, shell…) |

---

## 🚀 Démarrage rapide

### Étape 1 : Préparation de l'environnement

```bash
cd ~
sudo rm -Rf ~/hadoop-tp00

#### Ici, on va simplement cloner le projet :
git clone https://github.com/crystalloide/hadoop-tp00

cd ~/hadoop-tp00
```
```bash
# 1. Construire l'image (première fois : ~10-15 min)
docker compose build

# 2. Lancer le cluster
docker compose up -d

# 3. Suivre les logs de démarrage (<CTRL>+<C> pour sortir)
docker compose logs -f bigdata

# 4. Regarder les ports à l'écoute :
netstat -anl | grep -E '9870|8088|19888|8080|10000'

```

Le cluster est prêt quand vous voyez `✅ Cluster Big Data prêt !`

---

## 🌐 Interfaces Web

| Interface | URL | Lancer l'affichage |   
|-----------|-----|--------------------|
| HDFS NameNode | http://localhost:9870 | firefox http://localhost:9870 |
| YARN ResourceManager | http://localhost:8088 | firefox http://localhost:8088 |
| MapReduce History | http://localhost:19888 | firefox http://localhost:19888 |
| Zeppelin Notebooks | http://localhost:8080 | firefox http://localhost:8080 |

---

## 💻 Commandes essentielles

### Ouvrir un terminal dans le conteneur
```bash
docker exec -it bigdata-cluster bash
```

### HDFS
```bash
# Lister la racine
hdfs dfs -ls /

# Supprimer / Créer un répertoire
hdfs dfs -rm -r /monrepertoire
hdfs dfs -mkdir /monrepertoire

# Uploader un fichier
rm monFichier.csv
echo "hadoop,hive,hadoop,tez,hive" > monFichier.csv
hdfs dfs -put monFichier.csv /monrepertoire/

# Afficher un fichier
hdfs dfs -cat /monrepertoire/monFichier.csv
```

### MapReduce — WordCount (exemple classique)
```bash
# Créer un fichier test
echo "hadoop hive hadoop tez hive hive" > /tmp/texte.txt
hdfs dfs -mkdir /input
hdfs dfs -put /tmp/texte.txt /input/

# Lancer le job WordCount
hdfs dfs -rm -r /output
hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar \
  wordcount /input /output

# Voir le résultat
hdfs dfs -cat /output/part-r-00000
```

### Hive via Beeline (HiveServer2)
```bash

echo "id,produit,montant" > ventes.csv && for i in {1..10}; do echo "$i,Produit_$(printf "%02d" $i),$((10 + RANDOM % 90)).$((RANDOM % 99))" >> ventes.csv; done
hdfs dfs -put ventes.csv /input/ventes.csv
hdfs dfs -cat hdfs://bigdata-node:9000/input/ventes.csv

beeline -u "jdbc:hive2://localhost:10000" -n root

# Dans Beeline :
set hive.execution.engine=mr;

SHOW DATABASES;
CREATE DATABASE cours;
USE cours;

CREATE TABLE ventes (
  id     INT,
  produit STRING,
  montant DOUBLE
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

ALTER TABLE cours.ventes SET TBLPROPERTIES ("skip.header.line.count"="1");

LOAD DATA INPATH '/input/ventes.csv' INTO TABLE cours.ventes;
SELECT produit, SUM(montant) FROM cours.ventes GROUP BY produit;
```

### Sqoop — Importer depuis MySQL
```bash
# Lister les bases MySQL distantes
sqoop list-databases \
  --connect jdbc:mysql://mysql-host:3306/ \
  --username root --password secret

# Importer une table vers HDFS
sqoop import \
  --connect jdbc:mysql://mysql-host:3306/mabase \
  --username root --password secret \
  --table matable \
  --target-dir /user/root/matable \
  --num-mappers 1

# Importer directement dans Hive
sqoop import \
  --connect jdbc:mysql://mysql-host:3306/mabase \
  --username root --password secret \
  --table matable \
  --hive-import \
  --hive-table cours.matable \
  --num-mappers 1
```

### Zeppelin
Accéder à http://localhost:8080 et créer un nouveau notebook.  
Utiliser l'interpréteur `%hive` pour exécuter du HQL directement dans le navigateur.

---

## ⚙️ Configuration

| Fichier | Description |
|---------|-------------|
| `config/hadoop/core-site.xml` | URI du NameNode |
| `config/hadoop/hdfs-site.xml` | Répertoires HDFS, réplication |
| `config/hadoop/mapred-site.xml` | Framework MR, mémoire Map/Reduce |
| `config/hadoop/yarn-site.xml` | Ressources YARN |
| `config/hive/hive-site.xml` | Metastore Derby, moteur Tez |
| `config/tez/tez-site.xml` | Mémoire DAG, chemin HDFS Tez |
| `config/zeppelin/zeppelin-site.xml` | Port, accès anonyme |

### Ajuster la mémoire
Modifier `yarn.nodemanager.resource.memory-mb` dans `yarn-site.xml` et `mem_limit` dans `docker-compose.yml` selon la RAM disponible :

| RAM machine | Recommandé |
|-------------|-----------|
| 4 Go | 3 Go (mem_limit: 3g) |
| 8 Go | 5 Go (mem_limit: 5g) |
| 16 Go | 8 Go (mem_limit: 8g) |

---

## 🛑 Arrêt et nettoyage

```bash
# Arrêter le cluster (volumes conservés)
docker compose down

# Arrêter ET supprimer les volumes (reset complet)
docker compose down -v
```

---

## ⚠️ Notes importantes

- **Metastore Derby** : embarqué dans Hive, parfait pour un cours. Limité à une seule connexion simultanée. Remplacer par MySQL pour un usage multi-utilisateurs.
- **Pas de Kerberos** : la sécurité est désactivée pour simplifier l'apprentissage.
- **Mode pseudo-distribué** : un seul nœud joue les rôles NameNode et DataNode simultanément.
- **Tez** : l'upload du tarball sur HDFS se fait automatiquement au premier démarrage.
