# Report: Travel Agency on Proxmox

**Date:** 03.10.2026
**Project:** https://github.com/nazariybu/travelagency

## Goal

Deploy the Travel Agency web application on two virtual machines in Proxmox:
one for the database and one for the application.

## Setup

| VM | Role | IP | Software |
|---|---|---|---|
| `vm-db` | Database | 192.168.18.101 | Ubuntu 22.04, MySQL 8 |
| `vm-app` | Application | 192.168.18.102 | Ubuntu 22.04, Java 17, Maven, Tomcat 9 |

## What was done

**vm-db**

1. Installed MySQL and opened it for the local network (`bind-address = 0.0.0.0`).
2. Created the database `travelagency` and the user `travel`.

**vm-app**

1. Installed Java 17, Maven, Tomcat 9 and Git.
2. Built the project with `mvn clean package`.
3. Gave Tomcat the database address, user and password as environment variables.
4. Deployed the WAR file as `ROOT.war` and started Tomcat.


## Result

- [ ] vm-app connects to MySQL on vm-db
- [ ] Tomcat is running
- [ ] Site opens at `http://192.168.18.102:8080/`
