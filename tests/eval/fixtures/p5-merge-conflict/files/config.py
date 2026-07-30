"""Runtime configuration for the ingest service."""

POOL_SIZE = 4
REQUEST_TIMEOUT = 30
LOG_LEVEL = "INFO"


def summary():
    return "pool=%d timeout=%d level=%s" % (
        POOL_SIZE,
        REQUEST_TIMEOUT,
        LOG_LEVEL,
    )
