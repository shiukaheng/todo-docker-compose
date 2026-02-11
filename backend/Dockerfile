FROM python:3.11-slim

WORKDIR /app

COPY backend/repo/backend/pyproject.toml ./
RUN pip install --no-cache-dir .

COPY backend/repo/backend/app ./app

ENV NEO4J_URL=bolt://neo4j:7687
ENV NEO4J_USER=neo4j
ENV NEO4J_PASSWORD=password

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
