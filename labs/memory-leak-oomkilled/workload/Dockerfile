FROM python:3.12-slim

WORKDIR /app
COPY app.py /app/app.py

ENV PYTHONUNBUFFERED=1 \
    PORT=8000 \
    MODE=healthy \
    HARD_OOM_MB=600 \
    LEAK_MB_PER_TICK=30 \
    LEAK_INTERVAL_SECONDS=20

EXPOSE 8000
CMD ["python", "/app/app.py"]
