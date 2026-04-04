FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app.py ./

EXPOSE 3000

CMD ["gunicorn", "--bind", "0.0.0.0:3000", "--workers", "2", "app:app"]
