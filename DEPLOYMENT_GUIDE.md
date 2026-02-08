# Deployment Guide

This guide provides detailed instructions for deploying and managing the microservices infrastructure.

## 🎯 Overview

This project demonstrates advanced DevOps practices with:
- **Infrastructure as Code** using Terraform
- **Database Flexibility** with MySQL/MongoDB switching
- **Automated CI/CD** with GitHub Actions
- **Container Orchestration** with Docker Compose
- **Service Discovery** and API Gateway with Kong
- **Message Queuing** with RabbitMQ

## 🔧 Implementation Approach

### Infrastructure Design

The architecture follows microservices best practices:

1. **Service Isolation**: Each service runs on dedicated VMs
2. **Database Abstraction**: Application code supports both MySQL and MongoDB
3. **Message-Driven Architecture**: RabbitMQ enables async communication
4. **API Gateway Pattern**: Kong provides centralized API management
5. **Configuration Management**: Environment-based configuration switching

### Automation Strategy

I've implemented a multi-layered automation approach:

#### 1. Infrastructure Automation (Terraform)
- **Declarative Configuration**: Infrastructure defined as code
- **State Management**: Terraform tracks resource state
- **Parameterized Deployment**: Variables enable environment customization
- **Cloud-Init Integration**: Automated VM configuration

#### 2. Application Deployment (CI/CD)
- **GitHub Actions**: Automated build, test, and deploy pipelines
- **Container Registry**: Docker Hub for image distribution
- **Rolling Deployment**: Zero-downtime application updates
- **Health Verification**: Automated post-deployment checks

#### 3. Database Management (Scripts + Workflow)
- **Runtime Switching**: Change databases without infrastructure rebuild
- **Graceful Transition**: Services restart with new database configuration
- **Consistency Checks**: Verify database connectivity after switches

## 📋 Detailed Deployment Steps

### Phase 1: Prerequisites Setup

1. **Azure Setup**:
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login to Azure
   az login
   
   # Verify subscription
   az account show
   ```

2. **Terraform Installation**:
   ```bash
   # Download and install Terraform
   wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
   unzip terraform_1.5.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **SSH Key Generation**:
   ```bash
   # Generate SSH key if not exists
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

### Phase 2: Infrastructure Deployment

1. **Clone Repository**:
   ```bash
   git clone <repository-url>
   cd option4-all-vms
   chmod +x scripts/*.sh
   ```

2. **Configure Variables** (Optional):
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferred settings
   ```

3. **Deploy Infrastructure**:
   ```bash
   # Deploy with MongoDB (default)
   ./scripts/deploy-infrastructure.sh
   
   # Or with custom configuration
   ./scripts/deploy-infrastructure.sh --db-type mysql --environment staging
   ```

4. **Verify Deployment**:
   ```bash
   # Check deployment info
   cat deployment-info.json
   
   # Test SSH connectivity
   ssh azureuser@<JOKE_VM_IP> "echo 'Connected successfully'"
   ```

### Phase 3: Application Deployment

1. **Deploy Applications**:
   ```bash
   # Build and deploy all services
   ./scripts/deploy-apps.sh
   ```

2. **Monitor Deployment**:
   ```bash
   # Wait for services to initialize
   sleep 180
   
   # Run health checks
   ./scripts/health-check.sh --verbose
   ```

### Phase 4: Database Configuration

1. **Verify Current Database**:
   ```bash
   # Check current database type
   jq -r '.database_type' deployment-info.json
   ```

2. **Switch Database** (if needed):
   ```bash
   # Switch to MySQL
   ./scripts/switch-database.sh mysql
   
   # Switch to MongoDB
   ./scripts/switch-database.sh mongo
   ```

3. **Test Database Functionality**:
   ```bash
   # Test joke API
   JOKE_VM_IP=$(jq -r '.services.joke_vm.public_ip' deployment-info.json)
   curl "http://$JOKE_VM_IP:4000/api/jokes/random"
   ```

## 🔄 CI/CD Pipeline Configuration

### GitHub Secrets Configuration

Add these secrets to your GitHub repository:

1. **Azure Service Principal**:
   ```bash
   # Create service principal
   az ad sp create-for-rbac --name "microservices-sp" --role contributor --scopes /subscriptions/<subscription-id>
   ```
   
   Add to GitHub secrets:
   - `ARM_CLIENT_ID`
   - `ARM_CLIENT_SECRET`
   - `ARM_SUBSCRIPTION_ID`
   - `ARM_TENANT_ID`

2. **Docker Hub**:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN`

3. **SSH Key**:
   - `SSH_PRIVATE_KEY` (content of ~/.ssh/id_rsa)

### Pipeline Workflows

1. **Main Deployment Pipeline** (`.github/workflows/deploy.yml`):
   - Triggered on main branch push
   - Performs Terraform plan/apply
   - Builds and deploys Docker images
   - Runs health checks

2. **Database Switch Pipeline** (`.github/workflows/switch-database.yml`):
   - Manual trigger from GitHub Actions UI
   - Switches database type without infrastructure changes
   - Verifies database connectivity

### Using the Pipelines

1. **Automated Deployment**:
   ```bash
   # Push changes to main branch
   git add .
   git commit -m "Deploy infrastructure updates"
   git push origin main
   ```

2. **Manual Database Switch**:
   - Navigate to GitHub Actions
   - Select "Switch Database Type"
   - Choose target database type
   - Run workflow

## 🗄️ Database Implementation Details

### Architecture Design

Both databases use the same application interface:

```javascript
// Database abstraction layer
const dbType = process.env.DB_TYPE || 'mongo';

if (dbType === 'mongo') {
    // MongoDB implementation
    const mongoose = require('mongoose');
    // ... MongoDB logic
} else if (dbType === 'mysql') {
    // MySQL implementation
    const mysql = require('mysql2');
    // ... MySQL logic
}
```

### Schema Management

#### MongoDB Schema:
```javascript
const jokeSchema = {
    _id: ObjectId,
    text: String,
    type: String,
    created_at: Date
};
```

#### MySQL Schema:
```sql
CREATE TABLE jokes (
    id INT PRIMARY KEY AUTO_INCREMENT,
    text TEXT NOT NULL,
    type VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Switching Process

1. **Environment Update**: Change `DB_TYPE` variable
2. **Container Restart**: Stop current database containers, start target database
3. **Service Restart**: Restart application services with new configuration
4. **Health Verification**: Confirm database connectivity

### Data Persistence

- **MongoDB**: Data persists in `mongo_vol` Docker volume
- **MySQL**: Data persists in `mysql_vol` Docker volume
- **Volume Management**: Volumes survive container restarts

## 📊 Monitoring and Operations

### Health Monitoring

The health check system provides multiple levels of verification:

1. **HTTP Health Endpoints**: Application-level health checks
2. **TCP Connectivity**: Port-level connectivity verification
3. **SSH Connectivity**: VM-level access verification
4. **Functional Tests**: End-to-end API testing

### Operational Commands

```bash
# Check all service health
./scripts/health-check.sh --verbose --functional

# Monitor specific service
ssh azureuser@<VM_IP> "sudo docker-compose -f /app/microservices/*/docker-compose.yml logs -f"

