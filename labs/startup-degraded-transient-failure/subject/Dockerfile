# Deterministic subject image for the startup-degraded-transient-failure lab.
#
# Goals:
#   - Pin Python to a known minor version for reproducibility.
#   - Use a slim base to keep the image small and the cold start fast.
#   - No package installs: server.py only uses the Python stdlib.
#   - ENTRYPOINT runs the server directly so the container's PID 1 owns
#     the startup-delay-begin / listening markers.
#
# Build:
#   docker build --tag $ACR.azurecr.io/startup-degraded/subject:latest .
#
# Push to ACR:
#   az acr build --registry $ACR --image startup-degraded/subject:latest .

FROM mcr.microsoft.com/azurelinux/base/python:3.12

WORKDIR /app

# Copy the server module. The file is small and self-contained; we copy
# it AFTER the FROM/WORKDIR so layer caching works on rebuilds where
# only the script changes.
COPY server.py /app/server.py

# Defaults match the lab's reference profile. They are also documented
# in the lab guide; overriding them at the Container App level changes
# the experiment parameters, which is intentional.
ENV STARTUP_DELAY_SECONDS=25 \
    REQUEST_DELAY_MS=0 \
    PORT=8080 \
    PYTHONUNBUFFERED=1

EXPOSE 8080

# Use the JSON exec form so SIGTERM is forwarded to the Python process,
# which lets the platform terminate replicas cleanly during rollout.
ENTRYPOINT ["python3", "/app/server.py"]
