# Step 3 Demo Application

A simple Flask web application demonstrating Jenkins CI/CD pipeline with Docker containerization.

## Features

- Simple REST API with health check endpoint
- Docker containerization
- Jenkins pipeline integration
- Automated testing
- Deployment packaging

## Endpoints

- `GET /` - Main application endpoint with build info
- `GET /health` - Health check endpoint

## Local Development

1. Install dependencies:
   ```bash
   pip3 install -r requirements.txt
   ```

2. Run the application:
   ```bash
   python3 app.py
   ```

3. Test the application:
   ```bash
   curl http://localhost:5000/
   curl http://localhost:5000/health
   ```

## Docker Usage

1. Build the image:
   ```bash
   docker build -t step3-demo-app .
   ```

2. Run the container:
   ```bash
   docker run -p 5000:5000 step3-demo-app
   ```

## Jenkins Pipeline

The application includes a complete Jenkins pipeline that:
- Checks out source code
- Gathers environment information
- Builds the application
- Runs tests
- Creates Docker image
- Packages for deployment

## Build Information

The application exposes build information including:
- Build number
- Git commit hash
- Build timestamp
- Hostname
