import base64
import hmac
import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key


_table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
_secrets = boto3.client("secretsmanager")
_ingest_key = None


class DecimalEncoder(json.JSONEncoder):
    def default(self, value):
        if isinstance(value, Decimal):
            return int(value) if value % 1 == 0 else float(value)
        return super().default(value)


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json; charset=utf-8",
            "cache-control": "no-store",
        },
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def _get_ingest_key():
    global _ingest_key
    if _ingest_key is None:
        secret = _secrets.get_secret_value(SecretId=os.environ["INGEST_SECRET_ARN"])
        _ingest_key = secret["SecretString"]
    return _ingest_key


def _header(headers, name):
    target = name.lower()
    for key, value in (headers or {}).items():
        if key.lower() == target:
            return value
    return ""


def _list_waste(event):
    query = event.get("queryStringParameters") or {}
    try:
        limit = min(100, max(1, int(query.get("limit", "100"))))
    except (TypeError, ValueError):
        return _response(400, {"message": "limit must be an integer"})

    result = _table.query(
        KeyConditionExpression=Key("record_type").eq("WASTE"),
        ScanIndexForward=False,
        Limit=limit,
    )
    return _response(200, {"items": [item["payload"] for item in result["Items"]]})


def _create_waste(event):
    supplied_key = _header(event.get("headers"), "x-api-key")
    if not supplied_key or not hmac.compare_digest(supplied_key, _get_ingest_key()):
        return _response(401, {"message": "invalid API key"})

    raw_body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")
    try:
        payload = json.loads(raw_body, parse_float=Decimal)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return _response(400, {"message": "body must be valid JSON"})

    if not isinstance(payload, dict):
        return _response(400, {"message": "body must be a JSON object"})
    if not isinstance(payload.get("items"), list) or not payload["items"]:
        return _response(400, {"message": "items must be a non-empty array"})

    event_id = str(payload.get("event_id") or uuid.uuid4())
    captured_at = str(
        payload.get("captured_at")
        or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    )
    payload["event_id"] = event_id
    payload["captured_at"] = captured_at
    _table.put_item(
        Item={
            "record_type": "WASTE",
            "sort_key": f"{captured_at}#{event_id}",
            "payload": payload,
        }
    )
    return _response(201, payload)


def handler(event, _context):
    request_context = event.get("requestContext") or {}
    http = request_context.get("http") or {}
    method = http.get("method", "GET").upper()
    path = event.get("rawPath") or "/"

    if method == "GET" and path == "/health":
        return _response(200, {"status": "ok", "service": "smart-dustbin"})
    if path != "/api/waste":
        return _response(404, {"message": "not found"})
    if method == "GET":
        return _list_waste(event)
    if method == "POST":
        return _create_waste(event)
    return _response(405, {"message": "method not allowed"})
