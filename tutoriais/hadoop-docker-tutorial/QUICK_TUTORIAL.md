# Quick Tutorial: WordCount Customizado em Java

---

## 0. Subir e desligar o ambiente Docker

### Subir o container Hadoop

Navegue ate a pasta do projeto e inicie:

```bash
cd ~/Documents/Big\ Data/tutoriais/hadoop-docker
docker compose up -d
```

Aguardar ~25 segundos para o Hadoop inicializar:

```bash
docker logs hadoop 2>&1 | grep -E "(Hadoop Single Node Cluster is ready!|Safe mode is OFF)"
```

**Resultado esperado**:
```
Hadoop Single Node Cluster is ready!
 HDFS Web UI:  http://localhost:9870
 YARN Web UI:  http://localhost:8088
```

### Parar o container (mantendo dados)

```bash
docker compose down
```

### Parar e apagar tudo (inclusive dados HDFS)

```bash
docker compose down -v
```

---

## 1. Entrar no container

```bash
docker exec -it hadoop bash
```

**Resultado esperado**:
```
hduser@myhdfs:~$
```

## 2. Navegar nos arquivos do projeto

```bash
ls wordcount/src/
ls wordcount/data/
head -5 wordcount/data/lorem.txt
```

### 2.1 Copiar seus proprios arquivos do computador para o container

Se voce quiser usar seus proprios arquivos de texto (em vez do `lorem.txt`), copie da sua maquina para o container:

```bash
# No seu computador (host), fora do container:
docker cp /caminho/no/seu/computador/meu-texto.txt hadoop:/home/hduser/wordcount/data/
```

**Exemplo real**:
```bash
docker cp ~/Documentos/meu-livro.txt hadoop:/home/hduser/wordcount/data/
```

Depois de copiar, dentro do container voce podera enviar para o HDFS (passo 5).

## 3. Compilar o codigo Java

```bash
mkdir -p wordcount/build
javac -classpath "$(hadoop classpath)" -d wordcount/build wordcount/src/*.java
ls wordcount/build/
```

**Resultado esperado**:
```
WordCountApplication.class  WordCountMapper.class  WordCountReducer.class
```

## 4. Empacotar em JAR

```bash
jar cf wordcount/wordcount.jar -C wordcount/build .
```

## 5. Copiar dados para o HDFS

### Opcao A: Usar o arquivo lorem.txt (ja dentro do container)

```bash
hdfs dfs -mkdir -p /user/hduser/custom-input
hdfs dfs -put -f wordcount/data/lorem.txt /user/hduser/custom-input/
hdfs dfs -ls /user/hduser/custom-input/
```

**Resultado esperado**:
```
Found 1 items
-rw-r--r--   1 hduser supergroup       9634 ... /user/hduser/custom-input/lorem.txt
```

### Opcao B: Usar seu proprio arquivo copiado do computador

Se voce copiou um arquivo no passo 2.1 usando `docker cp`:

```bash
hdfs dfs -mkdir -p /user/hduser/custom-input
hdfs dfs -put -f wordcount/data/meu-texto.txt /user/hduser/custom-input/
hdfs dfs -ls /user/hduser/custom-input/
```

### Opcao C: Copiar direto do computador para o HDFS (sem entrar no container)

Voce pode copiar um arquivo direto do seu computador para o HDFS sem precisar entrar no container:

```bash
# Fora do container! No terminal do seu computador:
cat /caminho/para/seu-arquivo.txt | docker exec -i hadoop hdfs dfs -put - /user/hduser/custom-input/seu-arquivo.txt
```

**Exemplo real**:
```bash
cat ~/Documentos/meu-livro.txt | docker exec -i hadoop hdfs dfs -put - /user/hduser/custom-input/meu-livro.txt
```

> O `-` no lugar do nome do arquivo significa "ler da entrada padrao" (stdin). O `cat` envia o conteudo do arquivo pelo pipe `|` para o `hdfs dfs -put -`.

## 6. Rodar o WordCount

```bash
hdfs dfs -rm -r -f /user/hduser/custom-output 2>/dev/null || true
hadoop jar wordcount/wordcount.jar WordCountApplication /user/hduser/custom-input /user/hduser/custom-output
```

**Resultado esperado**:
```
INFO mapreduce.Job:  map 100% reduce 100%
INFO mapreduce.Job: Job job_local... completed successfully
```

## 7. Navegar no HDFS e ver o resultado

```bash
hdfs dfs -ls /user/hduser/custom-output/
```

**Resultado esperado**:
```
Found 2 items
-rw-r--r--   1 hduser supergroup          0 ... /user/hduser/custom-output/_SUCCESS
-rw-r--r--   1 hduser supergroup       9256 ... /user/hduser/custom-output/part-r-00000
```

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | head -20
```

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | sort -t$'\t' -k2 -nr | head -20
```

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | wc -l
```

## 8. Copiar resultado para o filesystem local

```bash
hdfs dfs -get /user/hduser/custom-output/part-r-00000 wordcount/result.txt
head -10 wordcount/result.txt
```

## 9. Explorar a estrutura completa do HDFS

```bash
hdfs dfs -ls -R /
hdfs dfs -du -h /
```

## 10. Sair do container

```bash
exit
```

---

## Versao automatizada (um comando so)

```bash
docker exec hadoop bash /home/hduser/run-custom-wordcount.sh
```
