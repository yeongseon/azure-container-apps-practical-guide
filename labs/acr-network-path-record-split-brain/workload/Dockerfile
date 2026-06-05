FROM python:3.12-slim

WORKDIR /app

COPY app.py /app/app.py

ENV PORT=80
ENV PYTHONUNBUFFERED=1

EXPOSE 80

CMD ["python", "/app/app.py"]
