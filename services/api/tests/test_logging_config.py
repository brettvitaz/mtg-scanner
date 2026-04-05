import logging
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from app.logging_config import (
    _RequestIdFilter,
    _configure_uvicorn_loggers,
    _request_id,
    get_logger,
    get_request_id,
    set_request_id,
    setup_logging,
)


def test_get_logger_returns_python_logger():
    logger = get_logger("test.module")
    assert isinstance(logger, logging.Logger)
    assert logger.name == "test.module"


def test_set_request_id_returns_uuid():
    rid = set_request_id()
    assert len(rid) == 36
    assert rid.count("-") == 4


def test_set_request_id_accepts_custom_value():
    rid = set_request_id("custom-123")
    assert rid == "custom-123"
    assert get_request_id() == "custom-123"


def test_get_request_id_returns_default_when_not_set():
    _request_id.set("-")
    rid = get_request_id()
    assert rid == "-"


def test_request_id_filter_adds_attribute():
    record = logging.LogRecord(
        name="test",
        level=logging.INFO,
        pathname="",
        lineno=0,
        msg="test",
        args=(),
        exc_info=None,
    )
    set_request_id("test-rid-456")
    f = _RequestIdFilter()
    assert f.filter(record) is True
    assert record.request_id == "test-rid-456"


def test_setup_logging_is_idempotent():
    setup_logging()
    root = logging.getLogger()
    handler_count = len(root.handlers)
    setup_logging()
    assert len(root.handlers) == handler_count


def test_setup_logging_creates_log_file():
    root = logging.getLogger()
    file_handlers = [
        h for h in root.handlers if isinstance(h, logging.handlers.RotatingFileHandler)
    ]
    assert len(file_handlers) >= 1
    log_path = Path(file_handlers[0].baseFilename)
    assert log_path.parent.name == "logs"


def test_configure_uvicorn_loggers_propagate():
    _configure_uvicorn_loggers()
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(name)
        assert logger.propagate is True
        assert len(logger.handlers) == 0


def test_log_message_includes_request_id(caplog):
    setup_logging()
    set_request_id("test-req-id")
    logger = get_logger("test.request_id")

    with caplog.at_level(logging.INFO):
        logger.info("hello %s", "world")

    assert "hello world" in caplog.text
    assert any(record.request_id == "test-req-id" for record in caplog.records)
