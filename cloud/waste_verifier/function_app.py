from __future__ import annotations

import json
import hmac
import logging
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote

import azure.functions as func

from azure_rest import AzureBlobService, ContentSettings, ManagedIdentityCredential
from waste_ai import CLASSIFIER_REVISION, analyze_frames, apply_verification_gate


app = func.FunctionApp()
credential = ManagedIdentityCredential()

RAW_CONTAINER = os.environ.get("RAW_CONTAINER", "wastemanagment")
ANALYSIS_CONTAINER = os.environ.get("ANALYSIS_CONTAINER", "waste-analysis")
VERIFIED_CONTAINER = os.environ.get("VERIFIED_CONTAINER", "verified-waste")
ACCOUNT_URL = os.environ["WASTE_STORAGE_ACCOUNT_URL"]
EVENT_PATTERN = re.compile(r"/containers/([^/]+)/blobs/motion/([^/]+)/frame_5\.jpg$")
EVENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def blob_service() -> AzureBlobService:
    return AzureBlobService(account_url=ACCOUNT_URL, credential=credential)


def process_event(
    event_id: str,
    detection_location: dict | None = None,
    device_id: str = "",
) -> dict:
    service = blob_service()
    analysis_blob = service.get_blob_client(ANALYSIS_CONTAINER, f"{event_id}.json")
    if analysis_blob.exists():
        return json.loads(analysis_blob.download_blob().readall())

    raw = service.get_container_client(RAW_CONTAINER)
    frames: list[bytes] = []
    frame_properties = []
    for frame_number in range(1, 6):
        client = raw.get_blob_client(f"motion/{event_id}/frame_{frame_number}.jpg")
        frames.append(client.download_blob().readall())
        frame_properties.append(client.get_blob_properties())

    analysis = apply_verification_gate(analyze_frames(frames, credential))
    analysis["event_id"] = event_id
    analysis["captured_at"] = (
        datetime.fromtimestamp(int(event_id), timezone.utc).isoformat()
        if event_id.isdigit() else frame_properties[0].last_modified.isoformat()
    )
    if detection_location:
        analysis["detection_location"] = detection_location
    if device_id:
        analysis["device_id"] = device_id

    if analysis["verification"]["verified"]:
        best_frame = max(1, min(5, int(analysis.get("best_frame", 1))))
        cover_path = f"{event_id}/cover.jpg"
        service.get_blob_client(VERIFIED_CONTAINER, cover_path).upload_blob(
            frames[best_frame - 1], overwrite=True,
            content_settings=ContentSettings(content_type="image/jpeg")
        )
        analysis["cover_blob"] = cover_path
        analysis["status"] = "verified"
    else:
        analysis["cover_blob"] = None
        analysis["status"] = "review" if analysis.get("items") else "rejected"

    analysis_blob.upload_blob(
        json.dumps(analysis, ensure_ascii=False, indent=2), overwrite=True,
        content_settings=ContentSettings(content_type="application/json")
    )
    return analysis


def _device_request_authorized(req: func.HttpRequest) -> bool:
    expected = os.environ.get("DEVICE_INGEST_KEY", "")
    supplied = req.headers.get("x-device-key", "")
    return bool(expected and supplied and hmac.compare_digest(expected, supplied))


