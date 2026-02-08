# Microservices Infrastructure with Database Switching

This project demonstrates a complete microservices infrastructure deployment on Azure using Terraform, with the ability to switch between MySQL and MongoDB databases. The infrastructure includes automated CI/CD pipelines and comprehensive monitoring.

## 🏗️ Architecture Overview

The infrastructure consists of 5 VMs running different microservices:

- **Joke VM**: Hosts the joke service and ETL service with configurable database (MySQL/MongoDB)
- **Submit VM**: Handles joke submission requests
- **Moderate VM**: Content moderation service
- **RabbitMQ VM**: Message broker for inter-service communication
- **Kong VM**: API Gateway for traffic management

## 🔧 Technologies Used

- **Infrastructure**: Terraform + Azure
- **Containerization**: Docker + Docker Compose
- **Databases**: MySQL 8 + MongoDB 6
- **Message Broker**: RabbitMQ 3
- **API Gateway**: Kong
- **CI/CD**: GitHub Actions
- **Monitoring**: Built-in health checks

## 🚀 Quick Start

### Prerequisites

1. **Azure CLI** - Authenticated (`az login`)
2. **Terraform** - Version 1.0+
3. **Docker** - For local image building
4. **SSH Key Pair** - For VM access
5. **jq** - For JSON processing (optional but recommended)

### 1. Deploy Infrastructure

```bash
# Clone the repository
git clone <repository-url>
cd option4-all-vms

# Make scripts executable
chmod +x scripts/*.sh

# Deploy with MongoDB (default)
./scripts/deploy-infrastructure.sh

# Or deploy with MySQL
./scripts/deploy-infrastructure.sh --db-type mysql

# For production deployment
./scripts/deploy-infrastructure.sh --environment prod --auto-approve
```

### 2. Deploy Applications

```bash
# Deploy all applications
./scripts/deploy-apps.sh

# Force deployment without building images
./scripts/deploy-apps.sh --force --no-build
```

### 3. Switch Database Type

```bash
# Switch to MySQL
./scripts/switch-database.sh mysql

# Switch to MongoDB
./scripts/switch-database.sh mongo

# Force switch with skip testing
./scripts/switch-database.sh mysql --force --skip-test
```

### 4. Health Monitoring

```bash
# Basic health check
./scripts/health-check.sh

# Verbose health check with functional tests
./scripts/health-check.sh --verbose --functional
```

## 📁 Project Structure

```
option4-all-vms/
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Core infrastructure
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── vms.tf                   # Virtual machine configuration
│   └── cloud-init/              # VM initialization scripts
├── .github/workflows/           # CI/CD pipelines
│   ├── deploy.yml               # Main deployment pipeline
│   └── switch-database.yml      # Database switching workflow
├── scripts/                     # Automation scripts
│   ├── deploy-infrastructure.sh # Infrastructure deployment
│   ├── deploy-apps.sh           # Application deployment
│   ├── switch-database.sh       # Database switching
│   └── health-check.sh          # Health monitoring
├── joke-vm/                     # Joke and ETL services
├── submit-vm/                   # Submit service
├── moderate-vm/                 # Moderate service
├── rabbitmq-vm/                 # RabbitMQ broker
├── kong-vm/                     # Kong gateway
└── README.md                    # This file
```

## 🗄️ Database Configuration

The joke service supports both MySQL and MongoDB with seamless switching:

### Database Switching Mechanism

1. **Docker Compose Profiles**: Uses profiles to activate specific database containers
2. **Environment Variables**: `DB_TYPE` controls which database connection to use
3. **Automated Scripts**: Handle service restart and health verification
4. **Zero Downtime**: Quick switching with minimal service interruption

### Database Connection Details

#### MongoDB
- **Port**: 27017 (container), 4002 (host)
- **Database**: jokes
- **Connection**: `mongodb://mongo:27017/jokes`

#### MySQL
- **Port**: 3306 (container), 4002 (host)
- **Database**: jokes
- **User**: root
- **Connection**: `mysql://root:password@mysql:3306/jokes`

## 🔄 CI/CD Pipeline

### Automated Deployment Workflow

The GitHub Actions pipeline provides:

1. **Infrastructure Validation**: Terraform format, validate, and plan
2. **Automated Deployment**: Apply infrastructure changes
3. **Application Build**: Docker image building and pushing
4. **Service Deployment**: Copy code and restart services
5. **Health Verification**: Post-deployment health checks

