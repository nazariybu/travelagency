pipeline {
    agent { label 'docker' }
    options { timestamps(); disableConcurrentBuilds() }

    stages {
        stage('Build & Test') {
            agent {
                docker {
                    image 'maven:3.9-eclipse-temurin-17'
                    args  '-v /home/jenkins/.m2:/home/jenkins/.m2'   // Maven cache between builds
                    reuseNode true
                }
            }
            steps {
                sh 'mvn -B -Dmaven.repo.local=/home/jenkins/.m2/repository clean package'
            }
        }

        stage('Archive') {
            steps {
                archiveArtifacts artifacts: 'target/TravelAgency.war', fingerprint: true
            }
        }

        stage('Deploy') {
            when { branch 'load-balancing-redis' }       // deploy only from this branch           
            environment { DB_PASSWORD = credentials('db-password') }
            steps {
                dir('ansible') {
                    sh 'ansible-playbook app.yml -e war_file=$WORKSPACE/target/TravelAgency.war'
                }
            }
        }
    }
}
