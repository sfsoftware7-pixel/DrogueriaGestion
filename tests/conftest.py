"""Fixtures compartidos. No conectan a MySQL: las pruebas de integración son opt-in."""
import pytest

from config import TestConfig
from app import create_app


@pytest.fixture
def client(monkeypatch):
    app = create_app(TestConfig)
    app.config.update(TESTING=True, SECRET_KEY='test-key-not-for-production')
    # La petición sin sesión no debe consultar MySQL; devolver None hace detectable cualquier consulta inesperada.
    monkeypatch.setattr('app.seguridad.consultar_uno', lambda *_args, **_kwargs: None)
    with app.test_client() as test_client:
        yield test_client
