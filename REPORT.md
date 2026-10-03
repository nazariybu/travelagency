# Report: Containerization of the Travel Agency project

Date: 03.10.2026

Project: https://github.com/nazariybu/travelagency

## Goal

Run the Travel Agency web application in Docker containers

## What was done

1. **Docker was installed** on the virtual machine, together with Docker Compose and Git.
2. **A `Dockerfile` was written.** It has two stages: the first stage builds the project with Maven and Java 17, and the second stage runs the `.war` file in Tomcat 9.
3. **A `docker-compose.yml` file was written.** It describes two containers: `app` (the application) and `db` (the MySQL 8 database).
4. **A `.env` file was created** for the database name, user and passwords. This file is not saved in Git.
5. **A `.dockerignore` file was added**, so Docker does not copy files it does not need.
6. **The containers were built and started** with one command: `docker compose up -d --build`.
7. **The application was opened** in the browser on port 8080.
8. **A guide `DOCKER.md` was written** with steps, diagrams and the file structure.


## Result

The application runs in two containers. The `app` container starts only after the database is ready. The database files are kept in a Docker volume. The whole project starts with one command.

## Files added

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the application image |
| `docker-compose.yml` | Describes the two containers |
| `.dockerignore` | Lists the files Docker does not copy |
| `.env` | Keeps the passwords (not in Git) |
| `DOCKER.md` | The guide |
| `REPORT.md` | This report |
