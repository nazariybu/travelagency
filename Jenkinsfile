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

        stage('SonarQube Analysis') {
            agent {
                docker {
                    image 'maven:3.9-eclipse-temurin-17'
                    args  '-v /home/jenkins/.m2:/home/jenkins/.m2'
                    reuseNode true
                }
            }
            steps {
                // 'sonarqube' = server name in Manage Jenkins -> System -> SonarQube servers.
                // withSonarQubeEnv passes the server URL and token to the Maven scanner.
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        mvn -B -Dmaven.repo.local=/home/jenkins/.m2/repository \
                            org.sonarsource.scanner.maven:sonar-maven-plugin:5.1.0.4751:sonar \
                            -Dsonar.projectKey=travelagency \
                            -Dsonar.projectName=TravelAgency
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Waits for SonarQube to call the Jenkins webhook with the result.
                // abortPipeline: true stops the build when the gate is red.
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Snyk Dependency Scan') {
            agent {
                docker {
                    image 'snyk/snyk:maven-3-jdk-17'
                    args  '-v /home/jenkins/.m2:/home/jenkins/.m2 --entrypoint='
                    reuseNode true
                }
            }
            environment {
                SNYK_TOKEN = credentials('snyk-token')
                HOME       = "${env.WORKSPACE}"   // snyk CLI needs a writable home for its config
            }
            steps {
                script {
                    // Exit codes: 0 = no issues, 1 = vulnerabilities found, 2/3 = Snyk error.
                    // Vulnerabilities mark the build UNSTABLE (yellow), an error fails it.
                    def rc = sh(returnStatus: true, script: '''
                        snyk test --file=pom.xml --severity-threshold=high \
                            -- -Dmaven.repo.local=/home/jenkins/.m2/repository > snyk-report.txt
                    ''')
                    sh 'cat snyk-report.txt'
                    archiveArtifacts artifacts: 'snyk-report.txt', allowEmptyArchive: true
                    if (rc == 1) {
                        unstable('Snyk found HIGH/CRITICAL vulnerabilities in Maven dependencies')
                    } else if (rc != 0) {
                        error("Snyk failed with exit code ${rc}")
                    }
                    // Snapshot of dependencies for the Snyk web UI, only from the main branch
                    if (env.BRANCH_NAME == 'load-balancing-redis') {
                        sh 'snyk monitor --file=pom.xml --project-name=travelagency -- -Dmaven.repo.local=/home/jenkins/.m2/repository'
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                archiveArtifacts artifacts: 'target/TravelAgency.war', fingerprint: true
            }
        }
        
        stage('Publish WAR to GitHub Packages') {
            when { branch 'load-balancing-redis' }
            agent {
                docker {
                    image 'maven:3.9-eclipse-temurin-17'
                    args  '-v /home/jenkins/.m2:/home/jenkins/.m2'
                    reuseNode true
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-packages',
                                                  usernameVariable: 'GH_PKG_USER',
                                                  passwordVariable: 'GH_PKG_TOKEN')]) {
                    // GitHub Packages rejects a second upload of the same release version,
                    // so every build gets its own version: 1.0.<build number>
                    sh '''
                        MVN="mvn -B -s ci/maven-settings.xml -Dmaven.repo.local=/home/jenkins/.m2/repository"
                        $MVN versions:set -DnewVersion=1.0.$BUILD_NUMBER -DgenerateBackupPoms=false
                        $MVN deploy -DskipTests
                    '''
                }
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
