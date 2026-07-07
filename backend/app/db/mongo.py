from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import ASCENDING, DESCENDING
from pymongo.errors import OperationFailure

from app.core.config import get_settings

client: AsyncIOMotorClient | None = None
database: AsyncIOMotorDatabase | None = None


async def connect_to_mongo() -> None:
    global client, database

    settings = get_settings()
    client = AsyncIOMotorClient(settings.mongodb_uri)
    database = client[settings.mongodb_db_name]
    await create_indexes(database)


async def close_mongo_connection() -> None:
    global client, database

    if client is not None:
        client.close()

    client = None
    database = None


def get_database() -> AsyncIOMotorDatabase:
    if database is None:
        raise RuntimeError("MongoDB is not connected")
    return database


async def create_indexes(db: AsyncIOMotorDatabase) -> None:
    await db.users.create_index("email", unique=True)
    await db.workout_plans.create_index(
        [("user_id", ASCENDING), ("is_active", ASCENDING), ("created_at", DESCENDING)]
    )
    await db.workout_sessions.create_index([("user_id", ASCENDING), ("completed_on", DESCENDING)])
    await db.workout_sessions.create_index([("user_id", ASCENDING), ("completed_on", ASCENDING)], unique=True)
    await _drop_legacy_workout_progress_index(db)
    await db.workout_progress.create_index(
        [("user_id", ASCENDING), ("plan_id", ASCENDING), ("day", ASCENDING)],
        unique=True,
    )
    await db.water_logs.create_index([("user_id", ASCENDING), ("day", ASCENDING)], unique=True)


async def _drop_legacy_workout_progress_index(db: AsyncIOMotorDatabase) -> None:
    try:
        index = await db.workout_progress.index_information()
    except OperationFailure:
        return

    legacy_index = index.get("user_id_1_plan_id_1")
    if legacy_index is None or legacy_index.get("key") != [("user_id", 1), ("plan_id", 1)]:
        return

    try:
        await db.workout_progress.drop_index("user_id_1_plan_id_1")
    except OperationFailure:
        return
