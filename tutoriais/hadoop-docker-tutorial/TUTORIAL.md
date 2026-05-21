# Tutorial Completo: Hadoop Single Node Cluster com Docker

> Guia passo a passo para iniciantes absolutos. Ao final, voce tera um Hadoop 3.3.6 rodando em um unico container Docker, com HDFS e YARN funcionais, e um job MapReduce WordCount executado com sucesso.

---

## Sumario

1. [O que voce vai instalar](#1-o-que-voce-vai-instalar)
2. [Pre-requisitos](#2-pre-requisitos)
3. [Instalacao do Docker](#3-instalacao-do-docker)
4. [Entendendo a estrutura do projeto](#4-entendendo-a-estrutura-do-projeto)
5. [Entendendo cada arquivo (explicacao detalhada)](#5-entendendo-cada-arquivo)
   - [Dockerfile](#51-dockerfile-linha-a-linha)
   - [docker-compose.yml](#52-docker-compose-yml-linha-a-linha)
   - [O que sao os arquivos XML](#53-o-que-sao-os-arquivos-xml-de-configuracao-do-hadoop)
   - [core-site.xml](#54-configcore-sitexml---configuracao-global-do-hadoop)
   - [hdfs-site.xml](#55-confighdfs-sitexml---configuracao-do-hdfs)
   - [yarn-site.xml](#56-configyarn-sitexml---configuracao-do-yarn)
   - [docker-entrypoint.sh](#57-scriptsdocker-entrypointsh---inicializacao-automatica-do-container)
   - [test-wordcount.sh](#58-scriptstest-wordcountsh---teste-automatizado-de-mapreduce)
   - [Como baixar o Hadoop tar.gz](#59-como-baixar-o-hadoophadoop-336targz)
6. [Build da imagem Docker](#6-build-da-imagem-docker)
7. [Iniciar o container](#7-iniciar-o-container)
8. [Verificar se esta funcionando](#8-verificar-se-esta-funcionando)
9. [Entrar no container e explorar](#9-entrar-no-container-e-explorar)
10. [Rodar o teste WordCount](#10-rodar-o-teste-wordcount)
11. [Comandos do dia a dia](#11-comandos-do-dia-a-dia)
12. [Parar e remover tudo](#12-parar-e-remover-tudo)
13. [WordCount Customizado em Java - Passo a Passo Manual](#13-wordcount-customizado-em-java---passo-a-passo-manual)
14. [Troubleshooting e Hotfix](#14-troubleshooting-e-hotfix)

---

## 1. O que voce vai instalar

| Componente | Versao | O que faz |
|---|---|---|
| Docker Desktop | ultima | Gerencia containers (ambientes isolados) |
| Hadoop | 3.3.6 | Framework de processamento distribuido de Big Data |
| HDFS | (incluido no Hadoop) | Sistema de arquivos distribuido (onde os dados ficam) |
| YARN | (incluido no Hadoop) | Gerenciador de recursos (quem roda os jobs) |
| MapReduce | (incluido no Hadoop) | Modelo de processamento paralelo de dados |

**Tudo roda dentro de um unico container Docker** - nao precisa instalar Java, SSH, ou Hadoop direto na sua maquina.

---

## 2. Pre-requisitos

- **Computador** com macOS (Intel ou Apple Silicon), Windows 10/11, ou Linux
- **Internet** para baixar o Docker e a imagem Hadoop
- **Espaco em disco**: ~2 GB (imagem Docker + Hadoop)
- **Terminal/Console**: Terminal (macOS/Linux) ou PowerShell (Windows)

> Este tutorial foi testado em macOS com Apple Silicon (M1/M2/M3). Funciona igualmente em Intel e Windows.

---

## 3. Instalacao do Docker

### 3.1 Verificar se o Docker ja esta instalado

Abra o terminal e digite:

```bash
docker --version
```

**Resultado esperado** (os numeros podem variar):
```
Docker version 27.x.x, build xxxxxxx
```

Se voce ja viu a versao, pule para a [secao 4](#4-entendendo-a-estrutura-do-projeto).

### 3.2 Instalar o Docker Desktop

#### macOS

1. Acesse: https://www.docker.com/products/docker-desktop/
2. Clique em **"Download for Mac"**
3. Escolha:
   - **Apple Silicon** (chip M1/M2/M3) -> arquivo `.dmg` com "Apple Silicon"
   - **Intel** (chip Intel) -> arquivo `.dmg` com "Intel"
4. Abra o arquivo `.dmg` baixado
5. Arraste o **Docker** para a pasta **Applications**
6. Abra o Docker from Applications
7. Siga as instrucoes iniciais (pode pedir senha do Mac)

#### Windows

1. Acesse: https://www.docker.com/products/docker-desktop/
2. Clique em **"Download for Windows"**
3. Execute o instalador `.exe`
4. Marque **"Use WSL 2 instead of Hyper-V"** se solicitado
5. Reinicie o computador se necessario
6. Abra o **Docker Desktop** from menu Iniciar

#### Linux (Ubuntu/Debian)

```bash
# Atualizar pacotes
sudo apt update

# Instalar dependencias
sudo apt install -y ca-certificates curl gnupg

# Adicionar chave GPG do Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositorio do Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Adicionar seu usuario ao grupo docker (nao precisa de sudo)
sudo usermod -aG docker $USER
newgrp docker
```

### 3.3 Verificar que o Docker esta rodando

```bash
docker info
```

**Resultado esperado** (primeiras linhas):
```
Client: Docker Engine - Community
 Version:    27.x.x
 ...
Server:
 ...
 Operating System: Docker Desktop
```

Se der erro "Cannot connect to the Docker daemon", abra o **Docker Desktop** e aguarde ele iniciar (o icone da baleia na barra de menus para de animar).

---

## 4. Entendendo a estrutura do projeto

Todos os arquivos estao na pasta:

```
tutoriais/hadoop-docker/
├── Dockerfile                  # Receita para criar a imagem Docker com Hadoop
├── docker-compose.yml          # Configuracao simplificada para subir o container
├── QUICK_TUTORIAL.md           # Guia rapido do WordCount customizado
├── hadoop-3.3.6.tar.gz         # Pacote do Hadoop (binario compactado)
├── config/
│   ├── core-site.xml           # Configuracao principal do Hadoop (onde fica o HDFS)
│   ├── hdfs-site.xml           # Configuracao do HDFS (replicacao = 1 para single node)
│   ├── yarn-site.xml           # Configuracao do YARN (gerenciador de recursos)
│   └── ssh_config              # Configuracao SSH (necessaria internamente)
├── scripts/
│   ├── docker-entrypoint.sh    # Script que inicia automaticamente quando o container sobe
│   ├── test-wordcount.sh       # Script de teste automatizado (built-in + custom WordCount)
│   └── run-custom-wordcount.sh # Script para compilar, empacotar e rodar WordCount customizado
├── src/
│   ├── WordCountApplication.java  # Classe principal do MapReduce customizado
│   ├── WordCountMapper.java       # Mapper: divide texto em (palavra, 1)
│   └── WordCountReducer.java      # Reducer: soma contagens por palavra
└── data/
    └── lorem.txt               # Texto de exemplo para o WordCount customizado
```

**O que cada coisa faz**:

- **Dockerfile**: e como uma "receita de bolo". Diz ao Docker como montar o ambiente (qual sistema operacional, o que instalar, como configurar).
- **docker-compose.yml**: e um atalho. Em vez de digitar um comando `docker run` enorme, voce digita apenas `docker compose up`.
- **hadoop-3.3.6.tar.gz**: e o proprio Hadoop empacotado. Esta versao e copiada para dentro do container durante o build.
- **config/**: sao os arquivos de configuracao do Hadoop que serao copiados para dentro do container.
- **scripts/**: scripts que automatizam a inicializacao e os testes.
- **src/**: codigo fonte Java do WordCount customizado (copiado para dentro do container).
- **data/**: arquivos de dados de exemplo (copiados para dentro do container).

---

## 5. Entendendo cada arquivo

### 5.1 Dockerfile (linha a linha)

```dockerfile
# Imagem base: Java 8 (Eclipse Temurin) sobre Ubuntu 20.04 (Focal)
# Hadoop 3.3.6 exige Java 8
FROM eclipse-temurin:8-jdk-focal

# Instala pacotes necessarios:
# - sudo: para o usuario hduser executar comandos administrativos
# - curl: para baixar arquivos
# - ssh: Hadoop precisa de SSH para se comunicar entre nos
# --no-install-recommends: instala so o essencial (imagem menor)
RUN apt-get update -y \
    && export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        sudo \
        curl \
        ssh \
    && apt-get clean

# Cria usuario "hduser" com senha "supergroup"
# -m: cria home directory (/home/hduser)
# Adiciona ao grupo sudo (pode executar comandos como root)
# Configura sudo sem senha para facilitar
RUN useradd -m hduser \
    && echo "hduser:supergroup" | chpasswd \
    && adduser hduser sudo \
    && echo "hduser     ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copia configuracao SSH que desabilita verificacao de host
# Isso evita prompts de "Are you sure you want to continue connecting?"
COPY config/ssh_config /etc/ssh/ssh_config

# Define o diretorio de trabalho e muda para o usuario hduser
# A partir daqui, todos os comandos rodam como hduser (nao root)
WORKDIR /home/hduser
USER hduser

# Gera chave SSH sem senha para o usuario hduser
# Isso permite que o Hadoop faca SSH para localhost sem pedir senha
# -t rsa: tipo de chave RSA
# -P '': senha vazia
# Depois adiciona a chave publica aos authorized_keys
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa \
    && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys \
    && chmod 0600 ~/.ssh/authorized_keys

# Define variaveis de ambiente para versao e localizacao do Hadoop
ENV HADOOP_VERSION=3.3.6
ENV HADOOP_HOME=/home/hduser/hadoop-${HADOOP_VERSION}

# Copia o tarball do Hadoop que ja esta na pasta local
# Descompacta, remove o .tar.gz e remove documentacao para poupar espaco
COPY hadoop-${HADOOP_VERSION}.tar.gz /home/hduser/hadoop.tar.gz
RUN tar -xzf /home/hduser/hadoop.tar.gz -C /home/hduser/ \
    && rm -f /home/hduser/hadoop.tar.gz \
    && rm -rf ${HADOOP_HOME}/share/doc

# Define quais usuarios vao rodar cada servico do Hadoop
# Como so temos 1 usuario (hduser), todos sao hduser
ENV HDFS_NAMENODE_USER=hduser
ENV HDFS_DATANODE_USER=hduser
ENV HDFS_SECONDARYNAMENODE_USER=hduser
ENV YARN_RESOURCEMANAGER_USER=hduser
ENV YARN_NODEMANAGER_USER=hduser

# Configura o JAVA_HOME dentro do Hadoop
# Diz ao Hadoop onde encontrar o Java (que ja vem na imagem base)
RUN echo "export JAVA_HOME=/opt/java/openjdk/" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

# Copia os arquivos de configuracao XML para dentro do Hadoop
# Esses arquivos definem como o Hadoop funciona
COPY config/core-site.xml $HADOOP_HOME/etc/hadoop/
COPY config/hdfs-site.xml $HADOOP_HOME/etc/hadoop/
COPY config/yarn-site.xml $HADOOP_HOME/etc/hadoop/

# Copia os scripts para dentro do container
COPY scripts/docker-entrypoint.sh $HADOOP_HOME/etc/hadoop/
COPY scripts/test-wordcount.sh /home/hduser/
COPY scripts/run-custom-wordcount.sh /home/hduser/

# Da permissao de execucao aos scripts
RUN sudo chmod +x $HADOOP_HOME/etc/hadoop/docker-entrypoint.sh \
    && sudo chmod +x /home/hduser/test-wordcount.sh \
    && sudo chmod +x /home/hduser/run-custom-wordcount.sh

# Copia codigo fonte Java e dados de exemplo para o WordCount customizado
COPY src/ /home/hduser/wordcount/src/
COPY data/ /home/hduser/wordcount/data/

# Corrige ownership dos arquivos copiados (sao copiados como root)
RUN sudo chown -R hduser:hduser /home/hduser/wordcount

# Adiciona os binarios do Hadoop ao PATH
# Permite digitar "hdfs" ou "hadoop" diretamente no terminal
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

# Expoe as portas que o Hadoop usa:
# 9000: Comunicacao HDFS (clientes conectam aqui)
# 9864: DataNode Web UI
# 9870: NameNode Web UI (interface web do HDFS)
# 8088: YARN ResourceManager Web UI (interface web do YARN)
EXPOSE 9000 9864 9870 8088

# Cria um link simbolico para o entrypoint em /usr/local/bin
WORKDIR /usr/local/bin
RUN sudo ln -s ${HADOOP_HOME}/etc/hadoop/docker-entrypoint.sh .
WORKDIR /home/hduser

# YARNSTART=1: faz o YARN iniciar automaticamente junto com o HDFS
ENV YARNSTART=1

# Comando executado quando o container inicia
# Roda o script docker-entrypoint.sh que:
# 1. Inicia SSH
# 2. Formata o namenode (se primeira vez)
# 3. Inicia HDFS
# 4. Inicia YARN
# 5. Cria diretorios no HDFS
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
```

### 5.2 docker-compose.yml (linha a linha)

```yaml
# Define os servicos (containers) que vao rodar
services:
  # Nome do servico: hadoop
  hadoop:
    # Configuracao de build
    build:
      context: .                # Usa a pasta atual como contexto
      dockerfile: Dockerfile    # Usa o Dockerfile desta pasta
    # Nome da imagem resultante
    image: hadoop-single-node:3.3.6
    # Nome do container (para facilitar referencia)
    container_name: hadoop
    # Hostname interno do container
    hostname: myhdfs
    # Mapeamento de portas: host:container
    ports:
      - "9870:9870"   # HDFS NameNode Web UI
      - "8088:8088"   # YARN ResourceManager Web UI
      - "9000:9000"   # HDFS cliente
      - "9864:9864"   # DataNode
    # Variaveis de ambiente passadas para o container
    environment:
      - YARNSTART=1   # Inicia YARN automaticamente
    # Volume: persiste os dados do HDFS entre reinicializacoes
    # Sem isso, os dados somem quando o container e parado
    volumes:
      - hadoop-data:/tmp/hadoop-hduser
    # Mantem o terminal aberto (interativo)
    stdin_open: true
    tty: true

# Define volumes nomeados
volumes:
  hadoop-data:   # Volume Docker que persiste os dados HDFS
```

### 5.3 O que sao os arquivos XML de configuracao do Hadoop

Antes de explicar cada arquivo XML, e importante entender **por que existem** e **como funcionam**.

#### O que sao?

O Hadoop nao usa um unico arquivo de configuracao. Ele usa **varios arquivos XML**, cada um responsavel por configurar um componente diferente. Esses arquivos ficam dentro do diretorio `$HADOOP_HOME/etc/hadoop/`.

#### Estrutura de um arquivo XML do Hadoop

Todo arquivo XML de configuracao do Hadoop segue este formato:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>nome.da.propriedade</name>
        <value>valor.da.propriedade</value>
    </property>
</configuration>
```

| Parte | O que e |
|---|---|
| `<configuration>` | Elemento raiz. Tudo fica dentro dele. |
| `<property>` | Uma configuracao individual. Pode haver varias. |
| `<name>` | O **nome** da configuracao. E um identificador unico que o Hadoop reconhece. |
| `<value>` | O **valor** dessa configuracao. Pode ser um numero, texto, caminho, etc. |

#### Quais arquivos existem e o que cada um configura?

| Arquivo | Componente configurado | O que controla |
|---|---|---|
| `core-site.xml` | **Hadoop Core** | Configuracoes globais do Hadoop. O mais importante: qual e o sistema de arquivos padrao (HDFS) e onde ele fica. |
| `hdfs-site.xml` | **HDFS** (Sistema de Arquivos) | Como o HDFS se comporta: numero de replicas, tamanho de blocos, permissoes, local dos dados no disco. |
| `yarn-site.xml` | **YARN** (Gerenciador de Recursos) | Como o YARN funciona: memoria por container, servicos auxiliares, filas de jobs. |
| `mapred-site.xml` | **MapReduce** | Como os jobs MapReduce rodam: framework (YARN ou local), memoria para map/reduce. |
| `hadoop-env.sh` | **Variaveis de ambiente** | Nao e XML, e um script shell. Define JAVA_HOME e outras variaveis. |

> **Nosso projeto so usa 3 desses**: `core-site.xml`, `hdfs-site.xml` e `yarn-site.xml`. O `mapred-site.xml` nao e necessario porque rodamos MapReduce sobre YARN com as configuracoes padrao. O `hadoop-env.sh` e configurado diretamente no Dockerfile (linha que faz `echo "export JAVA_HOME=..."`).

#### Onde esses arquivos ficam na maquina real vs no container?

| Local | Descricao |
|---|---|
| `tutoriais/hadoop-docker/config/` | **Na sua maquina** (host). Sao os arquivos que voce edita. |
| `$HADOOP_HOME/etc/hadoop/` (dentro do container) | **Dentro do container**. O Docker copia os arquivos da pasta `config/` para aqui durante o build. E o Hadoop le desta localizacao. |

O comando no Dockerfile que faz essa copia e:
```dockerfile
COPY config/core-site.xml $HADOOP_HOME/etc/hadoop/
```

#### Se eu quiser mudar uma configuracao, o que faco?

1. Edite o arquivo XML na pasta `config/` na sua maquina
2. Rebuild a imagem: `docker compose build`
3. Reinicie o container: `docker compose up -d`

> **Importante**: Mudancas nos XML exigem rebuild da imagem, pois os arquivos sao copiados DURANTE o build (nao em tempo de execucao).

---

### 5.4 config/core-site.xml - Configuracao Global do Hadoop

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://0.0.0.0:9000</value>
    </property>
</configuration>
```

#### O que e este arquivo?

O `core-site.xml` e o arquivo de configuracao **principal** do Hadoop. Ele define configuracoes globais que se aplicam a todos os componentes. Se o Hadoop fosse um sistema operacional, o `core-site.xml` seria como o "painel de controle" basico.

#### O que cada propriedade faz?

**`fs.defaultFS` = `hdfs://0.0.0.0:9000`**

| Parte | Explicacao detalhada |
|---|---|
| `fs.defaultFS` | Nome da propriedade. Significa "File System Default". Define qual sistema de arquivos o Hadoop usa por padrao quando voce digita comandos como `hdfs dfs -ls /`. Sem essa configuracao, o Hadoop nao sabe onde procurar os arquivos. |
| `hdfs://` | Protocolo. Diz ao Hadoop para usar o HDFS (Hadoop Distributed File System). Outras opcoes seriam `file:///` (sistema local) ou `s3a://` (Amazon S3). |
| `0.0.0.0` | Endereco IP. Significa "escute em **todas** as interfaces de rede". Se usassemos `localhost` ou `127.0.0.1`, so funcionaria internamente no container. Com `0.0.0.0`, o HDFS aceita conexoes de fora tambem (do host, de outros containers, etc.). |
| `:9000` | Porta TCP. E a porta onde o NameNode escuta conexoes de clientes HDFS. Quando voce roda `hdfs dfs -ls /`, o cliente HDFS conecta nesta porta. |

#### Analogia

Pense no `fs.defaultFS` como o **endereco do servidor de arquivos**. E como mapear uma unidade de rede no Windows (`\\servidor\compartilhamento`). Sem ele, o Hadoop nao sabe onde estao os arquivos.

#### Se voce quiser mudar a porta

Se a porta 9000 estiver em uso na sua maquina, voce pode mudar para outra:

```xml
<value>hdfs://0.0.0.0:19000</value>
```

Mas lembre-se de tambem atualizar o mapeamento de portas no `docker-compose.yml`:
```yaml
ports:
  - "19000:9000"   # 19000 no host -> 9000 no container
```

E recriar a imagem com `docker compose build`.

---

### 5.5 config/hdfs-site.xml - Configuracao do HDFS

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.permissions</name>
        <value>false</value>
    </property>
</configuration>
```

#### O que e este arquivo?

O `hdfs-site.xml` configura **exclusivamente o HDFS** (Hadoop Distributed File System). E aqui que voce define como os dados sao armazenados, replicados e protegidos.

#### O que cada propriedade faz?

**`dfs.replication` = `1`**

| Aspecto | Detalhe |
|---|---|
| **O que e** | Define **quantas copias** de cada bloco de dados sao armazenadas no HDFS. |
| **Valor padrao** | `3` (em um cluster real, cada bloco tem 3 copias em 3 maquinas diferentes) |
| **Por que 1 aqui?** | Temos apenas **1 no** (single node). Se pedissemos 3 replicas, o Hadoop tentaria colocar 3 copias no mesmo no, o que desperdica espaco e gera avisos. Com 1, cada bloco tem exatamente 1 copia. |
| **Como funciona na pratica** | Quando voce faz upload de um arquivo de 100 MB, o HDFS divide em blocos de 128 MB (tamanho padrao). Cada bloco e armazenado `dfs.replication` vezes. Com valor 1, so ha 1 copia. Se esse no morrer, o dado e perdido. |
| **Em producao** | Usa-se `3` ou mais. Cada replica fica em um DataNode diferente. Se um DataNode cai, os dados ainda existem nos outros 2. |

**`dfs.permissions` = `false`**

| Aspecto | Detalhe |
|---|---|
| **O que e** | Controla se o HDFS verifica permissoes de leitura/escrita/execucao nos arquivos. |
| **Valor padrao** | `true` (permissoes ativadas - como Linux: dono, grupo, outros) |
| **Por que false aqui?** | Para estudo e desenvolvimento, desabilitar permissoes evita erros como "Permission denied" quando voce tenta criar diretorios ou escrever arquivos. O usuario `hduser` pode fazer qualquer operacao no HDFS sem restricoes. |
| **Em producao** | **Sempre use `true`!** Sem permissoes, qualquer usuario pode apagar dados de qualquer outro. E um risco de seguranca grave. |

#### Analogia

Pense no `hdfs-site.xml` como as **regras do cofre**:
- `dfs.replication` = quantas copias da chave existem (1 copia = se perder, era)
- `dfs.permissions` = se o cofre tem tranca ou nao (false = cofre aberto para todos)

#### Outras propriedades uteis do hdfs-site.xml (nao usadas aqui, mas importantes)

| Propriedade | O que faz | Valor tipico |
|---|---|---|
| `dfs.blocksize` | Tamanho de cada bloco em bytes | `134217728` (128 MB) |
| `dfs.namenode.name.dir` | Onde o NameNode guarda metadados no disco | `/tmp/hadoop-hduser/dfs/name` |
| `dfs.datanode.data.dir` | Onde o DataNode guarda os blocos de dados | `/tmp/hadoop-hduser/dfs/data` |
| `dfs.namenode.http-address` | Endereco da Web UI do NameNode | `0.0.0.0:9870` |

---

### 5.6 config/yarn-site.xml - Configuracao do YARN

```xml
<?xml version="1.0"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
    </property>
</configuration>
```

#### O que e este arquivo?

O `yarn-site.xml` configura o **YARN** (Yet Another Resource Negotiator). YARN e o "gerente de recursos" do Hadoop - ele decide quais jobs rodam, quanto de memoria/CPU cada um recebe, e monitora a execucao.

#### O que e o YARN?

```
                    +-------------------+
                    |  ResourceManager   |  <-- Gerencia os recursos do cluster
                    |  (porta 8088)      |      Decide qual job roda quando
                    +---------+---------+
                              |
                    +---------+---------+
                    |   NodeManager     |  <-- Executa os jobs no no
                    |   (localhost)     |      Gerencia memoria e CPU local
                    +-------------------+
```

Sem YARN, voce pode rodar jobs MapReduce em modo "local" (1 processo so). **Com YARN**, os jobs rodam de forma distribuida e gerenciada, como em um cluster real.

#### O que cada propriedade faz?

**`yarn.nodemanager.aux-services` = `mapreduce_shuffle`**

| Aspecto | Detalhe |
|---|---|
| **O que e** | Define **servicos auxiliares** que o NodeManager executa. Servicos auxiliares sao processos extras que rodam junto com cada container de tarefa. |
| **Por que `mapreduce_shuffle`?** | Durante um job MapReduce, os dados saida da fase **Map** precisam ser transferidos para a fase **Reduce**. Esse processo se chama **shuffle**. O servico `mapreduce_shuffle` e o responsavel por essa transferencia. |
| **Sem essa configuracao** | Os jobs MapReduce falham com erro `No shuffle service found`. E obrigatorio para rodar MapReduce sobre YARN. |
| **Outros valores possiveis** | Voce pode ter servicos auxiliares customizados (ex: Spark shuffle), mas `mapreduce_shuffle` e o padrao para MapReduce. |

**`yarn.nodemanager.env-whitelist` = `JAVA_HOME,HADOOP_COMMON_HOME,...`**

| Aspecto | Detalhe |
|---|---|
| **O que e** | Lista de **variaveis de ambiente** que o NodeManager repassa do sistema para os containers dos jobs. |
| **Por que preciso?** | Quando o YARN inicia um container para rodar um Map ou Reduce, ele cria um processo Java novo. Esse processo precisa saber onde estao o Java (`JAVA_HOME`), o Hadoop (`HADOOP_COMMON_HOME`), e as configuracoes (`HADOOP_CONF_DIR`). Sem essa lista, essas variaveis nao seriam passadas e o job falharia. |
| **Cada variavel** | |
| `JAVA_HOME` | Onde o Java esta instalado. O job precisa para executar. |
| `HADOOP_COMMON_HOME` | Onde o Hadoop comum esta (bibliotecas compartilhadas). |
| `HADOOP_HDFS_HOME` | Onde o modulo HDFS esta (para ler/escrever dados). |
| `HADOOP_CONF_DIR` | Onde estao os arquivos XML de configuracao. |
| `CLASSPATH_PREPEND_DISTCACHE` | Cache de distribuicao (arquivos JAR compartilhados). |
| `HADOOP_YARN_HOME` | Onde o modulo YARN esta. |
| `HADOOP_MAPRED_HOME` | Onde o modulo MapReduce esta. |

#### Analogia

Pense no YARN como um **gerente de escritorio**:
- `ResourceManager` = o gerente geral que distribui tarefas
- `NodeManager` = o supervisor de cada mesa
- `mapreduce_shuffle` = o entregador que leva documentos da mesa do Map para a mesa do Reduce
- `env-whitelist` = a lista de informacoes (telefone, endereco, etc.) que o supervisor repassa para cada funcionario novo

#### Outras propriedades uteis do yarn-site.xml (nao usadas aqui)

| Propriedade | O que faz | Valor tipico |
|---|---|---|
| `yarn.nodemanager.resource.memory-mb` | Memoria total disponivel para containers | `8192` (8 GB) |
| `yarn.scheduler.minimum-allocation-mb` | Memoria minima por container | `1024` (1 GB) |
| `yarn.scheduler.maximum-allocation-mb` | Memoria maxima por container | `8192` (8 GB) |
| `yarn.resourcemanager.webapp.address` | Endereco da Web UI do YARN | `0.0.0.0:8088` |

---

### 5.7 scripts/docker-entrypoint.sh - Inicializacao automatica do container

#### O que e este arquivo?

O `docker-entrypoint.sh` e o **script de inicializacao** do container. Ele roda automaticamente toda vez que o container inicia (quando voce faz `docker compose up -d`). E o "interruptor geral" que liga todos os servicos do Hadoop, em ordem.

**Por que preciso de um script?** O Hadoop nao e um unico programa. Sao **5 servicos separados** que precisam iniciar em sequencia: SSH -> NameNode format -> HDFS -> YARN -> Diretorios. Se pular uma etapa, as proximas falham.

#### Fluxo visual do que o script faz

```
Container inicia
    |
    v
[1] Corrige permissoes do volume
    |
    v
[2] Inicia SSH
    |
    v
[3] Formata o NameNode (se primeira vez)
    |
    v
[4] Inicia HDFS (NameNode + DataNode + SecondaryNameNode)
    |
    v
[5] Inicia YARN (ResourceManager + NodeManager)
    |
    v
[6] Cria diretorios no HDFS (/tmp, /users, /jars)
    |
    v
[7] Desliga o Safe Mode
    |
    v
[8] Mantem container rodando (tail -f)
```

#### Linha a linha

```bash
#!/bin/bash
```
| Aspecto | Explicacao |
|---|---|
| **O que e** | Chamado de **shebang** (ou hashbang). E a primeira linha de todo script Bash. |
| **Para que serve** | Diz ao sistema operacional: "Use o programa `/bin/bash` para executar este script". Sem isso, o sistema nao saberia qual interpretador usar. |
| **O que e Bash** | Bash (Bourne Again Shell) e o interpretador de comandos mais comum em Linux. E a mesma coisa que o terminal que voce digita comandos. |

```bash
set -e
```
| Aspecto | Explicacao |
|---|---|
| **O que e** | Opcao do Bash chamada **"errexit"**. |
| **Para que serve** | Faz o script **parar imediatamente** se qualquer comando falhar (retornar codigo diferente de 0). |
| **Por que importante** | Se o SSH nao iniciar, o HDFS nao vai conseguir subir. Se o NameNode falhar, nao adianta tentar iniciar o YARN. Com `set -e`, o script para no primeiro erro em vez de continuar e gerar erros em cascata. |
| **Sem isso** | O script continuaria rodando mesmo com erros, e voce so perceberia o problema horas depois. |

```bash
sudo chown -R hduser:hduser /tmp/hadoop-hduser 2>/dev/null || true
```
| Aspecto | Explicacao |
|---|---|
| **`sudo`** | Executa como superusuario (root). O `hduser` so pode usar `sudo` porque configuramos isso no Dockerfile. |
| **`chown`** | Comando que muda o **dono** (change owner) de arquivos e diretorios. |
| **`-R`** | Recursivo: aplica a todos os arquivos e subdiretorios. |
| **`hduser:hduser`** | Novo dono e grupo. Formato `usuario:grupo`. Aqui, o usuario `hduser` e o grupo `hduser`. |
| **`/tmp/hadoop-hduser`** | Caminho do diretorio de dados do HDFS. E onde o NameNode e DataNode guardam seus arquivos no disco. |
| **`2>/dev/null`** | Redireciona mensagens de erro para `/dev/null` (descarta). Se o diretorio ainda nao existir, o comando daria erro, mas queremos que isso seja silencioso. |
| **`\|\| true`** | "Ou verdadeiro". Se o comando anterior falhar (codigo != 0), avalia como verdadeiro. Garante que esta linha nunca faca o script parar (por causa do `set -e`). |
| **Por que preciso?** | O Docker monta volumes como dono `root`. O Hadoop roda como `hduser`. Sem essa correcao, o Hadoop nao consegue criar arquivos no volume. |

```bash
sudo service ssh start
```
| Aspecto | Explicacao |
|---|---|
| **`service`** | Comando Linux para gerenciar servicos do sistema. |
| **`ssh`** | O servico SSH (Secure Shell). Permite conexao remota criptografada. |
| **`start`** | Inicia o servico. |
| **Por que o Hadoop precisa de SSH?** | O Hadoop usa SSH internamente para se comunicar entre nos (mesmo em single node). Os scripts `start-dfs.sh` e `start-yarn.sh` fazem SSH para `localhost` para iniciar cada processo em segundo plano. Sem SSH, esses scripts falham. |
| **Seguranca** | Como e dentro de um container isolado, SSH so e acessivel localmente. Nao expoe nada para fora. |

```bash
if [ ! -d "/tmp/hadoop-hduser/dfs/name" ]; then
    $HADOOP_HOME/bin/hdfs namenode -format && echo "OK: HDFS namenode format finished successfully!"
fi
```
| Aspecto | Explicacao |
|---|---|
| **`if [ ... ]; then ... fi`** | Estrutura condicional do Bash. Executa o bloco interno so se a condicao for verdadeira. |
| **`! -d`** | `!` = negacao (NOT). `-d` = "o caminho existe e e um diretorio?". Entao `! -d` = "o diretorio NAO existe?". |
| **`/tmp/hadoop-hduser/dfs/name`** | Caminho onde o NameNode guarda seus metadados (estrutura do sistema de arquivos). Se esse diretorio existe, o NameNode ja foi formatado antes. |
| **`$HADOOP_HOME/bin/hdfs`** | O binario `hdfs` do Hadoop. `$HADOOP_HOME` e a variavel de ambiente definida no Dockerfile que aponta para `/home/hduser/hadoop-3.3.6`. |
| **`namenode -format`** | Formata o NameNode. Isso **inicializa** o sistema de arquivos HDFS: cria a estrutura de diretorios em branco, gera um novo Cluster ID, etc. |
| **`&& echo "OK: ..."`** | Exibe mensagem de confirmacao apos o format. O `&&` so executa o `echo` se o format funcionou (retornou codigo 0). |
| **Por que so se o diretorio nao existe?** | Se voce formatar o NameNode quando ja existem dados, **todos os dados do HDFS sao apagados**. A verificacao evita perda acidental de dados ao reiniciar o container. |
| **Quando acontece?** | Apenas na **primeira vez** que o container sobe (ou apos `docker compose down -v` que apaga o volume). |

```bash
$HADOOP_HOME/sbin/start-dfs.sh
```
| Aspecto | Explicacao |
|---|---|
| **O que e** | Script oficial do Hadoop que inicia todos os servicos HDFS. |
| **O que ele faz internamente** | 1. Faz SSH para `0.0.0.0` e inicia o **NameNode** (gerenciador de metadados). 2. Faz SSH para `localhost` e inicia o **DataNode** (armazena blocos de dados). 3. Faz SSH para `myhdfs` e inicia o **SecondaryNameNode** (faz checkpoints). |
| **Processos iniciados** | NameNode (porta 9000/9870), DataNode (porta 9864/9866), SecondaryNameNode (porta 9868). |
| **Resultado esperado** | Voce vera mensagens como "Starting namenodes on [0.0.0.0]", "Starting datanodes", "Starting secondary namenodes". |

```bash
echo "YARNSTART = $YARNSTART"
if [[ -z $YARNSTART || $YARNSTART -ne 0 ]]; then
    echo "Starting YARN..."
    $HADOOP_HOME/sbin/start-yarn.sh
fi
```
| Aspecto | Explicacao |
|---|---|
| **`echo`** | Imprime mensagem na tela. Serve para aparecer nos logs do Docker. |
| **`$YARNSTART`** | Variavel de ambiente. Definida no `docker-compose.yml` como `YARNSTART=1`. Se nao definida, assume vazio. |
| **`[[ ... ]]`** | Teste condicional avancado do Bash (mais seguro que `[ ]`). |
| **`-z $YARNSTART`** | Verdadeiro se a variavel esta **vazia** (nao definida). |
| **`\|\|`** | Operador logico OU. A condicao e verdadeira se qualquer lado for verdadeiro. |
| **`$YARNSTART -ne 0`** | Verdadeiro se o valor e **diferente de 0** (`-ne` = not equal). |
| **Resumo da condicao** | "Se YARNSTART esta vazio OU se YARNSTART nao e zero, entao inicia o YARN". Isso significa: o padrao e iniciar YARN. So nao inicia se `YARNSTART=0` for explicitamente definido. |
| **`start-yarn.sh`** | Script oficial do Hadoop que inicia o **ResourceManager** (gerente de recursos) e o **NodeManager** (executor de tarefas). |

```bash
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /users
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /jars
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfs`** | Comando para interagir com o HDFS (Hadoop Distributed File System). Equivalente ao `mkdir`, `ls`, `cp` do Linux, mas para o sistema de arquivos distribuido. |
| **`-mkdir`** | Cria um diretorio no HDFS (nao no disco local!). |
| **`-p`** | "Parents": cria todos os diretorios intermediarios que nao existirem. Como `mkdir -p` do Linux. Se `/tmp` nao existe, cria; se ja existe, nao faz nada e nao da erro. |
| **`/tmp`** | Diretorio temporario no HDFS. Muitos jobs do Hadoop usam este diretorio para armazenar dados intermediarios. |
| **`/users`** | Diretorio base para usuarios. Alguns aplicativos do ecossistema Hadoop esperam que este diretorio exista. |
| **`/jars`** | Diretorio para armazenar arquivos JAR (aplicacoes Java empacotadas). Util quando voce quer rodar seus proprios jobs. |

```bash
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /tmp
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /users
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /jars
```
| Aspecto | Explicacao |
|---|---|
| **`chmod`** | Change mode: altera permissoes de acesso. |
| **`777`** | Permissao total: leitura (r) + escrita (w) + execucao (x) para dono, grupo e outros. Qualquer usuario pode fazer qualquer coisa nesses diretorios. |
| **Por que?** | Em ambiente de estudo, evita erros de "Permission denied". Qualquer job ou usuario pode escrever nesses diretorios. |
| **Em producao** | **Nunca faca isso!** Use permissoes especificas (ex: `755` ou `750`). |

```bash
$HADOOP_HOME/bin/hdfs dfsadmin -safemode leave
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfsadmin`** | Comando administrativo do HDFS. Para gerenciamento, nao para arquivos. |
| **`-safemode leave`** | Comando para **sair do modo seguro**. |
| **O que e Safe Mode?** | Quando o HDFS inicia, ele entra em "modo seguro" (read-only). Nesse modo, voce pode **ler** arquivos mas nao pode **escrever** ou **apagar**. E uma protecao para o Hadoop verificar a integridade dos dados antes de permitir escrita. |
| **Por que sair manualmente?** | Em um cluster real, o Hadoop sai do safe mode automaticamente apos verificar que um percentual minimo de blocos esta disponivel. Em single node com poucos dados, isso acontece muito rapido. Mas para garantir que nao ficamos travados, forçamos a saida. |

```bash
tail -f $HADOOP_HOME/logs/hadoop-*-namenode-*.log
```
| Aspecto | Explicacao |
|---|---|
| **`tail`** | Comando que mostra as **ultimas linhas** de um arquivo. |
| **`-f`** | "Follow": continua monitorando o arquivo e mostra novas linhas em tempo real (como um "tail -f" de log). |
| **`$HADOOP_HOME/logs/hadoop-*-namenode-*.log`** | Caminho do arquivo de log do NameNode. O `*` e um curinga que corresponde a qualquer texto (nome do usuario, hostname, etc.). |
| **Por que isso e necessario?** | Containers Docker **param** quando o processo principal termina. Se este script terminasse apos configurar tudo, o container seria encerrado e o Hadoop pararia. O `tail -f` e um processo que nunca termina, mantendo o container vivo indefinidamente. |
| **O que aparece** | Logs de atividade do NameNode: blocos sendo registrados, heartbeats do DataNode, conexoes de clientes, etc. |

---

### 5.8 scripts/test-wordcount.sh - Teste automatizado de MapReduce

#### O que e este arquivo?

O `test-wordcount.sh` e um script de **teste automatizado** que executa **dois testes** WordCount:
1. **Teste 1**: WordCount built-in do Hadoop (usa arquivos XML como dados de entrada)
2. **Teste 2**: WordCount customizado em Java (compila, empacota e roda com `lorem.txt`)

O WordCount e o "Hello World" do MapReduce. Ele:
1. Pega arquivos de texto como entrada
2. **Map**: Divide o texto em palavras e emite `(palavra, 1)` para cada ocorrencia
3. **Shuffle**: Agrupa todas as contagens da mesma palavra
4. **Reduce**: Soma todas as contagens de cada palavra
5. Resultado: lista com cada palavra e quantas vezes aparece

#### Fluxo visual do Teste 1 (built-in)

```
Arquivos XML de entrada (dados de configuracao do Hadoop)
    |
    v
[1] Criar diretorio /user/hduser/input no HDFS
    |
    v
[2] Upload dos 10 arquivos .xml para o HDFS
    |
    v
[3] Rodar job MapReduce WordCount do Hadoop (built-in)
    |
    v
[4] Listar arquivos de saida (_SUCCESS + part-r-00000)
    |
    v
[5] Mostrar as 20 primeiras palavras contadas
```

#### Fluxo visual do Teste 2 (customizado)

O Teste 2 chama o script `/home/hduser/run-custom-wordcount.sh`, que:
1. Compila os arquivos Java em `/home/hduser/wordcount/src/`
2. Empacota em JAR
3. Faz upload do `lorem.txt` para o HDFS
4. Roda o job MapReduce customizado
5. Mostra os resultados completos

#### Linha a linha

```bash
#!/bin/bash
set -e
```
| Aspecto | Explicacao |
|---|---|
| **`#!/bin/bash`** | Shebang: usa Bash para executar o script. |
| **`set -e`** | Para o script no primeiro erro. |

```bash
echo "============================================"
echo " Hadoop WordCount Tests"
echo "============================================"
echo ""
```
| Aspecto | Explicacao |
|---|---|
| **`echo`** | Imprime cabecalho no terminal identificando o inicio dos testes. |

```bash
echo "--- Test 1: Built-in WordCount (XML files) ---"
echo ""
```
| Aspecto | Explicacao |
|---|---|
| **O que faz** | Anuncia o primeiro teste. |

```bash
echo "[1/5] Creating HDFS directories..."
hdfs dfs -mkdir -p /user/hduser/input
```
| Aspecto | Explicacao |
|---|---|
| **`echo "[1/5]..."`** | Mostra progresso: passo 1 de 5. |
| **`hdfs dfs -mkdir`** | Cria um diretorio no HDFS. |
| **`-p`** | Cria todos os niveis (`/user`, `/user/hduser`, `/user/hduser/input`). Se ja existirem, nao da erro. |
| **`/user/hduser/input`** | Diretorio padrao de entrada do usuario `hduser` no HDFS. |

```bash
echo "[2/5] Uploading sample data to HDFS..."
hdfs dfs -put -f $HADOOP_HOME/etc/hadoop/*.xml /user/hduser/input
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfs -put`** | Faz upload do disco local para o HDFS. |
| **`-f`** | Force: sobrescreve se ja existir (permite rodar o teste varias vezes). |
| **`$HADOOP_HOME/etc/hadoop/*.xml`** | Caminho dos arquivos de entrada. O `*` seleciona todos os `.xml` do diretorio de configuracao. |
| **Resultado** | 10 arquivos XML ficam no HDFS em `/user/hduser/input/`. |

```bash
echo "[3/5] Running built-in WordCount MapReduce job..."
hdfs dfs -rm -r -f /user/hduser/output 2>/dev/null || true
hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar wordcount /user/hduser/input /user/hduser/output
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfs -rm -r -f`** | Remove o diretorio de saida previo se existir. O `|| true` evita erro se nao existir. |
| **`hadoop jar`** | Executa um arquivo JAR no Hadoop. |
| **`hadoop-mapreduce-examples-*.jar`** | JAR com exemplos que acompanha o Hadoop. |
| **`wordcount`** | Nome do exemplo WordCount dentro do JAR. |
| **`/user/hduser/output`** | Diretorio de saida (criado pelo job, nao pode existir previamente). |
| **Resultado** | Job roda completo: `map 100% reduce 100%`. |

```bash
echo "[4/5] Listing output files..."
hdfs dfs -ls /user/hduser/output
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfs -ls`** | Lista arquivos no HDFS. |
| **Resultado esperado** | `_SUCCESS` (confirmacao) e `part-r-00000` (resultados). |

```bash
echo "[5/5] Built-in WordCount results (top 20):"
echo "---"
hdfs dfs -cat /user/hduser/output/part-r-00000 | head -20
echo "..."
echo ""
```
| Aspecto | Explicacao |
|---|---|
| **`hdfs dfs -cat`** | Mostra conteudo de arquivo no HDFS. |
| **`head -20`** | Mostra apenas as primeiras 20 linhas. |
| **Formato** | Cada linha: `palavra<TAB>contagem`. |

```bash
echo "--- Test 2: Custom Java WordCount (lorem.txt) ---"
echo ""

/home/hduser/run-custom-wordcount.sh
```
| Aspecto | Explicacao |
|---|---|
| **`echo "--- Test 2..."`** | Anuncia o segundo teste. |
| **`/home/hduser/run-custom-wordcount.sh`** | Chama o script de WordCount customizado, que compila Java, empacota JAR, faz upload de dados, roda o job e exibe os resultados. |

---

### 5.9 Como baixar o Hadoop (hadoop-3.3.6.tar.gz)

O arquivo `hadoop-3.3.6.tar.gz` e o **proprio Hadoop empacotado**. E um arquivo compactado (~696 MB) contendo todos os binarios, bibliotecas e configuracoes do Hadoop. Ele precisa estar na pasta do projeto antes de fazer o build.

#### De onde vem?

O Hadoop e um projeto open-source da Apache Software Foundation. Os binarios oficiais sao distribuidos em:

| URL | Descricao |
|---|---|
| `https://dlcdn.apache.org/hadoop/common/` | **CDN oficial** (mais rapido). Contem apenas as versoes mais recentes. |
| `https://archive.apache.org/dist/hadoop/common/` | **Arquivo historico** (mais lento). Contem todas as versoes ja lancadas. |

#### Opcao 1: Baixar da CDN oficial (recomendado)

```bash
cd ~/Documents/Big\ Data/tutoriais/hadoop-docker

curl -L --progress-bar --max-time 600 \
    "https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz" \
    -o hadoop-3.3.6.tar.gz
```

| Parte do comando | Explicacao |
|---|---|
| **`curl`** | Ferramenta de linha de comando para baixar arquivos da internet. |
| **`-L`** | Follow redirects: se o servidor redirecionar para outra URL, o curl segue automaticamente. |
| **`--progress-bar`** | Mostra uma barra de progresso simples (`###=>    `) em vez das estatisticas padrao. |
| **`--max-time 600`** | Tempo maximo: 600 segundos (10 minutos). Se o download nao terminar em 10 minutos, aborta. |
| **`"https://dlcdn.apache.org/..."`** | URL do arquivo. O `dlcdn` e a CDN (Content Delivery Network) do Apache, que espalha copias pelo mundo para ser mais rapido. |
| **`-o hadoop-3.3.6.tar.gz`** | Output: salva o download com este nome de arquivo. |

**Resultado esperado**:
```
######################################################################## 100.0%
```

#### Opcao 2: Baixar do arquivo historico (se a CDN nao tiver a versao)

```bash
curl -L --progress-bar --max-time 1800 \
    "https://archive.apache.org/dist/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz" \
    -o hadoop-3.3.6.tar.gz
```

> **Atencao**: O `archive.apache.org` e **muito lento** (servidor unico). O download pode levar 10-30 minutos. Use `--max-time 1800` (30 minutos) para nao abortar cedo demais.

#### Opcao 3: Baixar pelo navegador

1. Acesse: https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/
2. Clique em `hadoop-3.3.6.tar.gz`
3. O navegador fara o download
4. Mova o arquivo para a pasta `tutoriais/hadoop-docker/`

#### Opcao 4: Baixar versao diferente (ex: 3.3.5 ou 3.4.0)

Substitua `3.3.6` pela versao desejada no URL:

```bash
# Exemplo: Hadoop 3.4.0
curl -L --progress-bar --max-time 600 \
    "https://dlcdn.apache.org/hadoop/common/hadoop-3.4.0/hadoop-3.4.0.tar.gz" \
    -o hadoop-3.4.0.tar.gz
```

> **Importante**: Se mudar a versao, tambem atualize o `HADOOP_VERSION` no `Dockerfile` e o nome do arquivo no `docker-compose.yml`.

#### Verificar que o download esta correto

```bash
ls -lh hadoop-3.3.6.tar.gz
```

**Resultado esperado** (tamanho proximo):
```
-rw-r--r--  1 leandroimail  staff   696M May 21 11:00 hadoop-3.3.6.tar.gz
```

Verificar o tipo do arquivo:

```bash
file hadoop-3.3.6.tar.gz
```

**Resultado esperado**:
```
hadoop-3.3.6.tar.gz: gzip compressed data, last modified: Sun Jun 18 09:37:18 2023, from Unix, original size modulo 2^32 1404344320
```

Se mostrar algo diferente (como "HTML document" ou "empty"), o download falhou ou baixou uma pagina de erro.

Verificar integridade com checksum SHA512:

```bash
curl -sL "https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz.sha512" | awk '{print $1}'
shasum -a 512 hadoop-3.3.6.tar.gz | awk '{print $1}'
```

Os dois valores devem ser **identicos**. Se forem diferentes, o arquivo esta corrompido - baixe novamente.

#### Troubleshooting do download

| Problema | Solucao |
|---|---|
| Download lento / timeout | Use `--max-time 1800` e tente o `archive.apache.org`. Ou baixe pelo navegador com gerenciador de downloads. |
| Arquivo muito menor que 696 MB | Download truncado. Apague e baixe novamente. |
| "gzip: not in gzip format" no build | O arquivo baixou corrompido ou como HTML (erro 404). Verifique com `file hadoop-3.3.6.tar.gz`. |
| Versao nao encontrada na CDN | Versoes antigas sao removidas da CDN. Use `archive.apache.org` ou escolha uma versao mais recente. |

---

## 6. Build da imagem Docker

### 6.1 Abrir o terminal e navegar ate a pasta do projeto

```bash
cd ~/Documents/Big\ Data/tutoriais/hadoop-docker
```

> **Nota**: O `\` antes do espaco e necessario porque "Big Data" tem um espaco no nome. Sem ele, o terminal entenderia como dois caminhos separados.

**Resultado esperado**: O terminal muda para o diretorio. Nada e impresso na tela.

### 6.2 Verificar que os arquivos estao la

```bash
ls -la
```

**Resultado esperado**:
```
total 710280
drwxr-xr-x  8 leandroimail  staff       256 May 21 11:00 .
drwxr-xr-x  4 leandroimail  staff       128 May 21 10:30 ..
-rw-r--r--  1 leandroimail  staff       921 May 21 11:00 Dockerfile
drwxr-xr-x  5 leandroimail  staff       160 May 21 10:30 config
-rw-r--r--  1 leandroimail  staff       271 May 21 11:00 docker-compose.yml
-rw-r--r--  1 leandroimail  staff  729297366 May 21 11:00 hadoop-3.3.6.tar.gz
drwxr-xr-x  3 leandroimail  staff        96 May 21 10:30 scripts
```

> **Importante**: O arquivo `hadoop-3.3.6.tar.gz` deve ter ~696 MB. Se estiver muito menor, esta corrompido.

### 6.3 Construir a imagem Docker

```bash
docker compose build
```

**O que acontece**:
1. Docker le o `Dockerfile`
2. Baixa a imagem base `eclipse-temurin:8-jdk-focal` (~400 MB, se ja nao estiver em cache)
3. Instala pacotes (sudo, curl, ssh)
4. Cria o usuario hduser
5. Copia o Hadoop para dentro da imagem
6. Configura tudo
7. Gera a imagem final `hadoop-single-node:3.3.6`

**Resultado esperado** (ultimas linhas):
```
 ...
 #24 exporting to image
 #24 exporting layers done
 #24 naming to docker.io/library/hadoop-single-node:3.3.6 done
 #24 DONE 0.1s

 Image hadoop-single-node:3.3.6 Built
```

**Tempo estimado**: 1-5 minutos (dependendo da velocidade do disco e cache).

### 6.4 Verificar que a imagem foi criada

```bash
docker images | grep hadoop
```

**Resultado esperado**:
```
hadoop-single-node   3.3.6   xxxxxxxxxxxx   x minutes ago   ~XXX MB
```

---

## 7. Iniciar o container

### 7.1 Subir o container

```bash
docker compose up -d
```

**O que acontece**:
1. Docker cria uma rede virtual para o container
2. Cria um volume para persistir dados
3. Cria e inicia o container com nome `hadoop`
4. O `docker-entrypoint.sh` executa automaticamente:
   - Inicia SSH
   - Formata o NameNode (se primeira vez)
   - Inicia HDFS (NameNode, DataNode, SecondaryNameNode)
   - Inicia YARN (ResourceManager, NodeManager)
   - Cria diretorios no HDFS

**Resultado esperado**:
```
 Network hadoop-docker_default Creating
 Network hadoop-docker_default Created
 Volume hadoop-docker_hadoop-data Creating
 Volume hadoop-docker_hadoop-data Created
 Container hadoop Creating
 Container hadoop Created
 Container hadoop Starting
 Container hadoop Started
```

> O `-d` significa "detached" - roda em segundo plano. Sem ele, o terminal ficaria preso nos logs.

### 7.2 Aguardar o Hadoop inicializar

O Hadoop leva **~20-30 segundos** para iniciar completamente. Aguarde e depois verifique os logs:

```bash
docker logs hadoop 2>&1 | tail -15
```

**Resultado esperado** (ultimas linhas):
```
Safe mode is OFF

==========================================
 Hadoop Single Node Cluster is ready!
 HDFS Web UI:  http://localhost:9870
 YARN Web UI:  http://localhost:8088
==========================================
```

Se voce vir a mensagem **"Hadoop Single Node Cluster is ready!"**, tudo funcionou!

---

## 8. Verificar se esta funcionando

### 8.1 Verificar o container esta rodando

```bash
docker ps
```

**Resultado esperado**:
```
CONTAINER ID   IMAGE                       STATUS          PORTS                                                              NAMES
xxxxxxxxxxxx   hadoop-single-node:3.3.6    Up X minutes    0.0.0.0:9000->9000/tcp, 0.0.0.0:8088->8088/tcp, ...               hadoop
```

O `STATUS` deve ser **"Up X minutes"**. Se estiver "Exited", algo deu errado - veja a [secao de troubleshooting](#14-troubleshooting-e-hotfix).

### 8.2 Verificar os processos Java dentro do container

```bash
docker exec hadoop jps
```

**Resultado esperado**:
```
XXXX NameNode
XXXX DataNode
XXXX SecondaryNameNode
XXXX ResourceManager
XXXX NodeManager
XXXX Jps
```

Voce deve ver pelo menos 5 processos: **NameNode, DataNode, SecondaryNameNode, ResourceManager, NodeManager**. Se algum estiver faltando, veja o troubleshooting.

### 8.3 Verificar a Web UI do HDFS

Abra o navegador e acesse:

```
http://localhost:9870
```

**Resultado esperado**: Uma pagina com o titulo "NameNode" mostrando informacoes do HDFS, incluindo:
- **Capacity**: espaco total disponivel
- **Live Nodes**: deve mostrar 1 no vivo
- **Decommissioning Nodes**: deve ser 0

### 8.4 Verificar a Web UI do YARN

Abra o navegador e acesse:

```
http://localhost:8088
```

**Resultado esperado**: Uma pagina com o titulo "ResourceManager" mostrando:
- **Active Nodes**: deve ser 1
- **Memory Total**: memoria disponivel para jobs

---

## 9. Entrar no container e explorar

### 9.1 Abrir um terminal dentro do container

```bash
docker exec -it hadoop bash
```

**Resultado esperado**: O prompt muda para:
```
hduser@myhdfs:~$
```

Agora voce esta **dentro** do container Hadoop. Todos os comandos Hadoop estao disponiveis.

### 9.2 Verificar a versao do Hadoop

```bash
hadoop version
```

**Resultado esperado**:
```
Hadoop 3.3.6
Source code repository https://github.com/apache/hadoop.git -r ...
Compiled by ... on ...
...
```

### 9.3 Listar arquivos no HDFS (raiz)

```bash
hdfs dfs -ls /
```

**Resultado esperado**:
```
Found 3 items
drwxrwxrwx   - hduser supergroup          0 2026-05-21 14:36 /jars
drwxrwxrwx   - hduser supergroup          0 2026-05-21 14:36 /tmp
drwxrwxrwx   - hduser supergroup          0 2026-05-21 14:36 /users
```

### 9.4 Ver informacoes do HDFS

```bash
hdfs dfsadmin -report
```

**Resultado esperado**:
```
Live datanodes (1):

Name: 192.168.x.x:9866 (myhdfs)
...
Configured Capacity: XXXXXXXXXXXX
...
```

### 9.5 Criar um diretorio de teste

```bash
hdfs dfs -mkdir /meu-teste
hdfs dfs -ls /
```

**Resultado esperado** (agora aparece o novo diretorio):
```
Found 4 items
drwxrwxrwx   - hduser supergroup          0 ... /jars
drwxr-xr-x   - hduser supergroup          0 ... /meu-teste
drwxrwxrwx   - hduser supergroup          0 ... /tmp
drwxrwxrwx   - hduser supergroup          0 ... /users
```

### 9.6 Criar um arquivo e fazer upload

```bash
echo "ola mundo hadoop big data" > /tmp/teste.txt
hdfs dfs -put /tmp/teste.txt /meu-teste/
hdfs dfs -cat /meu-teste/teste.txt
```

**Resultado esperado**:
```
ola mundo hadoop big data
```

### 9.7 Sair do container

```bash
exit
```

> O container continua rodando em segundo plano mesmo depois de voce sair.

---

## 10. Rodar o teste WordCount

O WordCount e o "Hello World" do Hadoop. Ele conta quantas vezes cada palavra aparece nos arquivos de entrada.

### 10.1 Executar o script de teste

```bash
docker exec hadoop bash ./test-wordcount.sh
```

**Resultado esperado** (resumido):
```
=== Hadoop WordCount Test ===
[1/5] Creating HDFS directories...
[2/5] Uploading sample data to HDFS...
[3/5] Running WordCount MapReduce job...
...
2026-05-21 ... INFO mapreduce.Job:  map 100% reduce 100%
...
[4/5] Listing output files...
Found 2 items
-rw-r--r--   1 hduser supergroup          0 ... /user/hduser/output/_SUCCESS
-rw-r--r--   1 hduser supergroup      10173 ... /user/hduser/output/part-r-00000
[5/5] WordCount results:
---
"*"     22
"AS     7
"License");    7
...
=== Test complete! ===
```

**O que cada parte significa**:

| Saida | Significado |
|---|---|
| `map 100% reduce 100%` | O job completou com sucesso! |
| `_SUCCESS` | Arquivo vazio que confirma que o job terminou |
| `part-r-00000` | Arquivo com os resultados (palavra \t contagem) |
| `"*"     22` | A palavra `"*"` aparece 22 vezes nos arquivos |

### 10.2 Rodar o WordCount manualmente (passo a passo)

Se preferir rodar cada comando individualmente:

```bash
# Entrar no container
docker exec -it hadoop bash

# Criar diretorio de entrada
hdfs dfs -mkdir -p /user/hduser/input

# Upload dos arquivos de configuracao como dados de teste
hdfs dfs -put -f $HADOOP_HOME/etc/hadoop/*.xml /user/hduser/input

# Rodar o job WordCount
hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar wordcount /user/hduser/input /user/hduser/output

# Ver o resultado
hdfs dfs -cat /user/hduser/output/part-r-00000

# Sair
exit
```

### 10.3 Limpar dados de teste (opcional)

```bash
docker exec hadoop hdfs dfs -rm -r /user/hduser/output
```

**Resultado esperado**:
```
Deleted /user/hduser/output
```

---

## 11. Comandos do dia a dia

### Gerenciamento do container

```bash
# Subir o container
docker compose up -d

# Ver status
docker ps

# Ver logs em tempo real
docker logs -f hadoop

# Ver ultimas 50 linhas de log
docker logs --tail 50 hadoop

# Entrar no container
docker exec -it hadoop bash

# Parar o container (dados persistem!)
docker compose down

# Parar e apagar os dados
docker compose down -v
```

### Comandos HDFS uteis (dentro do container)

```bash
# Listar arquivos
hdfs dfs -ls /caminho

# Criar diretorio
hdfs dfs -mkdir /novo-diretorio

# Upload de arquivo local para HDFS
hdfs dfs -put arquivo-local.txt /caminho/hdfs/

# Download de HDFS para local
hdfs dfs -get /caminho/hdfs/arquivo.txt ./

# Ver conteudo de arquivo
hdfs dfs -cat /caminho/arquivo.txt

# Apagar arquivo
hdfs dfs -rm /caminho/arquivo.txt

# Apagar diretorio recursivamente
hdfs dfs -rm -r /caminho/diretorio

# Ver espaco usado
hdfs dfs -du -h /

# Ver status do HDFS
hdfs dfsadmin -report

# Ver modo de seguranca
hdfs dfsadmin -safemode get

# Sair do modo de seguranca
hdfs dfsadmin -safemode leave
```

### Reiniciar servicos Hadoop (dentro do container)

```bash
# Parar tudo
stop-yarn.sh
stop-dfs.sh

# Iniciar tudo
start-dfs.sh
start-yarn.sh

# Verificar processos
jps
```

---

## 12. Parar e remover tudo

### 12.1 Parar o container (mantem dados)

```bash
docker compose down
```

**Resultado esperado**:
```
 Container hadoop Stopping
 Container hadoop Stopped
 Container hadoop Removing
 Container hadoop Removed
 Network hadoop-docker_default Removing
 Network hadoop-docker_default Removed
```

### 12.2 Parar e apagar tudo (incluindo dados)

```bash
docker compose down -v
```

> **Cuidado**: O `-v` apaga o volume com todos os dados do HDFS. Use so quando quiser comecar do zero.

### 12.3 Apagar a imagem Docker

```bash
docker rmi hadoop-single-node:3.3.6
```

---

## 13. WordCount Customizado em Java - Passo a Passo Manual

Nesta secao voce vai **digitar cada comando manualmente** para entender o fluxo completo: compilar codigo Java, empacotar em JAR, copiar dados para o HDFS, rodar o job MapReduce e ler o resultado.

### 13.1 O que sao os arquivos Java

O projeto inclui 3 classes Java que implementam um WordCount MapReduce do zero:

| Arquivo | O que faz |
|---|---|
| `WordCountApplication.java` | Classe principal. Configura o job (qual Mapper, qual Reducer, caminhos de entrada/saida) e submete ao Hadoop. |
| `WordCountMapper.java` | Recebe cada linha do texto de entrada, divide em palavras e emite `(palavra, 1)` para cada uma. |
| `WordCountReducer.java` | Recebe todas as contagens de uma mesma palavra e soma: `(palavra, [1,1,1,...])` -> `(palavra, total)`. |

Esses arquivos ja estao dentro do container em `/home/hduser/wordcount/src/`.

O arquivo de dados `lorem.txt` (texto variado: Lorem Ipsum, Pirate Ipsum, Pompy Ipsum, etc.) esta em `/home/hduser/wordcount/data/`.

### 13.2 Entrar no container

```bash
docker exec -it hadoop bash
```

**Resultado esperado**:
```
hduser@myhdfs:~$
```

### 13.3 Navegar nos diretorios do projeto

```bash
ls wordcount/
```

**Resultado esperado**:
```
data  src
```

```bash
ls wordcount/src/
```

**Resultado esperado**:
```
WordCountApplication.java  WordCountMapper.java  WordCountReducer.java
```

```bash
ls wordcount/data/
```

**Resultado esperado**:
```
lorem.txt
```

### 13.4 Ver o conteudo do arquivo de entrada

```bash
head -5 wordcount/data/lorem.txt
```

**Resultado esperado**:
```
Classic Lorem Ipsum Filler Text:
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
Fusce ac turpis quis ligula lacinia aliquet. Mauris ipsum. Nulla metus metus, ullamcorper vel, tincidunt sed, euismod in, nibh. Quisque volutpat condimentum velit. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Nam nec ante.
Vestibulum sapien. Proin quam. Etiam ultrices. Suspendisse in justo eu magna luctus suscipit. Sed lectus. Integer euismod lacus luctus magna.  Integer id quam. Morbi mi. Quisque nisl felis, venenatis tristique, dignissim in, ultrices sit amet, augue. Proin sodales libero eget ante.
```

### 13.5 Criar diretorio de build e compilar os arquivos Java

```bash
mkdir -p wordcount/build
```

```bash
javac -classpath "$(hadoop classpath)" -d wordcount/build wordcount/src/*.java
```

**O que este comando faz**:

| Parte | Explicacao |
|---|---|
| `javac` | Compilador Java. Transforma `.java` em `.class` (bytecode). |
| `-classpath "$(hadoop classpath)"` | Diz ao compilador onde encontrar as classes do Hadoop (`Text`, `IntWritable`, `Mapper`, `Reducer`, etc.). O comando `hadoop classpath` retorna todos os JARs do Hadoop. |
| `-d wordcount/build` | Diretorio onde os `.class` compilados serao salvos. |
| `wordcount/src/*.java` | Os 3 arquivos fonte Java. |

**Resultado esperado**: Nenhuma mensagem de erro. Se compilou com sucesso, so aparece o prompt novamente.

Verificar que os `.class` foram gerados:

```bash
ls wordcount/build/
```

**Resultado esperado**:
```
WordCountApplication.class  WordCountMapper.class  WordCountReducer.class
```

### 13.6 Empacotar em arquivo JAR

```bash
jar cf wordcount/wordcount.jar -C wordcount/build .
```

**O que este comando faz**:

| Parte | Explicacao |
|---|---|
| `jar` | Ferramenta Java para empacotar arquivos em JAR (Java ARchive). E como um `.zip` para classes Java. |
| `cf` | `c` = criar novo arquivo, `f` = nome do arquivo a criar. |
| `wordcount/wordcount.jar` | Nome do JAR que sera criado. |
| `-C wordcount/build .` | Entra no diretorio `build` e inclui tudo (`.`) no JAR. |

Verificar:

```bash
ls -lh wordcount/wordcount.jar
```

**Resultado esperado** (tamanho pode variar):
```
-rw-r--r-- 1 hduser supergroup 4.2K ... wordcount/wordcount.jar
```

### 13.7 Copiar o arquivo lorem.txt para o HDFS

```bash
hdfs dfs -mkdir -p /user/hduser/custom-input
```

```bash
hdfs dfs -put wordcount/data/lorem.txt /user/hduser/custom-input/
```

Verificar que o arquivo esta no HDFS:

```bash
hdfs dfs -ls /user/hduser/custom-input/
```

**Resultado esperado**:
```
Found 1 items
-rw-r--r--   1 hduser supergroup       9634 ... /user/hduser/custom-input/lorem.txt
```

### 13.8 Rodar o WordCount customizado

```bash
hadoop jar wordcount/wordcount.jar WordCountApplication /user/hduser/custom-input /user/hduser/custom-output
```

**O que este comando faz**:

| Parte | Explicacao |
|---|---|
| `hadoop jar` | Diz ao Hadoop para executar um JAR. |
| `wordcount/wordcount.jar` | O JAR que compilamos e empacotamos. |
| `WordCountApplication` | Nome da classe principal (com o metodo `main`). |
| `/user/hduser/custom-input` | Diretorio HDFS de entrada (onde esta o `lorem.txt`). |
| `/user/hduser/custom-output` | Diretorio HDFS de saida (sera criado pelo Hadoop). **Nao pode existir previamente!** |

**Resultado esperado** (ultimas linhas):
```
...
INFO mapreduce.Job:  map 100% reduce 100%
...
INFO mapreduce.Job: Job job_local... completed successfully
```

### 13.9 Navegar nos diretorios HDFS e ver o resultado

Listar o diretorio de saida:

```bash
hdfs dfs -ls /user/hduser/custom-output/
```

**Resultado esperado**:
```
Found 2 items
-rw-r--r--   1 hduser supergroup          0 ... /user/hduser/custom-output/_SUCCESS
-rw-r--r--   1 hduser supergroup       9256 ... /user/hduser/custom-output/part-r-00000
```

| Arquivo | O que e |
|---|---|
| `_SUCCESS` | Arquivo vazio. Confirma que o job terminou com sucesso. |
| `part-r-00000` | Arquivo com o resultado. Cada linha: `palavra<TAB>contagem`. |

Ver as 20 primeiras palavras contadas:

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | head -20
```

**Resultado esperado**:
```
"Bulkington!	1
"That's	1
"dark	1
'avin	1
'tis	1
(Herman	1
(though	1
A	1
Alleghanian	1
Alright,	1
...
```

Ver as 20 palavras mais frequentes (ordenadas por contagem):

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | sort -t$'\t' -k2 -nr | head -20
```

**Resultado esperado**:
```
the	60
of	38
and	30
to	25
a	47
...
```

Ver o total de palavras unicas:

```bash
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | wc -l
```

**Resultado esperado**:
```
1045
```

### 13.10 Copiar o resultado do HDFS para o sistema de arquivos local

```bash
hdfs dfs -get /user/hduser/custom-output/part-r-00000 wordcount/result.txt
```

```bash
head -10 wordcount/result.txt
```

**Resultado esperado**:
```
"Bulkington!	1
"That's	1
"dark	1
'avin	1
'tis	1
(Herman	1
(though	1
A	1
Alleghanian	1
Alright,	1
```

### 13.11 Navegar pela estrutura completa do HDFS

```bash
hdfs dfs -ls -R /
```

**Resultado esperado**:
```
/jars
/tmp
/users
/user/hduser/custom-input
/user/hduser/custom-input/lorem.txt
/user/hduser/custom-output
/user/hduser/custom-output/_SUCCESS
/user/hduser/custom-output/part-r-00000
...
```

Ver espaco usado no HDFS:

```bash
hdfs dfs -du -h /
```

**Resultado esperado** (valores aproximados):
```
9.4 K  /jars
9.4 K  /tmp
0      /users
9.4 K  /user/hduser/custom-input
9.0 K  /user/hduser/custom-output
...
```

### 13.12 Limpar dados de teste (opcional)

```bash
hdfs dfs -rm -r /user/hduser/custom-output
hdfs dfs -rm -r /user/hduser/custom-input
```

### 13.13 Sair do container

```bash
exit
```

### 13.14 Resumo completo dos comandos (copiar e colar)

Para referencia rapida, todos os comandos em sequencia:

```bash
# Entrar no container
docker exec -it hadoop bash

# Navegar
ls wordcount/src/
ls wordcount/data/

# Compilar Java
mkdir -p wordcount/build
javac -classpath "$(hadoop classpath)" -d wordcount/build wordcount/src/*.java
ls wordcount/build/

# Empacotar JAR
jar cf wordcount/wordcount.jar -C wordcount/build .

# Copiar dados para o HDFS
hdfs dfs -mkdir -p /user/hduser/custom-input
hdfs dfs -put wordcount/data/lorem.txt /user/hduser/custom-input/
hdfs dfs -ls /user/hduser/custom-input/

# Rodar o WordCount customizado
hadoop jar wordcount/wordcount.jar WordCountApplication /user/hduser/custom-input /user/hduser/custom-output

# Ver resultado
hdfs dfs -ls /user/hduser/custom-output/
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | head -20
hdfs dfs -cat /user/hduser/custom-output/part-r-00000 | sort -t$'\t' -k2 -nr | head -20

# Copiar resultado para local
hdfs dfs -get /user/hduser/custom-output/part-r-00000 wordcount/result.txt

# Navegar no HDFS
hdfs dfs -ls -R /
hdfs dfs -du -h /

# Sair
exit
```

### 13.15 Versao automatizada (um comando so)

Se preferir rodar tudo automaticamente (compilar, empacotar, upload, executar e mostrar resultado):

```bash
docker exec hadoop bash /home/hduser/run-custom-wordcount.sh
```

Ou rodar ambos os testes (built-in + customizado):

```bash
docker exec hadoop bash /home/hduser/test-wordcount.sh
```

---

## 14. Troubleshooting e Hotfix

### Problema: Container nao inicia (status "Exited")

**Sintomas**: `docker ps` nao mostra o container, ou mostra "Exited".

**Diagnostico**:
```bash
docker logs hadoop 2>&1 | tail -30
```

**Solucoes possiveis**:
1. Verifique se o Docker Desktop esta rodando
2. Verifique se as portas 9870, 8088, 9000, 9864 nao estao em uso:
   ```bash
   lsof -i :9870
   lsof -i :8088
   ```
3. Se portas estiverem ocupadas, pare o servico que as usa ou altere as portas no `docker-compose.yml`

---

### Problema: "Cannot create directory /tmp/hadoop-hduser/dfs/name/current"

**Sintomas**: Nos logs, erro de permissao ao formatar o namenode.

**Causa**: O volume Docker pertence ao root e o usuario hduser nao consegue escrever.

**Solucao**: Ja esta corrigido no `docker-entrypoint.sh` atual com:
```bash
sudo chown -R hduser:hduser /tmp/hadoop-hduser 2>/dev/null || true
```

Se persistir, recrie o container do zero:
```bash
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

---

### Problema: "Safe mode is ON" - HDFS em modo seguro

**Sintomas**: Ao tentar escrever no HDFS, recebe erro de safe mode.

**Solucao**:
```bash
docker exec hadoop hdfs dfsadmin -safemode leave
```

**Resultado esperado**:
```
Safe mode is OFF
```

---

### Problema: Porta ja em uso ("port is already allocated")

**Sintomas**: Ao rodar `docker compose up -d`, erro de porta ocupada.

**Solucao 1**: Encontrar e parar o processo que usa a porta:
```bash
# Descobrir quem usa a porta (exemplo: 9870)
lsof -i :9870
# Matar o processo
kill -9 <PID>
```

**Solucao 2**: Trocar a porta no `docker-compose.yml`:
```yaml
ports:
  - "19870:9870"   # Usa porta 19870 no host
```
Depois acesse `http://localhost:19870`.

---

### Problema: "gzip: stdin: not in gzip format" no build

**Sintomas**: Build falha ao descompactar o Hadoop.

**Causa**: O arquivo `hadoop-3.3.6.tar.gz` esta corrompido ou incompleto.

**Solucao**: Verifique o tamanho do arquivo:
```bash
ls -lh hadoop-3.3.6.tar.gz
```
Deve ter **~696 MB**. Se estiver menor, baixe novamente:
```bash
curl -L --max-time 600 "https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz" -o hadoop-3.3.6.tar.gz
```

---

### Problema: "WARN util.NativeCodeLoader: Unable to load native-hadoop library"

**Sintomas**: Mensagens de WARN frequentes nos logs.

**Causa**: Bibliotecas nativas do Hadoop nao estao compiladas para sua arquitetura (ARM/Apple Silicon).

**Impacto**: **Nenhum**. E apenas um aviso. O Hadoop funciona normalmente usando implementacoes Java puras.

**Silenciar (opcional)**: Dentro do container:
```bash
echo "export HADOOP_OPTS=\"-Djava.library.path=\"" >> ~/.bashrc
```

---

### Problema: "Connection refused" ao acessar HDFS

**Sintomas**: `hdfs dfs -ls` retorna "Connection refused".

**Solucao**: Verifique se o NameNode esta rodando:
```bash
docker exec hadoop jps
```

Se `NameNode` nao aparecer nos processos:
```bash
docker exec hadoop bash -c "start-dfs.sh"
```

---

### Problema: Container reinicia sozinho ou crasha

**Sintomas**: Container fica reiniciando.

**Diagnostico**:
```bash
docker logs hadoop 2>&1
```

**Solucao**: Provavelmente erro de memoria. Aumente recursos do Docker Desktop:
1. Abra Docker Desktop -> Settings -> Resources
2. Aumente **Memory** para pelo menos 4 GB
3. Clique em "Apply & Restart"

---

### Problema: Nao consigo acessar http://localhost:9870

**Diagnostico passo a passo**:

1. Container esta rodando?
   ```bash
   docker ps | grep hadoop
   ```
   Se nao aparecer: `docker compose up -d`

2. Portas estao mapeadas?
   ```bash
   docker port hadoop
   ```
   Deve mostrar:
   ```
   9000/tcp -> 0.0.0.0:9000
   8088/tcp -> 0.0.0.0:8088
   9864/tcp -> 0.0.0.0:9864
   9870/tcp -> 0.0.0.0:9870
   ```

3. NameNode esta rodando?
   ```bash
   docker exec hadoop jps | grep NameNode
   ```

4. Testar conexao HTTP:
   ```bash
   curl -s http://localhost:9870 | head -5
   ```

---

### Problema: "Your endpoint configuration is wrong"

**Sintomas**: Ao rodar comandos HDFS, erro sobre hostname ou port.

**Causa**: O Hadoop nao consegue resolver o hostname `myhdfs`.

**Solucao**: Dentro do container:
```bash
echo "127.0.0.1 myhdfs" | sudo tee -a /etc/hosts
```

---

### Problema: Quero comecar tudo do zero

```bash
# Parar tudo e apagar volumes
docker compose down -v

# Apagar a imagem
docker rmi hadoop-single-node:3.3.6

# Reconstruir sem cache
docker compose build --no-cache

# Subir novamente
docker compose up -d
```

---

### Referencia rapida de portas

| Porta | Servico | URL |
|---|---|---|
| 9870 | HDFS NameNode Web UI | http://localhost:9870 |
| 8088 | YARN ResourceManager Web UI | http://localhost:8088 |
| 9000 | HDFS cliente (programatico) | hdfs://localhost:9000 |
| 9864 | DataNode Web UI | http://localhost:9864 |

---

### Referencia rapida de processos (jps)

| Processo | O que faz | Obrigatorio? |
|---|---|---|
| **NameNode** | Gerencia metadados do HDFS | Sim |
| **DataNode** | Armazena blocos de dados | Sim |
| **SecondaryNameNode** | Faz checkpoints do NameNode | Sim |
| **ResourceManager** | Gerencia recursos do YARN | Sim (para MapReduce) |
| **NodeManager** | Executa tarefas no no | Sim (para MapReduce) |
| **Jps** | Proprio comando `jps` (info) | N/A |

---

> Tutorial gerado em maio de 2026. Baseado no projeto rancavil/hadoop-single-node-cluster, adaptado com Hadoop 3.3.6, docker-compose, volume persistente, YARN habilitado e script de teste automatizado.
