# SchoolBase Deployment Repository

A comprehensive deployment solution for SchoolBase that handles all infrastructure setup, configuration, and deployment using a **combined image approach**.

## 🏗️ Architecture Overview

This deployment uses a **combined container architecture** where:

```
┌─────────────────────────────────────┐
│        Nginx (Host)                 │
│  SSL Termination, Reverse Proxy     │
└──────────────┬──────────────────────┘
               │
    ┌──────────┴──────────┬──────────────┐
    │                     │              │
┌───▼──────────┐  ┌───────▼──────┐  ┌───▼──────┐
│ Combined App │  │  Postgres    │  │  MinIO   │
│ Container    │  │  Container   │  │ Container│
│              │  │              │  │          │
│ • Frontend   │  │ • Database   │  │ • Object │
│ • Backend    │  │ • Persisted  │  │   Storage│
│ • Supervisor │  │   Storage    │  │ • Files  │
│   Managed    │  │              │  │          │
└──────────────┘  └──────────────┘  └──────────┘
```

### Why This Architecture?

1. **Combined Application Container** (BE + FE):
   - Single container simplifies deployment and management
   - Frontend and backend run together using supervisor
   - Easier to deploy, scale, and maintain
   - Supports both single-instance and multi-tenant deployments

2. **Separate Database Container** (Postgres):
   - Data persistence independent of application
   - Easy backups and data management
   - Can be scaled or moved independently

3. **Separate Storage Container** (MinIO):
   - File storage decoupled from application
   - Critical for file uploads (logos, images, documents)
   - Can be backed up or migrated independently

4. **Nginx on Host**:
   - SSL termination and certificate management
   - Reverse proxy routing
   - Easy domain management

## 📋 Prerequisites

- Ubuntu/Debian server (20.04+ recommended) or CentOS/RHEL
- Root or sudo access
- Domain names pointing to your server (for SSL)
- Ports 80, 443, 3000, 3008, 5432, 9000, 9001 open

## 🚀 Quick Start

### 1. Clone Deployment Repository

```bash
git clone <deployment-repo-url> schoolbase-deployment
cd schoolbase-deployment
```

### 2. Configure Deployment

**Option A: Edit `deploy.sh` for repository configuration** (recommended for one-time setup):

Edit these variables at the top of `deploy.sh`:
```bash
# Repository URLs
FRONTEND_REPO="https://github.com/schoolbaseafrica/SchoolBase-FE.git"
BACKEND_REPO="https://github.com/Donkross360/SchoolBase-BE.git"

# Branch/Tag to deploy
FRONTEND_BRANCH="main"
BACKEND_BRANCH="dev"

# Action: "clone" or "pull"
REPO_ACTION="pull"
```

**Option B: Set environment variables** (for CI/CD or automation):
```bash
export FRONTEND_REPO="https://github.com/your-org/SchoolBase-FE.git"
export FRONTEND_BRANCH="main"
export BACKEND_BRANCH="dev"
export REPO_ACTION="pull"
```

**Domain and Email Configuration** will be loaded from `.env` file (created in step 3).

### 3. Make Scripts Executable

```bash
chmod +x deploy.sh scripts/*.sh
```

### 4. Configure Environment Variables

The deployment script will create a `.env` file from `config/env.example`. You'll be prompted to edit it.

**Important variables to set in `.env`:**
- `FRONTEND_DOMAIN` - Your frontend domain (e.g., `myschool.com`)
- `BACKEND_DOMAIN` - Your backend API domain (e.g., `api.myschool.com`)
- `SSL_EMAIL` - Email for Let's Encrypt SSL certificates
- `JWT_SECRET` - Strong random string for JWT tokens
- `JWT_REFRESH_SECRET` - Different strong random string
- `DB_PASS` - PostgreSQL database password
- `MINIO_ROOT_PASSWORD` - MinIO root password
- `MINIO_SECRET_KEY` - MinIO secret key (should match MINIO_ROOT_PASSWORD)

