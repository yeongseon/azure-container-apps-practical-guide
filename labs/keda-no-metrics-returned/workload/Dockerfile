FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py

ENV PYTHONUNBUFFERED=1 \
    PORT=8000 \
    MODE=healthy \
    DELAY_SECONDS=120 \
    OOM_MB=2048

EXPOSE 8000
CMD ["python", "/app/app.py"]
