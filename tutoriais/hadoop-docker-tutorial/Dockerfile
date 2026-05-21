FROM eclipse-temurin:8-jdk-focal

RUN apt-get update -y \
    && export DEBIAN_FRONTEND=noninteractive && apt-get install -y --no-install-recommends \
        sudo \
        curl \
        ssh \
    && apt-get clean

RUN useradd -m hduser \
    && echo "hduser:supergroup" | chpasswd \
    && adduser hduser sudo \
    && echo "hduser     ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY config/ssh_config /etc/ssh/ssh_config

WORKDIR /home/hduser
USER hduser

RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa \
    && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys \
    && chmod 0600 ~/.ssh/authorized_keys

ENV HADOOP_VERSION=3.3.6
ENV HADOOP_HOME=/home/hduser/hadoop-${HADOOP_VERSION}

COPY hadoop-${HADOOP_VERSION}.tar.gz /home/hduser/hadoop.tar.gz
RUN tar -xzf /home/hduser/hadoop.tar.gz -C /home/hduser/ \
    && rm -f /home/hduser/hadoop.tar.gz \
    && rm -rf ${HADOOP_HOME}/share/doc

ENV HDFS_NAMENODE_USER=hduser
ENV HDFS_DATANODE_USER=hduser
ENV HDFS_SECONDARYNAMENODE_USER=hduser
ENV YARN_RESOURCEMANAGER_USER=hduser
ENV YARN_NODEMANAGER_USER=hduser

RUN echo "export JAVA_HOME=/opt/java/openjdk/" >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

COPY config/core-site.xml $HADOOP_HOME/etc/hadoop/
COPY config/hdfs-site.xml $HADOOP_HOME/etc/hadoop/
COPY config/yarn-site.xml $HADOOP_HOME/etc/hadoop/

COPY scripts/docker-entrypoint.sh $HADOOP_HOME/etc/hadoop/
COPY scripts/test-wordcount.sh /home/hduser/
COPY scripts/run-custom-wordcount.sh /home/hduser/

RUN sudo chmod +x $HADOOP_HOME/etc/hadoop/docker-entrypoint.sh \
    && sudo chmod +x /home/hduser/test-wordcount.sh \
    && sudo chmod +x /home/hduser/run-custom-wordcount.sh

COPY src/ /home/hduser/wordcount/src/
COPY data/ /home/hduser/wordcount/data/

RUN sudo chown -R hduser:hduser /home/hduser/wordcount

ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

EXPOSE 9000 9864 9870 8088

WORKDIR /usr/local/bin
RUN sudo ln -s ${HADOOP_HOME}/etc/hadoop/docker-entrypoint.sh .
WORKDIR /home/hduser

ENV YARNSTART=1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
