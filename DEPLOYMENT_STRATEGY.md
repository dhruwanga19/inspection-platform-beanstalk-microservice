# 🚀 Deployment Strategy Document

## 3-Tier Inspection Platform - AWS Elastic Beanstalk

This document outlines the deployment strategies, procedures, and best practices for deploying and maintaining the Building Inspection Platform.

---

## 📋 Table of Contents

- [Deployment Overview](#-deployment-overview)
- [Deployment Strategies](#-deployment-strategies)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Manual Deployment](#-manual-deployment)
- [Environment Configuration](#-environment-configuration)
- [Rollback Procedures](#-rollback-procedures)
- [Database Migrations](#-database-migrations)
- [Service Dependencies](#-service-dependencies)
- [Health Checks](#-health-checks)
- [Monitoring Deployments](#-monitoring-deployments)
- [Troubleshooting](#-troubleshooting)
- [Deployment Checklist](#-deployment-checklist)

---

## 🎯 Deployment Overview

### Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           DEPLOYMENT PIPELINE                                        │
└─────────────────────────────────────────────────────────────────────────────────────┘

   Developer Push                GitHub Actions                    AWS
   ═════════════                 ══════════════                    ═══

   ┌─────────────┐
   │   Local     │
   │   Code      │
   │   Changes   │
   └──────┬──────┘
          │
          │ git push
          ▼
   ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
   │   GitHub    │─────────▶│    Test     │─────────▶│   Build     │
   │   main      │  trigger │    Job      │  success │    Job      │
   │   branch    │          │             │          │             │
   └─────────────┘          └─────────────┘          └──────┬──────┘
                                                            │
                                                            │ artifacts
                                                            ▼
                                                     ┌─────────────┐
                                                     │   Deploy    │
                                                     │    Job      │
                                                     └──────┬──────┘
                                                            │
                            ┌───────────────────────────────┼───────────────────────────┐
                            │                               │                           │
                            ▼                               ▼                           ▼
                     ┌─────────────┐                 ┌─────────────┐             ┌─────────────┐
                     │    S3       │                 │     EB      │             │     EB      │
                     │  Artifacts  │────────────────▶│  App        │────────────▶│Environment  │
                     │             │  create version │  Versions   │   update    │  (Deploy)   │
                     └─────────────┘                 └─────────────┘             └─────────────┘
```

### Environments

| Environment     | Purpose                   | Deployment Trigger         |
| --------------- | ------------------------- | -------------------------- |
| **Development** | Feature testing           | Push to `develop`          |
| **Staging**     | Pre-production validation | Push to `staging`          |
| **Production**  | Live system               | Push to `main` (or manual) |

---

## 📊 Deployment Strategies

### Available Strategies in Elastic Beanstalk

| Strategy                          | Description                            | Downtime | Rollback | Use Case                 |
| --------------------------------- | -------------------------------------- | -------- | -------- | ------------------------ |
| **All at Once**                   | Deploy to all instances simultaneously | Yes      | Manual   | Development              |
| **Rolling**                       | Deploy in batches                      | Minimal  | Slower   | Staging                  |
| **Rolling with Additional Batch** | Add instances, then roll               | No       | Moderate | Pre-production           |
| **Immutable**                     | New instances, then swap               | No       | Fast     | **Production (Default)** |
| **Traffic Splitting**             | Gradual traffic shift                  | No       | Fast     | Canary releases          |

### Selected Strategy: Immutable Deployment

We use **Immutable Deployment** for production deployments due to its zero-downtime and fast rollback capabilities.

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                        IMMUTABLE DEPLOYMENT PROCESS                                  │
└─────────────────────────────────────────────────────────────────────────────────────┘

     STEP 1: Initial State                    STEP 2: Launch New Instances
     ════════════════════                     ═══════════════════════════

     ┌─────────────────┐                      ┌─────────────────┐
     │       ALB       │                      │       ALB       │
     └────────┬────────┘                      └───────┬─┬───────┘
              │                                       │ │
              ▼                                       │ │
     ┌─────────────────┐                      ┌───────▼─┴───────┐
     │   Instance A    │                      │   Instance A    │──── Old Version (v1)
     │   (v1 - Live)   │                      │   (v1 - Live)   │
     └─────────────────┘                      └─────────────────┘
     ┌─────────────────┐                      ┌─────────────────┐
     │   Instance B    │                      │   Instance B    │──── Old Version (v1)
     │   (v1 - Live)   │                      │   (v1 - Live)   │
     └─────────────────┘                      └─────────────────┘
                                              ┌─────────────────┐
                                              │   Instance C    │──── New Version (v2)
                                              │   (v2 - New)    │     (Not in ALB yet)
                                              └─────────────────┘
                                              ┌─────────────────┐
                                              │   Instance D    │──── New Version (v2)
                                              │   (v2 - New)    │     (Not in ALB yet)
                                              └─────────────────┘


     STEP 3: Health Checks Pass               STEP 4: Swap & Terminate
     ══════════════════════════               ════════════════════════

     ┌─────────────────┐                      ┌─────────────────┐
     │       ALB       │                      │       ALB       │
     └───────┬─┬───────┘                      └────────┬────────┘
             │ │                                       │
     ┌───────▼─┴───────────────┐                      ▼
     │   Instance A (v1)       │  ┐           ┌─────────────────┐
     │   Instance B (v1)       │  ├─ Still    │   Instance C    │──── New Version (v2)
     └─────────────────────────┘  │  serving  │   (v2 - Live)   │     (Now in ALB)
                                  │           └─────────────────┘
     ┌─────────────────────────┐  │           ┌─────────────────┐
     │   Instance C (v2) ✓     │  │           │   Instance D    │──── New Version (v2)
     │   Instance D (v2) ✓     │  ┘           │   (v2 - Live)   │     (Now in ALB)
     └─────────────────────────┘              └─────────────────┘
            ↓
       Health checks pass                      Instance A, B terminated
       Ready to swap                           Deployment complete!
```

### Configuration in Terraform

```hcl
# Deployment Policy Configuration
setting {
  namespace = "aws:elasticbeanstalk:command"
  name      = "DeploymentPolicy"
  value     = "Immutable"
}

setting {
  namespace = "aws:elasticbeanstalk:command"
  name      = "Timeout"
  value     = "600"  # 10 minutes
}
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml

name: Deploy to AWS Elastic Beanstalk

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci && npm run build
        working-directory: services/frontend
      # ... more tests

  build:
    name: Build Artifacts
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      # Build and package each service
      # Upload to S3

  deploy:
    name: Deploy to Elastic Beanstalk
    needs: build
    runs-on: ubuntu-latest
    steps:
      # Deploy each service with Immutable policy
```

### Pipeline Stages Detail

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              PIPELINE STAGES                                         │
└─────────────────────────────────────────────────────────────────────────────────────┘

 ╔════════════════════════════════════════════════════════════════════════════════════╗
 ║                              STAGE 1: TEST                                         ║
 ║════════════════════════════════════════════════════════════════════════════════════║
 ║                                                                                     ║
 ║   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐           ║
 ║   │ Frontend Tests    │   │ Inspection API    │   │ Report Service    │           ║
 ║   │ ─────────────────│   │ Tests             │   │ Tests             │           ║
 ║   │ • npm ci         │   │ ─────────────────│   │ ─────────────────│           ║
 ║   │ • npm run build  │   │ • npm ci         │   │ • npm ci         │           ║
 ║   │ • npm test       │   │ • npm test       │   │ • npm test       │           ║
 ║   └───────────────────┘   └───────────────────┘   └───────────────────┘           ║
 ║                                                                                     ║
 ║   Trigger: All pushes and PRs                                                      ║
 ║   Duration: ~2-3 minutes                                                            ║
 ║                                                                                     ║
 ╚════════════════════════════════════════════════════════════════════════════════════╝
                                        │
                                        │ success
                                        ▼
 ╔════════════════════════════════════════════════════════════════════════════════════╗
 ║                              STAGE 2: BUILD                                        ║
 ║════════════════════════════════════════════════════════════════════════════════════║
 ║                                                                                     ║
 ║   Trigger: Only on push to main branch                                             ║
 ║                                                                                     ║
 ║   ┌─────────────────────────────────────────────────────────────────────────┐      ║
 ║   │                    VERSION GENERATION                                   │      ║
 ║   │   frontend-20260120143052-a1b2c3d                                       │      ║
 ║   │   inspection-api-20260120143052-a1b2c3d                                 │      ║
 ║   │   report-service-20260120143052-a1b2c3d                                 │      ║
 ║   └─────────────────────────────────────────────────────────────────────────┘      ║
 ║                                                                                     ║
 ║   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐           ║
 ║   │ Frontend Build    │   │ Inspection API    │   │ Report Service    │           ║
 ║   │ ─────────────────│   │ Build             │   │ Build             │           ║
 ║   │ • npm ci         │   │ ─────────────────│   │ ─────────────────│           ║
 ║   │ • npm run build  │   │ • npm ci --prod  │   │ • npm ci --prod  │           ║
 ║   │ • Create ZIP     │   │ • Create ZIP     │   │ • Create ZIP     │           ║
 ║   │   - dist/        │   │   - src/         │   │   - src/         │           ║
 ║   │   - server.js    │   │   - node_modules │   │   - node_modules │           ║
 ║   │   - Procfile     │   │   - Procfile     │   │   - Procfile     │           ║
 ║   │   - .ebextensions│   │   - .ebextensions│   │   - .ebextensions│           ║
 ║   └───────────────────┘   └───────────────────┘   └───────────────────┘           ║
 ║                                                                                     ║
 ║   Duration: ~3-5 minutes                                                            ║
 ║                                                                                     ║
 ╚════════════════════════════════════════════════════════════════════════════════════╝
                                        │
                                        │ artifacts uploaded
                                        ▼
 ╔════════════════════════════════════════════════════════════════════════════════════╗
 ║                              STAGE 3: DEPLOY                                       ║
 ║════════════════════════════════════════════════════════════════════════════════════║
 ║                                                                                     ║
 ║   ┌─────────────────────────────────────────────────────────────────────────┐      ║
 ║   │  STEP 1: Upload to S3                                                   │      ║
 ║   │  aws s3 cp frontend-*.zip s3://bucket/frontend/                         │      ║
 ║   │  aws s3 cp inspection-api-*.zip s3://bucket/inspection-api/             │      ║
 ║   │  aws s3 cp report-service-*.zip s3://bucket/report-service/             │      ║
 ║   └─────────────────────────────────────────────────────────────────────────┘      ║
 ║                                                                                     ║
 ║   ┌─────────────────────────────────────────────────────────────────────────┐      ║
 ║   │  STEP 2: Create Application Versions                                    │      ║
 ║   │  aws elasticbeanstalk create-application-version                        │      ║
 ║   │    --application-name inspection-platform                               │      ║
 ║   │    --version-label frontend-20260120143052-a1b2c3d                      │      ║
 ║   │    --source-bundle S3Bucket=bucket,S3Key=frontend/frontend-*.zip        │      ║
 ║   └─────────────────────────────────────────────────────────────────────────┘      ║
 ║                                                                                     ║
 ║   ┌─────────────────────────────────────────────────────────────────────────┐      ║
 ║   │  STEP 3: Deploy with Immutable Policy                                   │      ║
 ║   │  aws elasticbeanstalk update-environment                                │      ║
 ║   │    --environment-name inspection-frontend-dev                           │      ║
 ║   │    --version-label frontend-20260120143052-a1b2c3d                      │      ║
 ║   │    --option-settings DeploymentPolicy=Immutable                         │      ║
 ║   └─────────────────────────────────────────────────────────────────────────┘      ║
 ║                                                                                     ║
 ║   Duration: ~10-15 minutes (due to immutable deployment)                           ║
 ║                                                                                     ║
 ╚════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 🔧 Manual Deployment

### Prerequisites

```bash
# Install AWS CLI
brew install awscli  # macOS
aws --version

# Configure AWS credentials
aws configure

# Install EB CLI (optional but recommended)
pip install awsebcli
eb --version
```

### Step-by-Step Manual Deployment

#### 1. Build the Frontend

```bash
cd services/frontend

# Install dependencies
npm ci

# Build the React application
npm run build

# Verify the build
ls -la dist/
```

#### 2. Create Deployment Package

```bash
# Frontend package
cd services/frontend
zip -r ../../frontend-manual.zip \
  dist/ \
  server.js \
  package.json \
  Procfile \
  .ebextensions/ \
  -x "node_modules/*" "src/*" "*.config.js"

# Inspection API package
cd ../inspection-api
npm ci --production
zip -r ../../inspection-api-manual.zip \
  src/ \
  node_modules/ \
  package.json \
  Procfile \
  .ebextensions/ \
  .platform/

# Report Service package
cd ../report-service
npm ci --production
zip -r ../../report-service-manual.zip \
  src/ \
  node_modules/ \
  package.json \
  Procfile \
  .ebextensions/ \
  .platform/
```

#### 3. Upload to S3

```bash
# Upload packages
aws s3 cp frontend-manual.zip s3://your-deployment-bucket/frontend/
aws s3 cp inspection-api-manual.zip s3://your-deployment-bucket/inspection-api/
aws s3 cp report-service-manual.zip s3://your-deployment-bucket/report-service/
```

#### 4. Create Application Versions

```bash
# Create version for Frontend
aws elasticbeanstalk create-application-version \
  --application-name inspection-platform \
  --version-label frontend-manual-$(date +%Y%m%d%H%M%S) \
  --source-bundle S3Bucket=your-deployment-bucket,S3Key=frontend/frontend-manual.zip

# Create version for Inspection API
aws elasticbeanstalk create-application-version \
  --application-name inspection-platform \
  --version-label inspection-api-manual-$(date +%Y%m%d%H%M%S) \
  --source-bundle S3Bucket=your-deployment-bucket,S3Key=inspection-api/inspection-api-manual.zip

# Create version for Report Service
aws elasticbeanstalk create-application-version \
  --application-name inspection-platform \
  --version-label report-service-manual-$(date +%Y%m%d%H%M%S) \
  --source-bundle S3Bucket=your-deployment-bucket,S3Key=report-service/report-service-manual.zip
```

#### 5. Deploy to Environments

```bash
# Deploy Frontend
aws elasticbeanstalk update-environment \
  --environment-name inspection-frontend-dev \
  --version-label frontend-manual-TIMESTAMP

# Deploy Inspection API
aws elasticbeanstalk update-environment \
  --environment-name inspection-api-dev \
  --version-label inspection-api-manual-TIMESTAMP

# Deploy Report Service
aws elasticbeanstalk update-environment \
  --environment-name report-service-dev \
  --version-label report-service-manual-TIMESTAMP
```

#### 6. Monitor Deployment

```bash
# Check environment status
aws elasticbeanstalk describe-environments \
  --application-name inspection-platform \
  --query 'Environments[*].[EnvironmentName,Status,Health]' \
  --output table

# Watch events
aws elasticbeanstalk describe-events \
  --environment-name inspection-frontend-dev \
  --max-items 10
```

---

## ⚙️ Environment Configuration

### Environment Variables by Service

#### Frontend

```bash
aws elasticbeanstalk update-environment \
  --environment-name inspection-frontend-dev \
  --option-settings \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=PORT,Value=8080 \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=NODE_ENV,Value=production \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=INSPECTION_API_URL,Value=http://internal-api-alb:3001 \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=REPORT_API_URL,Value=http://internal-report-alb:3002
```

#### Inspection API

```bash
aws elasticbeanstalk update-environment \
  --environment-name inspection-api-dev \
  --option-settings \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=PORT,Value=3001 \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_HOST,Value=your-rds-endpoint.rds.amazonaws.com \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_PORT,Value=3306 \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_USER,Value=admin \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_PASSWORD,Value=your-password \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_NAME,Value=inspection_platform \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=IMAGE_BUCKET_NAME,Value=inspection-images-bucket
```

#### Report Service

```bash
aws elasticbeanstalk update-environment \
  --environment-name report-service-dev \
  --option-settings \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=PORT,Value=3002 \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_HOST,Value=your-rds-primary.rds.amazonaws.com \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_READ_HOST,Value=your-rds-replica.rds.amazonaws.com \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_USER,Value=admin \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_PASSWORD,Value=your-password \
    Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_NAME,Value=inspection_platform
```

---

## ⏪ Rollback Procedures

### Automatic Rollback (Immutable Deployment)

With Immutable deployments, rollback is automatic if the new instances fail health checks:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                          AUTOMATIC ROLLBACK FLOW                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

   Deploy v2 Started           Health Check Failed          Auto Rollback
   ════════════════            ═══════════════════          ═════════════

   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
   │  Old (v1) ✓    │         │  Old (v1) ✓    │         │  Old (v1) ✓    │
   │  Still serving │         │  Still serving │         │  Still serving │
   └─────────────────┘         └─────────────────┘         └─────────────────┘

   ┌─────────────────┐         ┌─────────────────┐
   │  New (v2)      │   ──▶   │  New (v2) ✗    │   ──▶    New instances
   │  Starting...   │         │  Health failed │         terminated
   └─────────────────┘         └─────────────────┘

                                     │
                                     ▼
                               No manual action
                               required!
```

### Manual Rollback

If you need to manually rollback to a previous version:

```bash
# List available application versions
aws elasticbeanstalk describe-application-versions \
  --application-name inspection-platform \
  --query 'ApplicationVersions[*].[VersionLabel,DateCreated]' \
  --output table

# Rollback to previous version
aws elasticbeanstalk update-environment \
  --environment-name inspection-frontend-dev \
  --version-label frontend-20260119120000-previous

# Monitor rollback
aws elasticbeanstalk describe-events \
  --environment-name inspection-frontend-dev \
  --max-items 20
```

### Emergency Rollback Script

```bash
#!/bin/bash
# emergency-rollback.sh

ENVIRONMENT=$1
PREVIOUS_VERSION=$2

if [ -z "$ENVIRONMENT" ] || [ -z "$PREVIOUS_VERSION" ]; then
  echo "Usage: ./emergency-rollback.sh <environment-name> <version-label>"
  exit 1
fi

echo "Emergency rollback initiated for $ENVIRONMENT to $PREVIOUS_VERSION"

aws elasticbeanstalk update-environment \
  --environment-name "$ENVIRONMENT" \
  --version-label "$PREVIOUS_VERSION" \
  --option-settings \
    Namespace=aws:elasticbeanstalk:command,OptionName=DeploymentPolicy,Value=AllAtOnce

echo "Monitoring deployment..."
aws elasticbeanstalk wait environment-updated --environment-name "$ENVIRONMENT"

echo "Rollback complete!"
aws elasticbeanstalk describe-environments \
  --environment-names "$ENVIRONMENT" \
  --query 'Environments[0].[Status,Health,VersionLabel]' \
  --output table
```

---

## 🔗 Service Dependencies

### Deployment Order

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         RECOMMENDED DEPLOYMENT ORDER                                 │
└─────────────────────────────────────────────────────────────────────────────────────┘

   PHASE 1: Infrastructure & Database
   ═══════════════════════════════════

   ┌─────────────────┐
   │   Terraform     │──▶ VPC, RDS, S3, IAM, ALB, EB Apps
   │   (if changed)  │
   └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │   Database      │──▶ Run any pending migrations
   │   Migrations    │
   └─────────────────┘

   PHASE 2: Backend Services (Parallel)
   ════════════════════════════════════

   ┌─────────────────┐     ┌─────────────────┐
   │  Inspection     │     │    Report       │
   │     API         │     │   Service       │
   │                 │     │                 │
   │  Port: 3001     │     │  Port: 3002     │
   └─────────────────┘     └─────────────────┘
            │                      │
            └──────────┬───────────┘
                       │
                       ▼
            Wait for health: OK

   PHASE 3: Frontend (Depends on APIs)
   ════════════════════════════════════

   ┌─────────────────┐
   │    Frontend     │──▶ Requires API URLs in environment
   │                 │
   │  Port: 8080     │
   └─────────────────┘
            │
            ▼
      Deployment Complete!
```

### Health Check Dependencies

```yaml
# Verify all services are healthy before declaring success
health_checks:
  - service: inspection-api
    endpoint: /health
    expected: 200

  - service: report-service
    endpoint: /health
    expected: 200

  - service: frontend
    endpoint: /health
    expected: 200
    depends_on:
      - inspection-api
      - report-service
```

---

## ✅ Health Checks

### Health Check Configuration

| Service        | Endpoint  | Port | Interval | Healthy | Unhealthy |
| -------------- | --------- | ---- | -------- | ------- | --------- |
| Frontend       | `/health` | 8080 | 30s      | 2       | 2         |
| Inspection API | `/health` | 3001 | 30s      | 2       | 2         |
| Report Service | `/health` | 3002 | 30s      | 2       | 2         |

### Health Endpoint Implementation

```javascript
// All services implement this pattern
app.get("/health", async (req, res) => {
  try {
    // Verify database connection
    await pool.query("SELECT 1");

    res.json({
      status: "healthy",
      service: "service-name",
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: "unhealthy",
      error: error.message,
    });
  }
});
```

---

## 📊 Monitoring Deployments

### CloudWatch Metrics to Watch

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                          KEY METRICS DURING DEPLOYMENT                               │
└─────────────────────────────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────────┐
   │  INSTANCE METRICS                                                │
   ├──────────────────────────────────────────────────────────────────┤
   │  • CPUUtilization       - Should stabilize after deployment     │
   │  • StatusCheckFailed    - Should remain 0                       │
   │  • InstanceHealth       - Should show "Ok"                      │
   └──────────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────────┐
   │  APPLICATION METRICS                                             │
   ├──────────────────────────────────────────────────────────────────┤
   │  • RequestCount         - Compare before/after deployment       │
   │  • Latency (p99, p90)   - Should not increase significantly     │
   │  • HTTPCode_Target_5XX  - Should remain 0 or minimal            │
   │  • HealthyHostCount     - Should match expected instance count  │
   └──────────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────────┐
   │  DATABASE METRICS                                                │
   ├──────────────────────────────────────────────────────────────────┤
   │  • DatabaseConnections  - Should remain within limits           │
   │  • CPUUtilization       - Monitor for query issues              │
   │  • ReplicaLag           - Should be minimal for read replica    │
   └──────────────────────────────────────────────────────────────────┘
```

### Monitoring Commands

```bash
# Check environment health
aws elasticbeanstalk describe-environment-health \
  --environment-name inspection-api-dev \
  --attribute-names All

# View recent events
aws elasticbeanstalk describe-events \
  --environment-name inspection-api-dev \
  --start-time $(date -v-1H +%Y-%m-%dT%H:%M:%SZ)

# Check instance health
aws elasticbeanstalk describe-instances-health \
  --environment-name inspection-api-dev
```

---

## 🔧 Troubleshooting

### Common Deployment Issues

#### 1. Environment Stuck in "Updating"

```bash
# Check events for errors
aws elasticbeanstalk describe-events \
  --environment-name inspection-api-dev \
  --severity ERROR

# Possible causes:
# - Health check failing
# - Instance launch failures
# - Security group issues
```

#### 2. Health Check Failures

```bash
# SSH into instance (if enabled)
eb ssh inspection-api-dev

# Check application logs
tail -f /var/log/web.stdout.log

# Check if application is running
curl localhost:3001/health
```

#### 3. Database Connection Issues

```bash
# Verify security group allows connection
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[*].IpPermissions'

# Test connection from instance
mysql -h rds-endpoint -u admin -p
```

#### 4. Environment Variables Not Set

```bash
# List current environment variables
aws elasticbeanstalk describe-configuration-settings \
  --application-name inspection-platform \
  --environment-name inspection-api-dev \
  --query 'ConfigurationSettings[0].OptionSettings[?Namespace==`aws:elasticbeanstalk:application:environment`]'
```

### Log Locations

| Log Type           | Location                    |
| ------------------ | --------------------------- |
| Application stdout | `/var/log/web.stdout.log`   |
| Application stderr | `/var/log/web.stderr.log`   |
| Nginx access       | `/var/log/nginx/access.log` |
| Nginx error        | `/var/log/nginx/error.log`  |
| EB deployment      | `/var/log/eb-engine.log`    |

---

## 📚 Additional Resources

- [AWS Elastic Beanstalk Deployment Policies](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html)
- [GitHub Actions AWS Deploy](https://github.com/aws-actions/configure-aws-credentials)
- [Blue/Green Deployments on AWS](https://docs.aws.amazon.com/whitepapers/latest/overview-deployment-options/bluegreen-deployments.html)

---

**Document Version**: 1.0  
**Last Updated**: January 2026  
**Author**: Dhruwang Akbari
