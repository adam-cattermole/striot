FROM maven:3.5-jdk-8

WORKDIR /opt/gen-broker

COPY src ./src

COPY pom.xml ./

RUN mvn compile && \
    mvn install

CMD ["java", "-jar", "target/gen-broker-1.0-SNAPSHOT.jar"]
