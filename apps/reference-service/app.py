from flask import Flask

app = Flask(__name__)


@app.get("/")
def index():
    return {"service": "reference-service", "version": "0.1.0"}


@app.get("/health")
def health():
    return {"status": "healthy"}
