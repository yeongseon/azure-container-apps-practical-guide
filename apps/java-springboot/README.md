# Java Reference App (Spring Boot)

Minimal Spring Boot application that backs the [Java language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/java/). It demonstrates the Container Apps runtime contract for a Java workload: listen on `$PORT` (default `8000`), emit structured JSON logs to stdout via Logback, expose Spring Boot Actuator health, and export telemetry to Application Insights.

## Stack

- **Spring Boot 3.3** (`spring-boot-starter-web`, `spring-boot-starter-actuator`), Java 21.
- **applicationinsights-spring-boot-starter** for Application Insights.
- **logstash-logback-encoder** for JSON logging (`src/main/resources/logback-spring.xml`).
- Multi-stage `Dockerfile`: `maven:3.9-eclipse-temurin-21` build → `eclipse-temurin:21-jre-alpine` runtime, runs as non-root UID `1000`.

## Layout

```text
apps/java-springboot/
├── Dockerfile            # Multi-stage Maven build, EXPOSE 8000, USER 1000
├── pom.xml               # Spring Boot 3.3, Java 21, App Insights, logstash encoder
└── src/main/
    ├── java/com/example/demo/
    │   ├── DemoApplication.java
    │   └── controller/   # HealthController, InfoController, HomeController
    └── resources/
        ├── application.yml
        └── logback-spring.xml
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Landing response |
| GET | `/health` | Health check (`{status, timestamp}`) |
| GET | `/info` | Application and runtime info (Java version, revision, replica) |

Spring Boot Actuator (`spring-boot-starter-actuator`) also exposes operational endpoints under `/actuator`; see `src/main/resources/application.yml` for the exposure settings.

## Run locally

```bash
cd apps/java-springboot

# Run
mvn spring-boot:run

# Or build a jar and run it
mvn package
java -jar target/*.jar
```

Then:

```bash
curl http://localhost:8000/health
```

## Run in a container

```bash
cd apps/java-springboot
docker build --tag aca-java-guide:local .
docker run --rm --publish 8000:8000 aca-java-guide:local
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8000` | Ingress target port |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | *(unset)* | Application Insights connection string |
| `CONTAINER_APP_NAME` | `local` | Surfaced in `/info` (set by the platform) |
| `CONTAINER_APP_REVISION` | `local` | Surfaced in `/info` (set by the platform) |

## See Also

- [Java language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/java/) — local development through revisions and traffic splitting.