# Restart service
ssh azureuser@<VM_IP> "sudo systemctl restart <service>-service"

# View resource usage
ssh azureuser@<VM_IP> "sudo docker stats"
```

### Troubleshooting

Common issues and solutions:

1. **Cloud-init not complete**:
   ```bash
   ssh azureuser@<VM_IP> "sudo cloud-init status --wait"
   ```

2. **Service startup failure**:
   ```bash
   ssh azureuser@<VM_IP> "sudo systemctl status <service>-service"
   ssh azureuser@<VM_IP> "sudo journalctl -u <service>-service -f"
   ```

3. **Database connection issues**:
   ```bash
   ssh azureuser@<JOKE_VM_IP> "sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml ps"
   ssh azureuser@<JOKE_VM_IP> "sudo docker-compose -f /app/microservices/joke-vm/docker-compose.yml logs"
   ```

## 🏗️ Infrastructure Customization

### Scaling Considerations

To scale the infrastructure:

1. **Vertical Scaling**: Increase VM sizes in `variables.tf`
2. **Horizontal Scaling**: Add load balancers and multiple service instances
3. **Database Scaling**: Implement replica sets or clustering

### Environment Variations

Create environment-specific configurations:

```hcl
# terraform/environments/prod.tfvars
location = "East US"
environment = "prod"
vm_size = "Standard_D4s_v3"
db_type = "mysql"
```

Deploy with:
```bash
./scripts/deploy-infrastructure.sh --environment prod
```

### Security Hardening

For production deployments:

1. **Network Security**: Implement private subnets and NAT gateways
2. **Key Management**: Use Azure Key Vault for secrets
3. **SSL/TLS**: Configure HTTPS with proper certificates
4. **Access Control**: Implement role-based access control

## 🧪 Testing Strategy

### Local Testing

```bash
# Test individual components
cd joke-vm
docker-compose up --build

# Test database switching locally
docker-compose --profile mongo up -d
docker-compose --profile mysql up -d
```

### Integration Testing

```bash
# Full deployment test
./scripts/deploy-infrastructure.sh --environment dev
./scripts/deploy-apps.sh
./scripts/health-check.sh --functional
./scripts/switch-database.sh mysql
./scripts/switch-database.sh mongo
```

### Performance Testing

```bash
# Load test joke API
for i in {1..100}; do
    curl -s "http://$JOKE_VM_IP:4000/api/jokes/random" &
done
wait
```

## 📈 Performance Optimization

### Database Performance

1. **MongoDB Optimization**:
   - Create indexes for frequently queried fields
   - Use connection pooling
   - Configure replica sets for high availability

2. **MySQL Optimization**:
   - Tune buffer pool size
   - Optimize query cache
   - Implement read replicas

### Application Performance

1. **Caching**: Implement Redis for frequently accessed data
2. **Connection Pooling**: Configure database connection pools
3. **Load Balancing**: Add application load balancers

## 🔒 Security Best Practices

### Network Security

- Use private subnets for internal communication
- Implement network security groups with minimal required access
- Consider Azure Firewall for advanced network protection

### Application Security

- Implement API authentication and authorization
- Use HTTPS for all external communications
- Regular security updates for base images

### Data Security

- Encrypt data at rest and in transit
- Implement database access controls
- Regular backup and disaster recovery testing

## 📚 Additional Resources

### Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### Best Practices

- [12-Factor App Methodology](https://12factor.net/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Microservices Patterns](https://microservices.io/patterns/)

This deployment guide provides the foundation for a production-ready microservices infrastructure with database flexibility and automated operations.