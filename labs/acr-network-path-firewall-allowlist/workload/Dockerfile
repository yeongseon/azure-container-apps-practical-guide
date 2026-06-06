FROM python:3.12-slim

WORKDIR /app

COPY app.py /app/app.py

# BUILD_TAG is baked in at image-build time so each of v1 / v-broken / v-recover
# has different content. This serves two purposes:
#   1. Forces a fresh pull on each tag switch (different content = different digest)
#   2. Lets /, /health prove WHICH tag the running replica was pulled from
ARG BUILD_TAG=unknown
ENV BUILD_TAG=${BUILD_TAG}

# pip install in its own layer so the build_tag arg above does not invalidate
# the dependency cache between v1 / v-broken / v-recover rebuilds.
RUN pip install --no-cache-dir flask==3.0.3 gunicorn==23.0.0

ENV PYTHONUNBUFFERED=1
EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
