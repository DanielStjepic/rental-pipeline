import pytest
import requests

from rental_pipeline import retry
from rental_pipeline.fda import TransientApiException

RETRY_ON = (TransientApiException, requests.Timeout, requests.ConnectionError)


def test_run_with_retry_returns_value_on_first_success(monkeypatch):
    number = 5
    calls = []

    def fake_returning_func():
        calls.append(number)
        return number

    monkeypatch.setattr(retry.time, "sleep", lambda seconds: None)
    result = retry.run_with_retry(fake_returning_func, retry_on=RETRY_ON)

    assert result == number
    assert len(calls) == 1


def test_run_with_retry_returns_value_on_second_attempt(monkeypatch):
    number = 5
    calls = []

    def fake_returning_func():
        calls.append(number)
        if len(calls) == 1:
            raise TransientApiException
        else:
            return number

    monkeypatch.setattr(retry.time, "sleep", lambda seconds: None)
    result = retry.run_with_retry(fake_returning_func, retry_on=RETRY_ON)

    assert result == number
    assert len(calls) == 2


def test_run_with_retry_raises_after_max_attempts(monkeypatch):
    number = 5
    calls = []

    def fake_returning_func():
        calls.append(number)
        raise TransientApiException

    monkeypatch.setattr(retry.time, "sleep", lambda seconds: None)
    with pytest.raises(TransientApiException):
        retry.run_with_retry(fake_returning_func, retry_on=RETRY_ON)
    assert len(calls) == 3


def test_run_with_retry_raises_immediately_on_unlisted_exception(monkeypatch):
    number = 5
    calls = []

    def fake_returning_func():
        calls.append(number)
        raise ValueError

    monkeypatch.setattr(retry.time, "sleep", lambda seconds: None)
    with pytest.raises(ValueError):
        retry.run_with_retry(fake_returning_func, retry_on=RETRY_ON)
    assert len(calls) == 1