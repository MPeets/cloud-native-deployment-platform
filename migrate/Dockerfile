FROM python:3.12-alpine

WORKDIR /app

RUN apk add --no-cache curl \
  && curl -fsSL -o /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

ENV PGSSLROOTCERT=/etc/ssl/certs/rds-global-bundle.pem

RUN pip install --no-cache-dir psycopg2-binary==2.9.9

COPY scripts/run_migrations.py scripts/
COPY migrations/ migrations/

CMD ["python", "scripts/run_migrations.py", "--migrations-dir", "migrations"]
