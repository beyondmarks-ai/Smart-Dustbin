import importlib.util
import json
import os
import sys
import types
import unittest
from pathlib import Path


class FakeTable:
    def __init__(self):
        self.items = []

    def query(self, **_kwargs):
        return {"Items": list(reversed(self.items))}

    def put_item(self, Item):
        self.items.append(Item)


class FakeSecrets:
    def get_secret_value(self, **_kwargs):
        return {"SecretString": "test-ingest-key"}


class FakeKey:
    def __init__(self, name):
        self.name = name

    def eq(self, value):
        return (self.name, value)


fake_table = FakeTable()
boto3 = types.ModuleType("boto3")
boto3.resource = lambda _service: types.SimpleNamespace(Table=lambda _name: fake_table)
boto3.client = lambda _service: FakeSecrets()
conditions = types.ModuleType("boto3.dynamodb.conditions")
conditions.Key = FakeKey
sys.modules["boto3"] = boto3
sys.modules["boto3.dynamodb"] = types.ModuleType("boto3.dynamodb")
sys.modules["boto3.dynamodb.conditions"] = conditions
os.environ["TABLE_NAME"] = "test-table"
os.environ["INGEST_SECRET_ARN"] = "test-secret"

module_path = Path(__file__).parent / "function" / "app.py"
spec = importlib.util.spec_from_file_location("waste_app", module_path)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def event(method, path="/api/waste", body=None, api_key=None):
    headers = {"x-api-key": api_key} if api_key else {}
    return {
        "rawPath": path,
        "headers": headers,
        "requestContext": {"http": {"method": method}},
        "body": json.dumps(body) if body is not None else None,
    }


class HandlerTest(unittest.TestCase):
    def setUp(self):
        fake_table.items.clear()

    def test_health(self):
        response = app.handler(event("GET", "/health"), None)
        self.assertEqual(response["statusCode"], 200)

    def test_rejects_unauthorized_ingestion(self):
        response = app.handler(event("POST", body={"items": [{}]}), None)
        self.assertEqual(response["statusCode"], 401)

    def test_creates_then_lists_waste(self):
        payload = {
            "waste_confidence": 0.95,
            "items": [{"name": "Bottle", "recyclable": True}],
        }
        created = app.handler(
            event("POST", body=payload, api_key="test-ingest-key"), None
        )
        listed = app.handler(event("GET"), None)

        self.assertEqual(created["statusCode"], 201)
        self.assertEqual(listed["statusCode"], 200)
        records = json.loads(listed["body"])["items"]
        self.assertEqual(records[0]["items"][0]["name"], "Bottle")
        self.assertIn("event_id", records[0])
        self.assertIn("captured_at", records[0])


if __name__ == "__main__":
    unittest.main()
