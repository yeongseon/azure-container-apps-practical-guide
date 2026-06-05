FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py

ENV PYTHONUNBUFFERED=1 \
    PORT=80 \
    BUILD_TAG=v1

EXPOSE 80
CMD ["python", "/app/app.py"]