@app.function_name(name="process_camera_event")
@app.route(route="api/process", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def process_camera_event(req: func.HttpRequest) -> func.HttpResponse:
    if not _device_request_authorized(req):
        return func.HttpResponse("Unauthorized", status_code=401)
    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse("Invalid JSON", status_code=400)
    event_id = str(payload.get("event_id", ""))
    if not EVENT_ID_PATTERN.fullmatch(event_id):
        return func.HttpResponse("Invalid event_id", status_code=400)

    location = payload.get("detection_location")
    if location is not None and not isinstance(location, dict):
        return func.HttpResponse("Invalid detection_location", status_code=400)
    try:
        result = process_event(event_id, location, str(payload.get("device_id", "")).strip())
    except Exception:
        logging.exception("Camera event %s could not be processed", event_id)
        return func.HttpResponse("Processing failed", status_code=500)
    return func.HttpResponse(json.dumps(result), mimetype="application/json")


@app.function_name(name="verify_uploaded_event")
@app.route(route="api/events", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def verify_uploaded_event(req: func.HttpRequest) -> func.HttpResponse:
    try:
        events = req.get_json()
    except ValueError:
        return func.HttpResponse("Invalid Event Grid payload", status_code=400)
    if isinstance(events, dict):
        events = [events]
    if not isinstance(events, list):
        return func.HttpResponse("Invalid Event Grid payload", status_code=400)

    for event in events:
        event_type = event.get("eventType", event.get("type", ""))
        data = event.get("data", {})
        if event_type == "Microsoft.EventGrid.SubscriptionValidationEvent":
            return func.HttpResponse(
                json.dumps({"validationResponse": data.get("validationCode")}),
                mimetype="application/json",
            )
        if event_type != "Microsoft.Storage.BlobCreated":
            continue
        match = EVENT_PATTERN.search(unquote(event.get("subject", "")))
        if not match or match.group(1) != RAW_CONTAINER:
            continue
        event_id = match.group(2)
        logging.info("Verifying camera event %s", event_id)
        result = process_event(event_id)
        logging.info(
            "Event %s result: %s (%.2f)",
            event_id,
            result["status"],
            result["waste_confidence"],
        )
    return func.HttpResponse(
        json.dumps({"accepted": True}), mimetype="application/json"
    )


@app.function_name(name="list_verified_waste")
@app.route(route="api/waste", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def list_verified_waste(req: func.HttpRequest) -> func.HttpResponse:
    try:
        limit = max(1, min(100, int(req.params.get("limit", "30"))))
    except ValueError:
        limit = 30

    container = blob_service().get_container_client(ANALYSIS_CONTAINER)
    records = []
    for blob in container.list_blobs():
        if not blob.name.endswith(".json"):
            continue
        record = json.loads(container.download_blob(blob.name).readall())
        if record.get("status") not in ("verified", "review"):
            continue
        if not record.get("items"):
            continue
        record["image_url"] = f"/api/waste/{record['event_id']}/image"
        records.append(record)
    records.sort(key=lambda value: value.get("captured_at", ""), reverse=True)
    return func.HttpResponse(
        json.dumps({"items": records[:limit], "count": min(len(records), limit)}),
        mimetype="application/json"
    )


@app.function_name(name="get_verified_image")
@app.route(route="api/waste/{event_id}/image", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_verified_image(req: func.HttpRequest) -> func.HttpResponse:
    event_id = req.route_params.get("event_id", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", event_id):
        return func.HttpResponse("Invalid event", status_code=400)
    analysis_client = blob_service().get_blob_client(ANALYSIS_CONTAINER, f"{event_id}.json")
    if not analysis_client.exists():
        return func.HttpResponse("Not found", status_code=404)
    record = json.loads(analysis_client.download_blob().readall())
    if record.get("status") == "verified":
        client = blob_service().get_blob_client(VERIFIED_CONTAINER, f"{event_id}/cover.jpg")
    else:
        best_frame = max(1, min(5, int(record.get("best_frame", 1))))
        client = blob_service().get_blob_client(
            RAW_CONTAINER, f"motion/{event_id}/frame_{best_frame}.jpg"
        )
    if not client.exists():
        return func.HttpResponse("Not found", status_code=404)
    return func.HttpResponse(client.download_blob().readall(), mimetype="image/jpeg")


@app.function_name(name="dashboard")
@app.route(route="dashboard", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def dashboard(req: func.HttpRequest) -> func.HttpResponse:
    html = (Path(__file__).parent / "dashboard.html").read_text(encoding="utf-8")
    return func.HttpResponse(html, mimetype="text/html")


@app.function_name(name="health")
@app.route(route="api/health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(json.dumps({
        "status": "ok", "service": "waste-ai-verifier",
        "classifier_revision": CLASSIFIER_REVISION,
        "time": datetime.now(timezone.utc).isoformat()
    }), mimetype="application/json")
