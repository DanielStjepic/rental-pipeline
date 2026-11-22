from rental_pipeline import fda
import requests,pytest, json
from rental_pipeline.fda import TransientApiException

def test_short_page_stop_loop(monkeypatch):
    calls = []
    def fake_fetch_page(limit: int, skip: int):
        calls.append(skip)
        data = [{"recall_number": f'R{i}'} for i in range(5)]
        shortdata = [{"recall_number": f'R{i}'} for i in range(2)]

        if skip < 10:
            return data
        else:
            return shortdata
    monkeypatch.setattr(fda.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(fda, "fetch_page", fake_fetch_page)
    records = fda.fetch_all_pages(5)

    assert len(records) == 12

    assert calls == [0,5,10]

def test_fetch_all_pages_stops_on_404_after_data(monkeypatch):
    calls = []
    resp = requests.Response()
    resp.status_code = 404
    def fake_fetch_page(limit: int, skip: int):
        calls.append(skip)
        data = [{"recall_number": f'R{i}'} for i in range(5)]
        if skip < 10:
            return data
        else:
            raise requests.HTTPError(response = resp)


    monkeypatch.setattr(fda.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(fda, "fetch_page", fake_fetch_page)
    records = fda.fetch_all_pages(5)
    assert len(records) == 10

    assert calls == [0,5,10]

def test_fetch_all_pages_404_stops_on_first_call(monkeypatch):
    calls = []
    resp = requests.Response()
    resp.status_code = 404
    def fake_fetch_page(limit: int, skip: int):
        calls.append(skip)
        raise requests.HTTPError(response = resp)

    monkeypatch.setattr(fda.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(fda, "fetch_page", fake_fetch_page)
    with pytest.raises(requests.HTTPError) as exc:
        
        fda.fetch_all_pages(5)

    assert len(calls) == 1
    assert calls == [0]
    assert exc.value.response.status_code == 404


def test_fetch_all_pages_400_stops_on_first_call(monkeypatch):
    calls = []
    resp = requests.Response()
    resp.status_code = 400
    def fake_fetch_page(limit: int, skip: int):
        calls.append(skip)
        raise requests.HTTPError(response = resp)

    monkeypatch.setattr(fda.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(fda, "fetch_page", fake_fetch_page)
    with pytest.raises(requests.HTTPError) as exc:
        
        fda.fetch_all_pages(5)

    assert len(calls) == 1
    assert calls == [0]
    assert exc.value.response.status_code == 400

def test_fetch_all_pages_hit_max_pages(monkeypatch):
    calls = []
    data = [{'recall_number': f'R{i}'} for i in range (5)]
    def fake_fetch_page(limit: int, skip: int):
        calls.append(skip)
        return data
    monkeypatch.setattr(fda.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(fda, "fetch_page", fake_fetch_page)
    records = fda.fetch_all_pages(5, max_pages = 3)

    assert len(records) == 15
    assert calls == [0,5,10]



def test_fetch_page_returns_results_on_200(monkeypatch):
    data = {"results": [{"response_code": "R1"},{"response_code": "R2"}]}
    def fake_requests_get(url,params= None, timeout=None):
        resp = requests.Response()
        dic = json.dumps(data).encode()
        resp.status_code = 200
        resp._content = dic
        return resp
    
    monkeypatch.setattr(fda.requests, "get", fake_requests_get)
    result = fda.fetch_page(2,0)

    assert result == data["results"]

def test_fetch_page_returns_503(monkeypatch):
    def fake_requests_get(url,params= None, timeout=None):
        resp = requests.Response()
        resp.status_code = 503
        resp._content = None
        return resp
    
    monkeypatch.setattr(fda.requests, "get", fake_requests_get)
    with pytest.raises(TransientApiException) as exc:
        fda.fetch_page(2,0)

@pytest.mark.parametrize("status_code, expected",[(503, TransientApiException),(429,TransientApiException), (400,requests.HTTPError), (404, requests.HTTPError)], ids=['503','429','400','404'])
def test_fetch_page_raises_expected_exception(monkeypatch,status_code,expected):
    def fake_requests_get(url,params= None, timeout=None,):
        resp = requests.Response()
        resp.status_code = status_code
        resp._content = None
        return resp
    
    monkeypatch.setattr(fda.requests, "get", fake_requests_get)
    with pytest.raises(expected):
        fda.fetch_page(2,0)
    

