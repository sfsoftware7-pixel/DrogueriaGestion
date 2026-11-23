"""Pruebas de caja negra de respuestas HTTP del back-office."""


def test_endpoint_protegido_sin_sesion_responde_401(client):
    respuesta = client.get('/api/ventas')

    assert respuesta.status_code == 401
    assert respuesta.get_json()['error'] == 'Su sesión ha expirado. Inicie sesión nuevamente.'


def test_login_json_vacio_reporta_campos_obligatorios(client):
    respuesta = client.post('/api/auth/login', json={})

    assert respuesta.status_code == 422
    assert set(respuesta.get_json()['errores']) == {'usuario', 'password'}


def test_login_sin_json_devuelve_error_de_formato(client):
    respuesta = client.post('/api/auth/login', data='no es json', content_type='text/plain')

    assert respuesta.status_code == 400
    assert respuesta.get_json()['error'] == 'Se esperaba un cuerpo JSON válido'


def test_api_desconocida_responde_404_json(client):
    respuesta = client.get('/api/ruta-que-no-existe')

    assert respuesta.status_code == 404
    assert respuesta.is_json
