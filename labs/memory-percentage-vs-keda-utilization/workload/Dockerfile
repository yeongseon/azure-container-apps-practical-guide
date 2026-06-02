FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py

ENV PYTHONUNBUFFERED=1 \
    PORT=8000 \
    MODE=cache \
    TARGET_MB=700 \
    CACHE_FILE=/tmp/bigfile.bin

EXPOSE 8000
CMD ["python", "/app/app.py"]
