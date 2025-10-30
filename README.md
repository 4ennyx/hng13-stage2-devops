# Blue/Green Deployment with Nginx Auto-Failover

## Overview

This project implements a Blue/Green deployment pattern with automatic failover using Nginx as a reverse proxy. The system ensures zero failed client requests during primary service failures.

This setup implements a Blue/Green deployment pattern with automatic failover using Nginx as a reverse proxy. The system ensures zero failed client requests during primary service failures.


## Architecture
- **Nginx**: Reverse proxy with upstream failover configuration
- **Blue Service**: Primary active service (port 8081)
- **Green Service**: Backup service (port 8082)
- **Public Endpoint**: http://localhost:8080

## Quick Start


1. **Clone and setup**
   ```bash
   git clone https://github.com/4ennyx/hng13-stage2-devops.git
   cd hng13-stage2-devops
   cp .env.example .env

1. **Clone and setup**
   ```bash
   git clone <repository>
   cd blue-green-nginx

   cp .env.example .env

