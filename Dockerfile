# ---------- Stage 1: build the WAR (JDK 17: Lombok 1.18.20 does not work on JDK 21) ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
# Download dependencies first, so this layer is cached while only the code changes
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---------- Stage 2: run on Tomcat 9 + JRE 17 as a non-root user ----------
FROM tomcat:9.0-jre17-temurin-jammy

# Fixed UID/GID, so file owners are the same on every host
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /usr/local/tomcat --shell /usr/sbin/nologin app \
 && rm -rf /usr/local/tomcat/webapps/* \
 && chown -R app:app /usr/local/tomcat/logs /usr/local/tomcat/temp /usr/local/tomcat/work /usr/local/tomcat/webapps

# The app is deployed as ROOT, the same as Ansible does on the VMs
COPY --from=build --chown=app:app /src/target/TravelAgency.war /usr/local/tomcat/webapps/ROOT.war

USER 10001
EXPOSE 8080
CMD ["catalina.sh", "run"]
