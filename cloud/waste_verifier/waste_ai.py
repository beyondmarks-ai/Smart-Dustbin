from __future__ import annotations

import base64
import json
import os
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

CLASSIFIER_REVISION = "2026-10-16-film-aware-v1"

SYSTEM_PROMPT = """You classify items presented to a dedicated smart-bin sorting camera.
Analyze all five chronological frames as one event. The foreground inspection area is where users
present items for recycling or disposal. Identify the visible item and its material for sorting.
This is a bin inspection station, not a general street-litter or abandonment detector.

Critical rules:
- A recognizable bottle, can, wrapper, paper, cardboard, food scrap or other sortable item presented
  prominently in the foreground is a waste/sorting candidate. It need not be crushed, dirty, broken,
  abandoned or inside a visible bin. Being intact or resting on the inspection surface does not
  by itself make it uncertain. Classify the object that is actually visible, without inventing intent.
- Ignore background furniture, vehicles, buildings, plants and appliances, and do not classify
  people, hands, shadows, reflections or camera noise as waste. A container clearly being used for
  drinking, for example, is not an item presented for sorting.
- Dark, obstructed, empty or unrecognizably blurred frames provide no positive evidence. Return
  uncertain when an object is visible but its identity is unclear; use not_waste when no sortable
  object is visible. Never infer an object from the fact that motion triggered the camera.
- Identify only items supported by visible evidence. Never invent materials or recycling instructions.
- Distinguish flexible plastic bags, polythene film and wrappers from rigid plastic bottles.
  Folds, flattened edges, crumpling and a collapsible sheet support plastic film/bag; transparency
  and shiny highlights alone do not support a bottle. Only name a bottle when a rigid vessel shape
  and diagnostic features such as its neck, opening, cap or molded base are actually visible.
- When glare, blur or cropping hides the distinguishing features, use a broad supported name
  such as "plastic packaging" and decision uncertain; do not confidently guess a specific object.
  If even the material is unclear, say unknown. Do not infer a polymer such as PET or LDPE without
  identifying evidence. All frames can show the same ambiguous object without making it certain.
- Flexible plastic film/bags generally require dedicated collection, not ordinary curbside plastic
  bottle recycling. State the local-facility limitation and do not apply rigid-bottle guidance to film.
- Recyclability is general guidance; explicitly note contamination and local-facility dependence.
- Reuse ideas must be practical and safe. Do not suggest reuse for hazardous, medical, chemical,
  sharp, contaminated, or unknown waste.
- frames_with_waste must contain only frame numbers 1 through 5 where the sortable item is clearly
  visible. Confidence must reflect visual evidence; do not raise it just to satisfy a threshold.
- Keep evidence_summary brief and based on visible facts, not hidden reasoning.
"""


RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "decision", "is_waste", "waste_confidence", "frames_with_waste",
        "best_frame", "summary", "evidence_summary", "items"
    ],
    "properties": {
        "decision": {"type": "string", "enum": ["verified_waste", "not_waste", "uncertain"]},
        "is_waste": {"type": "boolean"},
        "waste_confidence": {"type": "number", "minimum": 0, "maximum": 1},
        "frames_with_waste": {
            "type": "array", "items": {"type": "integer", "minimum": 1, "maximum": 5},
            "maxItems": 5
        },
        "best_frame": {"type": "integer", "minimum": 1, "maximum": 5},
        "summary": {"type": "string"},
        "evidence_summary": {"type": "string"},
        "items": {
            "type": "array",
            "maxItems": 8,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": [
                    "name", "category", "material", "recyclable", "recycling_confidence",
                    "recycling_guidance", "contamination_notes", "reuse_safe",
                    "best_from_waste_ideas", "safety_warnings"
                ],
                "properties": {
                    "name": {"type": "string"},
                    "category": {
                        "type": "string",
                        "enum": [
                            "plastic", "paper", "cardboard", "metal", "glass", "organic",
                            "electronic", "textile", "wood", "hazardous", "mixed", "other"
                        ]
                    },
                    "material": {"type": "string"},
                    "recyclable": {"type": "boolean"},
                    "recycling_confidence": {"type": "number", "minimum": 0, "maximum": 1},
                    "recycling_guidance": {"type": "string"},
                    "contamination_notes": {"type": "string"},
                    "reuse_safe": {"type": "boolean"},
                    "best_from_waste_ideas": {
                        "type": "array", "items": {"type": "string"}, "maxItems": 3
                    },
                    "safety_warnings": {
                        "type": "array", "items": {"type": "string"}, "maxItems": 4
                    }
                }
            }
        }
    }
}


def _image_data_url(image: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(image).decode("ascii")


def analyze_frames(frames: list[bytes], credential: Any) -> dict[str, Any]:
    if len(frames) != 5:
        raise ValueError("Exactly five frames are required for verification")

    endpoint = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
    deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")
    token = credential.get_token("https://cognitiveservices.azure.com/.default").token

    content: list[dict[str, Any]] = [{
        "type": "text",
        "text": "Verify this five-frame event. The images are chronological and labeled Frame 1 to Frame 5."
    }]
    for index, frame in enumerate(frames, start=1):
        content.append({"type": "text", "text": f"Frame {index}"})
        content.append({
            "type": "image_url",
            "image_url": {"url": _image_data_url(frame), "detail": os.environ.get("AZURE_VISION_DETAIL", "high")}
        })

    payload = {
        "model": deployment,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": content}
        ],
        "temperature": 0,
        "max_tokens": int(os.environ.get("AZURE_OPENAI_MAX_TOKENS", "1200")),
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": "waste_verification", "strict": True, "schema": RESPONSE_SCHEMA}
        }
    }
    request = Request(
        f"{endpoint}/openai/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=90) as response:
            response_payload = json.loads(response.read())
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Azure OpenAI HTTP {error.code}: {detail[:500]}") from error
    result = json.loads(response_payload["choices"][0]["message"]["content"])
    result["analyzed_at"] = datetime.now(timezone.utc).isoformat()
    result["model_deployment"] = deployment
    result["classifier_revision"] = CLASSIFIER_REVISION
    return result


def apply_verification_gate(analysis: dict[str, Any]) -> dict[str, Any]:
    threshold = float(os.environ.get("WASTE_CONFIDENCE_THRESHOLD", "0.80"))
    minimum_frames = int(os.environ.get("WASTE_MIN_FRAMES", "2"))
    visible_frames = sorted(set(
        frame for frame in analysis.get("frames_with_waste", [])
        if isinstance(frame, int) and 1 <= frame <= 5
    ))
    confidence = float(analysis.get("waste_confidence", 0))
    verified = (
        analysis.get("decision") == "verified_waste"
        and analysis.get("is_waste") is True
        and confidence >= threshold
        and len(visible_frames) >= minimum_frames
        and len(analysis.get("items", [])) > 0
    )
    analysis["frames_with_waste"] = visible_frames
    analysis["verification"] = {
        "verified": verified,
        "confidence_threshold": threshold,
        "minimum_confirming_frames": minimum_frames,
        "rejection_reason": None if verified else (
            f"Requires waste confidence >= {threshold:.0%} in at least {minimum_frames} frames"
        )
    }
    return analysis
