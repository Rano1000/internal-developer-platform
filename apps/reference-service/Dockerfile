FROM public.ecr.aws/docker/library/python:3.14.8-alpine3.24

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt \
    && python -m pip uninstall --yes pip

RUN addgroup -g 10001 appuser \
    && adduser -D -u 10001 -G appuser -h /home/appuser appuser

COPY app.py .

USER 10001

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--access-logfile", "-", "app:app"]
