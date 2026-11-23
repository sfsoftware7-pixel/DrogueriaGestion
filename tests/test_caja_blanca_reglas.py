"""Pruebas de caja blanca para validadores y reglas de negocio puras."""
from datetime import date, timedelta
from decimal import Decimal

import pytest

from app.services.ventas import _agrupar_items
from app.utils import ApiError, Validador, patron_busqueda, redondear
from tienda.app.servicios.catalogo import preparar_busqueda
from tienda.app.servicios.pedidos import _asignar_fefo


def test_validador_normaliza_texto_email_y_entero():
    validador = Validador({'nombre': '  Ana  ', 'email': ' Ana@Correo.COM ', 'cantidad': '3'})

    assert validador.texto('nombre') == 'Ana'
    assert validador.email('email', requerido=True) == 'ana@correo.com'
    assert validador.entero('cantidad', minimo=1, maximo=5) == 3
    validador.validar()


def test_validador_rechaza_enteros_y_email_invalidos():
    validador = Validador({'cantidad': 1.5, 'email': 'correo-invalido'})

    assert validador.entero('cantidad', minimo=1) is None
    assert validador.email('email', requerido=True) == 'correo-invalido'
    with pytest.raises(ApiError) as error:
        validador.validar()
    assert error.value.status == 422
    assert {'cantidad', 'email'} <= set(error.value.errores)


def test_redondeo_monetario_es_half_up():
    assert redondear(Decimal('1.005')) == Decimal('1.01')
    assert redondear(Decimal('1.004')) == Decimal('1.00')


def test_patron_like_escapa_metacaracteres():
    assert patron_busqueda(r'a%_\\b') == r'%a\%\_\\\\b%'


def test_agrupar_items_suma_repetidos_y_rechaza_cero():
    assert _agrupar_items([{'id_medicamento': '4', 'cantidad': '2'},
                           {'id_medicamento': 4, 'cantidad': 3}]) == {4: 5}
    with pytest.raises(ApiError):
        _agrupar_items([{'id_medicamento': 4, 'cantidad': 0}])


def test_asignacion_fefo_prioriza_vencimiento_cercano_y_conserva_saldo():
    hoy = date.today()
    lotes = [
        {'id_inventario': 20, 'id_lote': 8, 'cantidad': 5, 'fecha_vencimiento': hoy + timedelta(days=90)},
        {'id_inventario': 10, 'id_lote': 7, 'cantidad': 3, 'fecha_vencimiento': hoy + timedelta(days=20)},
    ]

    # El repositorio entrega lotes ordenados por FEFO; la regla consume en ese orden.
    resultado = _asignar_fefo(list(reversed(lotes)), 4)
    assert [(a['id_lote'], a['cantidad'], a['saldo']) for a in resultado] == [(7, 3, 0), (8, 1, 4)]


def test_asignacion_fefo_insuficiente_no_devuelve_asignacion_parcial():
    assert _asignar_fefo([{'id_inventario': 1, 'id_lote': 1, 'cantidad': 2}], 3) is None


def test_busqueda_catalogo_filtra_operadores_fulltext_y_escapa_like():
    termino, prefijo, contiene = preparar_busqueda('  acet% +dolor_  ')

    assert termino == '+acet* +dolor*'
    assert prefijo == r'acet\% +dolor\_%'
    assert contiene == r'%acet\% +dolor\_%'