**Note**: Domain and email configuration is now in `.env` file - you only need to configure it once!

### 5. Run Deployment

```bash
./deploy.sh
```

The script will:
- ✅ Install all system dependencies (Docker, Nginx, Certbot, etc.)
- ✅ Clone or update frontend/backend repositories
- ✅ Load configuration from `.env` file
- ✅ Configure SSL certificates (if domains are set in `.env`)
- ✅ Configure Nginx reverse proxy
- ✅ Build combined Docker image (BE + FE)
- ✅ Start all services (app, postgres, minio)

## 📁 Repository Structure

```
schoolbase-deployment/
├── deploy.sh                    # Main deployment script
├── docker-compose.yml           # Docker Compose configuration
├── Dockerfile.combined          # Combined image Dockerfile (BE + FE)
├── supervisord.conf             # Supervisor config for combined container
├── scripts/
│   ├── install-dependencies.sh  # Installs system dependencies
│   ├── setup-ssl.sh             # SSL certificate setup
│   └── setup-nginx.sh           # Nginx configuration
├── nginx/
│   └── templates/
│       ├── frontend.conf.j2     # Frontend Nginx template
│       └── backend.conf.j2      # Backend Nginx template
├── config/
│   └── env.example              # Environment variables template
└── README.md                    # This file
```

## ⚙️ Configuration

### Environment Variables

During deployment, the script creates a `.env` file from `config/env.example`. You'll be prompted to review and edit it.

**Critical variables to set:**
- `JWT_SECRET` - Strong random string for JWT tokens
- `JWT_REFRESH_SECRET` - Different strong random string for refresh tokens
- `DB_PASS` - PostgreSQL database password
- `MINIO_ROOT_PASSWORD` - MinIO root password (must match `MINIO_SECRET_KEY`)
- `MINIO_SECRET_KEY` - MinIO secret key

### Branch Selection

To deploy a specific version, edit branch variables in `deploy.sh`:

```bash
FRONTEND_BRANCH="v1.2.3"    # Deploy specific tag
BACKEND_BRANCH="production"  # Deploy production branch
```

Or set as environment variables:

```bash
export FRONTEND_BRANCH="main"
export BACKEND_BRANCH="dev"
./deploy.sh
```

### Domain and Email Configuration

**All domain and email configuration is in `.env` file** - update once, used everywhere:

```bash
# In .env file
FRONTEND_DOMAIN=myschool.com
BACKEND_DOMAIN=api.myschool.com
SSL_EMAIL=admin@myschool.com
```

These values are automatically used for:
- SSL certificate generation
- Nginx configuration
- Application URLs

### Repository Action

Control clone vs update:

- `REPO_ACTION="pull"` - Updates existing repos (default, faster)
- `REPO_ACTION="clone"` - Removes and re-clones (fresh start)

## 🔒 SSL Certificate Setup

SSL certificates are automatically configured when domains are set:

1. Set `FRONTEND_DOMAIN` and `BACKEND_DOMAIN` in `deploy.sh`
2. Ensure DNS records point to your server
3. Port 80 must be accessible from internet
4. Certificates auto-renew via systemd timer

**Manual renewal:**
```bash
sudo certbot renew
```

## 🌐 Nginx Configuration

Nginx configurations are generated from Jinja2 templates:

- **Frontend**: Proxies to `http://localhost:3000` (Next.js)
- **Backend**: Proxies to `http://localhost:3008` (NestJS API)

Configs installed to:
- `/etc/nginx/sites-available/schoolbase-frontend`
- `/etc/nginx/sites-available/schoolbase-backend`

## 🐳 Docker Compose Services

### Combined App Container

- **Frontend** (Next.js): Port 3000
- **Backend** (NestJS): Port 3008
- **Supervisor**: Manages both processes
- **Health Check**: Checks backend `/health` endpoint

### Postgres Container

- **Port**: 5432 (configurable)
- **Version**: PostgreSQL 16
- **Data**: Persistent volume `postgres_data`

### MinIO Container