### Manual Database Switching

Use the dedicated workflow to switch databases:

1. Go to Actions tab in GitHub
2. Select "Switch Database Type" workflow
3. Choose target database type (mysql/mongo)
4. Run workflow

### Required Secrets

Configure these secrets in your GitHub repository:

```
# Azure Service Principal
ARM_CLIENT_ID=<service-principal-id>
ARM_CLIENT_SECRET=<service-principal-secret>
ARM_SUBSCRIPTION_ID=<azure-subscription-id>
ARM_TENANT_ID=<azure-tenant-id>

# Docker Hub (for image registry)
DOCKERHUB_USERNAME=<dockerhub-username>
DOCKERHUB_TOKEN=<dockerhub-token>

# SSH Key for VM access
SSH_PRIVATE_KEY=<private-ssh-key>
```

## 🌐 Service Endpoints

After deployment, access services via:

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Joke API | 4000 | http://JOKE_VM_IP:4000 | Main joke service |
| ETL Service | 4001 | http://JOKE_VM_IP:4001 | Data processing |
| Submit Service | 4200 | http://SUBMIT_VM_IP:4200 | Joke submission |
| Moderate Service | 4100 | http://MODERATE_VM_IP:4100 | Content moderation |
| RabbitMQ Management | 15672 | http://RABBITMQ_VM_IP:15672 | Message broker UI |
| Kong Gateway | 8000 | http://KONG_VM_IP:8000 | API gateway |
| Kong Admin | 8001 | http://KONG_VM_IP:8001 | Gateway management |

## 🔍 Monitoring and Troubleshooting

### Health Check Endpoints

Each service provides health endpoints:
- Joke Service: `http://JOKE_VM_IP:4000/health`
- ETL Service: `http://JOKE_VM_IP:4001/health`
- Submit Service: `http://SUBMIT_VM_IP:4200/health`
- Moderate Service: `http://MODERATE_VM_IP:4100/health`

### Logs and Debugging

```bash
# SSH into a VM
ssh azureuser@<VM_IP>

# Check service status
sudo systemctl status joke-service

# View Docker containers
sudo docker ps

# View container logs
sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml logs

# Check database status
sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml exec mongo mongosh
sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml exec mysql mysql -u root -p
```

### Common Issues

1. **Services not starting**: Check cloud-init completion (`sudo cloud-init status`)
2. **Database connection failed**: Verify container status and environment variables
3. **Health checks failing**: Allow 5-10 minutes for full service initialization
4. **SSH connection refused**: Verify security group rules and VM status

## 🛡️ Security Considerations

- **SSH Keys**: Use strong SSH key pairs for VM access
- **Passwords**: Change default passwords in production
- **Network Security**: Services use private IPs for internal communication
- **Firewall Rules**: Only necessary ports are exposed publicly
- **Secrets Management**: Use Azure Key Vault for production secrets

## 📊 Cost Optimization

- **VM Sizes**: Default `Standard_B2s` balances performance and cost
- **Auto-shutdown**: Consider scheduled VM shutdown for dev environments
- **Resource Tagging**: All resources are tagged for cost tracking
- **Cleanup**: Use `terraform destroy` to remove resources when not needed

## 🔧 Advanced Configuration

### Custom Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
location = "West US 2"
environment = "staging"
vm_size = "Standard_B4ms"
db_type = "mysql"
```

### Environment-Specific Deployments

```bash
# Deploy to staging with MySQL
./scripts/deploy-infrastructure.sh --environment staging --db-type mysql

# Deploy to production with auto-approval
./scripts/deploy-infrastructure.sh --environment prod --auto-approve
```

### Database Migration

When switching databases, consider:

1. **Data Backup**: Export data before switching
2. **Schema Migration**: Ensure schema compatibility
3. **Testing**: Verify functionality after switch
4. **Rollback Plan**: Keep previous database available

## 📝 Contributing

1. Follow infrastructure as code best practices
2. Test changes in development environment first
3. Update documentation for new features
4. Follow security guidelines for secrets and credentials

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🆘 Support

For issues and questions:

1. Check the troubleshooting section above
2. Review service logs on VMs
3. Verify infrastructure status in Azure portal
4. Create an issue in the repository with detailed information

---

**Note**: This is a demonstration project. For production use, implement additional security measures, monitoring, and backup strategies.