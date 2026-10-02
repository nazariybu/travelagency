# Travel Agency: deploy on two Proxmox VMs

This guide installs the project on two Ubuntu 22.04 virtual machines.

| VM | Role | IP (example) |
|---|---|---|
| `vm-app` | Java 17 + Tomcat 9 | 192.168.18.100 |
| `vm-db` | MySQL database | 192.168.18.101 |


Change the IP addresses if your network is different.

---

## 1. vm-db (database)

### 1.1 Install MySQL

```bash
# Update the package list and install the MySQL server
sudo apt update && sudo apt install -y mysql-server
```

### 1.2 Allow connections from other VMs

```bash
# By default MySQL listens only on 127.0.0.1.
# Change it to 0.0.0.0 so vm-app can connect.
sudo sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Restart MySQL to apply the change
sudo systemctl restart mysql
```

### 1.3 Create the database and the user

```bash
# Create the database, create the user "travel",
# and give this user full access to the database.
# '192.168.18.%' means: any host in the 192.168.18.x network.
sudo mysql -e "CREATE DATABASE IF NOT EXISTS travelagency CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'travel'@'192.168.18.%' IDENTIFIED BY 'travel123';
GRANT ALL ON travelagency.* TO 'travel'@'192.168.18.%';"
```

### 1.4 Check

```bash
# MySQL must listen on 0.0.0.0:3306
sudo ss -tlnp | grep 3306

# The user "travel" must be in the list
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='travel';"
```

---

## 2. vm-app (application)

### 2.1 Install Java, Maven, Tomcat and Git

```bash
# Java 17 and Maven build the project. Tomcat 9 runs it.
# Use Tomcat 9, not Tomcat 10: the project does not work on Tomcat 10.
sudo apt update && sudo apt install -y openjdk-17-jdk maven tomcat9 git
```

### 2.2 Check the connection to the database (optional)

```bash
# Install the MySQL client and try to connect to vm-db.
# If you see the "travelagency" database, the network and the user are OK.
sudo apt install -y mysql-client
mysql -h 192.168.18.101 -u travel -ptravel123 -e "SHOW DATABASES;"
```

### 2.3 Build the project

```bash
# Download the source code
git clone https://github.com/nazariybu/travelagency
cd travelagency

# Build the project. The result is target/TravelAgency.war
mvn clean package
```

### 2.4 Tell Tomcat to use Java 17

```bash
# Make a backup of the config file first
sudo cp /etc/default/tomcat9 /etc/default/tomcat9.bak

# Add JAVA_HOME to the Tomcat config
echo 'JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/default/tomcat9
```

### 2.5 Set the database connection

The application reads the database address, user and password from three
environment variables. We add them to the Tomcat service.

```bash
# Create a folder for extra service settings
sudo mkdir -p /etc/systemd/system/tomcat9.service.d

# Create the settings file with the three variables
sudo tee /etc/systemd/system/tomcat9.service.d/travelagency.conf > /dev/null <<'EOF'
[Service]
Environment=DB_TRAVELAGENCY_URL=jdbc:mysql://192.168.18.101:3306/travelagency
Environment=DB_TRAVELAGENCY_USER=travel
Environment=DB_TRAVELAGENCY_PASSWORD=travel123
EOF

# Tell systemd to read the new file
sudo systemctl daemon-reload
```

### 2.6 Deploy the application

```bash
# Stop Tomcat
sudo systemctl stop tomcat9

# Remove the default Tomcat start page
sudo rm -rf /var/lib/tomcat9/webapps/ROOT

# Copy our application as ROOT.war.
# The name ROOT is important: the site must open at "/", not at "/TravelAgency".
sudo cp target/TravelAgency.war /var/lib/tomcat9/webapps/ROOT.war

# Start Tomcat. It now has Java 17 and the database settings.
sudo systemctl start tomcat9
```

### 2.7 Check

```bash
# Tomcat must be "active (running)"
systemctl status tomcat9 --no-pager

# Watch the log. Press Ctrl+C to exit.
journalctl -u tomcat9 -f

# The login page must answer (HTTP 200)
curl -I http://localhost:8080/form-login
```

Open in a browser: `http://192.168.18.102:8080/`

---
