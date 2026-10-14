# The elm npm package just downloads a statically linked binary; copy that
# into the Python image so `runserver` can build and watch the page editor.
FROM node:24-slim AS elm

RUN npm install -g elm@0.19.2-0

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

COPY --from=elm /usr/local/lib/node_modules/elm/bin/elm /usr/local/bin/elm

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate && gunicorn linktree_project.wsgi:application --bind 0.0.0.0:8000"]