- **API Port**: 9000
- **Console Port**: 9001 (web UI)
- **Data**: Persistent volume `minio_data`
- **Access**: Default `minioadmin` / `minioadmin123` (change in `.env`)

**⚠️ Important**: After first deployment, create a bucket in MinIO console:
1. Access: `http://your-server-ip:9001`
2. Login with credentials from `.env`
3. Create bucket: `schoolbase` (or update `MINIO_BUCKET_NAME`)

### Useful Commands

```bash
# View all logs
docker-compose logs -f

# View specific service
docker-compose logs -f app
docker-compose logs -f postgres
docker-compose logs -f minio

# Stop services
docker-compose down

# Restart services
docker-compose restart

# Rebuild combined image
docker-compose up -d --build app

# View running containers
docker-compose ps
```

## 🔄 Updating Deployment

To update to a new version:

1. Edit branch/tag in `deploy.sh`
2. Set `REPO_ACTION="pull"`
3. Run `./deploy.sh`

The script will:
- Pull latest changes from specified branches
- Rebuild the combined Docker image
- Restart services with zero-downtime (if configured)

## 🏫 Single vs Multi-Tenant Deployment

### Single Instance (Current Setup)

One deployment serves one school:
- One combined container
- One database
- One MinIO instance
- Configured via `.env`

### Multi-Tenant (Future)

Same combined image, multiple instances:

```bash
# Deploy school 1
docker-compose -f docker-compose.yml -p school1 up -d

# Deploy school 2 (different .env)
docker-compose -f docker-compose.yml -p school2 up -d
```

Each instance:
- Uses same combined image
- Has its own database (different `DB_NAME`)
- Can share MinIO (different buckets) or use separate MinIO
- Configured via different `.env` files

## 🛠️ Troubleshooting

### Services Won't Start

Check logs:
```bash
docker-compose logs app
docker-compose ps
```

### Combined Container Issues

Check supervisor logs:
```bash
docker exec schoolbase-app cat /var/log/supervisor/supervisord.log
docker exec schoolbase-app cat /var/log/supervisor/backend.err.log
docker exec schoolbase-app cat /var/log/supervisor/frontend.err.log
```

### SSL Certificate Issues

1. Verify DNS:
   ```bash
   dig yourdomain.com
   ```

2. Check port 80:
   ```bash
   sudo netstat -tlnp | grep :80
   ```

3. Test manually:
   ```bash
   sudo certbot certonly --standalone -d yourdomain.com
   ```

### Nginx Configuration Errors

Test config:
```bash
sudo nginx -t
```

View errors:
```bash
sudo tail -f /var/log/nginx/error.log
```

### Database Connection Issues

1. Check container:
   ```bash
   docker-compose ps postgres
   docker-compose logs postgres
   ```

2. Verify `.env` variables match

### MinIO Setup

1. Access console: `http://your-server-ip:9001`
2. Login with credentials from `.env`
3. Create bucket: `schoolbase`
4. Verify backend can connect (check backend logs)

## 🔐 Security Considerations

1. **Change Default Passwords**:
   - Update all passwords in `.env`
   - Especially: `DB_PASS`, `MINIO_ROOT_PASSWORD`, `MINIO_SECRET_KEY`

2. **Strong JWT Secrets**:
   - Generate strong random strings
   - Use different values for `JWT_SECRET` and `JWT_REFRESH_SECRET`

3. **Enable SSL**:
   - Always use HTTPS in production
   - Certificates auto-renew via Let's Encrypt

4. **Firewall Rules**:
   - Restrict access to management ports (9001, 5432)
   - Only expose 80, 443, 3000, 3008 publicly

5. **Regular Updates**:
   - Keep Docker images updated
   - Update system packages regularly

## 📚 Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [MinIO Documentation](https://min.io/docs/)
- [Supervisor Documentation](http://supervisord.org/)

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section
2. Review service logs: `docker-compose logs`
3. Check GitHub issues in application repositories

## 📄 License

This deployment repository is part of the SchoolBase project.
