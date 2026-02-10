import json
import os
import time

from flask import Flask, jsonify, request
from redis import Redis

app = Flask(__name__)

redis_client = Redis(
    host=os.environ.get("REDIS_HOST", "localhost"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    password=os.environ.get("REDIS_PASSWORD", None),
    decode_responses=True,
)

NEWS_KEY = "devops_news"


@app.route("/health")
def health():
    try:
        redis_client.ping()
        return jsonify({"status": "ok"}), 200
    except Exception:
        return jsonify({"status": "unhealthy"}), 503


@app.route("/news", methods=["GET"])
def get_news():
    raw_items = redis_client.lrange(NEWS_KEY, 0, -1)
    news = [json.loads(item) for item in raw_items]
    return jsonify(news), 200


@app.route("/news", methods=["POST"])
def add_news():
    data = request.get_json(force=True)
    title = data.get("title", "").strip()
    content = data.get("content", "").strip()

    if not title:
        return jsonify({"error": "title is required"}), 400

    entry = {
        "title": title,
        "content": content,
        "timestamp": time.time(),
    }
    redis_client.lpush(NEWS_KEY, json.dumps(entry))
    return jsonify(entry), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
