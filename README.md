# Droguería Gestión

Sistema web académico para administrar las operaciones de una droguería y prototipo separado de comercio electrónico.

## Alcance

El repositorio contiene dos aplicaciones Flask independientes:

- **Gestión interna** (`app/`): catálogo farmacéutico, usuarios y roles, clientes, recepción de compras, inventario por lotes, punto de venta, ventas, anulaciones, reportes, auditoría y exploración del modelo/consultas SQL. Usa la base `drogueria_gestion`.
- **Tienda en línea** (`tienda/`): catálogo público, búsqueda, carrito de navegador, pedidos como invitado o con una cuenta existente, cobertura, despacho o retiro, carga de fórmula médica y seguimiento. Usa `drogueria_db`.

Las bases y sus scripts de instalación son independientes; los identificadores entre ellas no son compartidos. La tienda es un prototipo con pago contra entrega y no incluye un panel administrativo ni una pasarela real.

## Documentación

Consulte el [índice de documentación](docs/README.md) para los requerimientos, arquitectura, diseño de datos y pruebas. En particular:

- [Arquitectura implementada](docs/ARQUITECTURA_GENERAL.md)
- [Bases de datos](docs/BASE_DATOS.md)
- [Pruebas de caja negra, blanca y gris](docs/PRUEBAS.md)

## Tecnologías

Python 3.13, Flask 3.1, PyMySQL y MySQL 8.x. El cliente web se implementa con HTML, CSS y JavaScript. Las dependencias de gestión están en `requirements.txt`; las de tienda en `tienda/requirements.txt`.

## Puesta en marcha resumida

1. Cree su entorno virtual e instale `pip install -r requirements.txt`.
2. Configure `.env` a partir de `.env.example`.
3. Instale la base de gestión con `python database/init_db.py` (se pide confirmación si ya existe porque la reinstalación borra sus datos).
4. Inicie el back-office con `python run.py`.
5. Para la tienda, siga los pasos detallados en [tienda/README.md](tienda/README.md); su esquema es `database/schema.sql` y sus datos iniciales `database/seed.sql`.

La configuración de prueba del back-office apunta a `drogueria_gestion_test`. No configure pruebas para usar la base de producción o una base con información real.

## Estado de verificación en este entorno

El código y los scripts se documentaron y se agregó una suite automatizada. En el entorno de elaboración no están instalados PyMySQL ni pytest y el servicio MySQL no pudo comprobarse por restricciones del entorno. Por tanto, la suite está lista para ejecutarse tras instalar dependencias, pero no se declara aquí como pasada. Véase [el informe de pruebas](docs/PRUEBAS.md).
