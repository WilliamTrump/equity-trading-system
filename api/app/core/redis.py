from redis.asyncio import ConnectionPool, Redis
from app.core.config import redis_host, redis_port_number, computed_max_connections

# 5. Initialize your pool using the computed value
pool = ConnectionPool(
    host=redis_host,
    port=redis_port_number,
    db=0,
    max_connections=computed_max_connections,
    decode_responses=True,
)

redis_client = Redis(ConnectionPool=pool)

redis_dictionaries = [
    "users",
    "accounts",
    "positions",
    "username",
]  # redis dicts TODO update these tables once agrred upon naming convention
