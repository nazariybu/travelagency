pipeline {
    agent { label 'docker' }
    options { timestamps(); disableConcurrentBuilds() }
    environment {
        IMAGE = 'nazariybu/travelagency'   // change to your Docker Hub login
        TAG   = "${env.BUILD_NUMBER}"
    }

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
        
        stage('Docker Build') {
            steps {
                sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
            }
        }

        stage('Trivy Scan') {
            steps {
                // Report only: --exit-code 0 never fails the build.
                // To block the build on critical CVEs use: --severity CRITICAL --exit-code 1
                sh '''
                    mkdir -p $HOME/.cache/trivy
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v $HOME/.cache/trivy:/root/.cache/trivy \
                        aquasec/trivy:0.57.1 image \
                        --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
                        --no-progress --exit-code 0 \
                        $IMAGE:$TAG | tee trivy-report.txt
                '''
                archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true
            }
        }

        stage('Push to Docker Hub') {
            when { branch 'load-balancing-redis' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                        docker push $IMAGE:$TAG
                        docker push $IMAGE:latest
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy') {
            when { branch 'load-balancing-redis' }       // deploy only from this branch           
            environment {
                DB_PASSWORD    = credentials('db-password')
                REDIS_PASSWORD = credentials('redis-password')
            }
            steps {
                dir('ansible') {
                    sh 'ansible-playbook app.yml -e war_file=$WORKSPACE/target/TravelAgency.war'
                }
            }
        }
    }
}
