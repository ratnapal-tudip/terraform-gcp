// ─────────────────────────────────────────────────────────────
// Jenkinsfile — Ratnapal CI/CD Pipeline
// Triggered by: GitHub webhook push
// Flow: Build 4 Docker images → Push to Artifact Registry → SSH deploy to backend VM
// ─────────────────────────────────────────────────────────────

pipeline {
    agent any

    environment {
        PROJECT_ID      = "ratnapal-project"
        REGION          = "us-central1"
        REGISTRY        = "${REGION}-docker.pkg.dev/${PROJECT_ID}/ratnapal-images"
        BACKEND_VM_IP   = credentials('BACKEND_VM_PRIVATE_IP')   // store in Jenkins credentials
        GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                checkout scm
            }
        }

        stage('Authenticate with GCP') {
            steps {
                sh '''
                    gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
                '''
            }
        }

        stage('Build Docker Images') {
            parallel {
                stage('Build FastAPI') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/fastapi:${GIT_COMMIT_SHORT} \
                                         -t ${REGISTRY}/fastapi:latest \
                                         -f ./fastapi/Dockerfile ./fastapi
                        '''
                    }
                }
                stage('Build Django') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/django:${GIT_COMMIT_SHORT} \
                                         -t ${REGISTRY}/django:latest \
                                         -f ./django/Dockerfile ./django
                        '''
                    }
                }
                stage('Build Node') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/node:${GIT_COMMIT_SHORT} \
                                         -t ${REGISTRY}/node:latest \
                                         -f ./node/Dockerfile ./node
                        '''
                    }
                }
                stage('Build .NET') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/dotnet:${GIT_COMMIT_SHORT} \
                                         -t ${REGISTRY}/dotnet:latest \
                                         -f ./dotnet/Dockerfile ./dotnet
                        '''
                    }
                }
            }
        }

        stage('Push to Artifact Registry') {
            parallel {
                stage('Push FastAPI') {
                    steps {
                        sh '''
                            docker push ${REGISTRY}/fastapi:${GIT_COMMIT_SHORT}
                            docker push ${REGISTRY}/fastapi:latest
                        '''
                    }
                }
                stage('Push Django') {
                    steps {
                        sh '''
                            docker push ${REGISTRY}/django:${GIT_COMMIT_SHORT}
                            docker push ${REGISTRY}/django:latest
                        '''
                    }
                }
                stage('Push Node') {
                    steps {
                        sh '''
                            docker push ${REGISTRY}/node:${GIT_COMMIT_SHORT}
                            docker push ${REGISTRY}/node:latest
                        '''
                    }
                }
                stage('Push .NET') {
                    steps {
                        sh '''
                            docker push ${REGISTRY}/dotnet:${GIT_COMMIT_SHORT}
                            docker push ${REGISTRY}/dotnet:latest
                        '''
                    }
                }
            }
        }

        stage('Deploy to Backend VM') {
            steps {
                // Inject updated image tags into docker-compose and deploy via SSH
                // Jenkins VM → Backend VM via internal VPC (private IP)
                sshagent(['backend-vm-ssh-key']) {  // add SSH key in Jenkins credentials
                    sh '''
                        # Copy docker-compose with updated registry URLs
                        scp -o StrictHostKeyChecking=no \
                            compose.yaml \
                            jenkins@${BACKEND_VM_IP}:/home/jenkins/

                        # SSH into backend VM and redeploy
                        ssh -o StrictHostKeyChecking=no jenkins@${BACKEND_VM_IP} << 'REMOTE'
                            cd /home/jenkins

                            # Auth Docker with Artifact Registry
                            gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

                            # Pull latest images
                            docker compose pull

                            # Restart containers with zero-downtime rolling
                            docker compose up -d --remove-orphans

                            # Clean up old images
                            docker image prune -f
                        REMOTE
                    '''
                }
            }
        }

    }

    post {
        success {
            echo "✅ Deployment successful! Commit: ${GIT_COMMIT_SHORT}"
        }
        failure {
            echo "❌ Pipeline failed at stage. Check logs above."
        }
        always {
            // Clean up local Docker images on Jenkins VM to save disk
            sh 'docker system prune -f || true'
        }
    }
}
