pipeline {
    agent any

    environment {
        PROJECT_ID    = "ratnapal-project"
        REGION        = "us-central1"
        REGISTRY      = "${REGION}-docker.pkg.dev/${PROJECT_ID}/ratnapal-images"
        BACKEND_VM_IP = credentials('BACKEND_VM_PRIVATE_IP')
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                checkout scm
            }
        }

        stage('Set Commit Tag') {
            steps {
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                }
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
                                -f backend/python-fastapi/Dockerfile backend/python-fastapi
                        '''
                    }
                }
                stage('Build Django') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/django:${GIT_COMMIT_SHORT} \
                                -t ${REGISTRY}/django:latest \
                                -f backend/python-django/Dockerfile backend/python-django
                        '''
                    }
                }
                stage('Build Node') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/node:${GIT_COMMIT_SHORT} \
                                -t ${REGISTRY}/node:latest \
                                -f backend/nodejs/Dockerfile backend/nodejs
                        '''
                    }
                }
                stage('Build .NET') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/dotnet:${GIT_COMMIT_SHORT} \
                                -t ${REGISTRY}/dotnet:latest \
                                -f backend/dotnet-webapi/Dockerfile backend/dotnet-webapi
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

        stage('Build & Deploy Frontend') {
            steps {
                dir('frontend') {
                    sh '''
                        echo "Building React frontend..."
                        
                        # Fetch the dynamic Load Balancer IP
                        LB_IP=$(gcloud compute addresses describe ratnapal-lb-ip --global --format="value(address)" --project=${PROJECT_ID})
                        export VITE_API_BASE_URL="http://${LB_IP}"
                        
                        echo "Using API Base URL: ${VITE_API_BASE_URL}"
                        
                        npm install
                        npm run build
                        
                        # Upload to GCS Bucket (acting as S3 for GCP)
                        if [ -d "build" ]; then
                            gsutil -m rsync -R build/ gs://${PROJECT_ID}-react-frontend/
                        elif [ -d "dist" ]; then
                            gsutil -m rsync -R dist/ gs://${PROJECT_ID}-react-frontend/
                        else
                            echo "Build directory not found! Expected 'build' or 'dist'."
                            exit 1
                        fi
                    '''
                }
            }
        }

        stage('Deploy to Backend VM') {
            steps {
                sshagent(['backend-vm-ssh-key']) {
                    sh '''
                        scp -o StrictHostKeyChecking=no \
                        compose.yaml \
                        ratnapalshende2001_gmail_com@${BACKEND_VM_IP}:/home/ratnapalshende2001_gmail_com/

                        ssh -o StrictHostKeyChecking=no ratnapalshende2001_gmail_com@${BACKEND_VM_IP} << EOF
cd /home/ratnapalshende2001_gmail_com

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
EOF
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ Deployment successful! Commit: ${env.GIT_COMMIT_SHORT}"
        }
        failure {
            echo "❌ Pipeline failed. Check logs above."
        }
        always {
            script {
                try {
                    sh 'docker system prune -f'
                } catch (err) {
                    echo "Cleanup skipped"
                }
            }
        }
    }
}