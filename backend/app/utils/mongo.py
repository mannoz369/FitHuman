from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from bson import ObjectId


def object_id(value: str) -> ObjectId:
    if not ObjectId.is_valid(value):
        raise ValueError("Invalid object id")
    return ObjectId(value)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def day_key(value: datetime | None = None, timezone_name: str = "UTC") -> str:
    try:
        local_timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        local_timezone = timezone.utc

    source = value or utc_now()
    if source.tzinfo is None or source.tzinfo.utcoffset(source) is None:
        source = source.replace(tzinfo=timezone.utc)

    return source.astimezone(local_timezone).date().isoformat()


def serialize_document(document: dict[str, Any]) -> dict[str, Any]:
    serialized = dict(document)

    if "_id" in serialized:
        serialized["id"] = str(serialized.pop("_id"))

    for key, value in list(serialized.items()):
        if isinstance(value, ObjectId):
            serialized[key] = str(value)
        elif isinstance(value, dict):
            serialized[key] = serialize_document(value)
        elif isinstance(value, list):
            serialized[key] = [
                serialize_document(item) if isinstance(item, dict) else str(item) if isinstance(item, ObjectId) else item
                for item in value
            ]

    return serialized
