# Especificación de requerimientos de software

## 1. Propósito

Especificar el comportamiento observado en el código del repositorio para la entrega académica de bases de datos. Este documento no convierte funcionalidades planeadas en funcionalidades implementadas.

## 2. Actores

| Actor | Responsabilidad |
|---|---|
| Administrador | Administración completa, usuarios, auditoría, configuración y modelo de datos. |
| Regente | Operación farmacéutica, catálogo, inventario, ventas, anulaciones e informes. |
| Vendedor | Atención a clientes y registro de ventas; el descuento puede estar limitado por configuración. |
| Bodega | Recepción, ajustes, consulta de inventario y proveedores. |
| Comprador invitado | Consulta el catálogo público y genera/consulta pedidos de la tienda. |
| Cliente registrado | Inicia sesión en una cuenta existente y consulta sus datos y pedidos. |

## 3. Requerimientos funcionales

| ID | Requerimiento | Módulo / evidencia |
|---|---|---|
| RF-01 | Iniciar y cerrar sesión; validar credenciales y estado de usuario. | `app/routes/auth.py` |
| RF-02 | Limitar intentos fallidos y bloquear temporalmente la cuenta. | `app/routes/auth.py`, `usuarios` |
| RF-03 | Aplicar permisos basados en rol en el servidor. | `app/seguridad.py` |
| RF-04 | Consultar, crear, editar y desactivar medicamentos y categorías. | `app/routes/medicamentos.py`, `categorias.py` |
| RF-05 | Consultar, crear, editar y eliminar clientes sin historial; conservar mediante desactivación los que tienen facturas. Administrar proveedores. | `app/routes/clientes.py`, `proveedores.py` |
| RF-06 | Registrar recepción de mercancía, asociarla a proveedor/factura y crear o incrementar lotes. | `app/services/inventario.py` |
| RF-07 | Registrar ajustes de inventario con motivo y movimiento de kárdex. | `app/services/inventario.py` |
| RF-08 | Consultar existencias resumidas, lotes vencidos y alertas de vencimiento. | Tabla sincronizada `stock`, vistas `v_stock_medicamentos`, `v_lotes_vencimiento` |
| RF-09 | Registrar una venta con detalle, impuestos, descuento, medio de pago y cambio, y conservar su cabecera histórica. | `app/services/ventas.py`, tabla `historial_facturas` |
| RF-10 | Descontar existencias FEFO, excluyendo lotes vencidos y bloqueando filas durante la venta. | `app/services/ventas.py` |
| RF-11 | Exigir identificador de fórmula para medicamentos que la requieran. | `app/services/ventas.py` |
| RF-12 | Anular una venta una sola vez, restaurar existencias a los lotes originales y dejar kárdex. | `app/services/ventas.py` |
| RF-13 | Consultar reportes de ventas, auditoría y análisis ABC según permisos. | `app/routes/reportes.py`, `auditoria.py`, `analisis_abc.py` |
| RF-14 | Consultar catálogo, categorías, promociones, disponibilidad y búsqueda de la tienda. | `tienda/app/api/`, repositorios y servicios |
| RF-15 | Validar pedido invitado, cobertura, método de entrega y autorización de tratamiento de datos. | `tienda/app/servicios/pedidos.py` |
| RF-16 | Verificar tipo y firma del archivo de fórmula, fecha y límite de tamaño. | `tienda/app/servicios/pedidos.py` |
| RF-17 | Crear pedido de tienda en una transacción, congelar precio/descuento y asignar lote FEFO por sede. | `tienda/app/servicios/pedidos.py` |
| RF-18 | Consultar seguimiento mediante sesión autorizada o código y documento coincidentes. | `tienda/app/api/pedidos.py` |
| RF-19 | Iniciar/cerrar sesión de clientes existentes y consultar datos e historial de pedidos; no hay registro público. | `tienda/app/api/cuenta.py`, `tienda/app/servicios/cuentas.py` |
| RF-20 | Capturar ciudad y país del cliente y emitir un informe imprimible agrupado por país para administrador y vendedor. | `app/templates/_modal_cliente.html`, `/clientes/reporte-pais` |
| RF-21 | Administrar usuarios con altas, consultas, modificaciones y eliminación protegida; desactivar cuentas que tengan operaciones relacionadas. | `app/routes/usuarios.py` |
| RF-22 | Mantener el stock resumido al día y guardar una cabecera por factura dentro de la transacción de venta. | Triggers de `database/04_mejoras.sql` |

## 4. Requerimientos no funcionales

| ID | Requerimiento | Evidencia / observación |
|---|---|---|
| RNF-01 | Persistencia relacional transaccional. | MySQL, InnoDB, llaves foráneas y transacciones. |
| RNF-02 | Evitar SQL por concatenación de entradas del usuario. | Consultas PyMySQL usan parámetros `%s`; ordenaciones permitidas deben ser lista blanca. |
| RNF-03 | Mantener integridad y trazabilidad de inventario/ventas. | Restricciones SQL, kárdex, historial y auditoría. |
| RNF-04 | Proteger rutas internas por sesión, permiso y CSRF. | `app/seguridad.py`; cookie HttpOnly/SameSite y cabeceras. |
| RNF-05 | No registrar consultas de búsqueda de salud en logs HTTP. | Filtro `SinConsultaEnLog` de la tienda y logging de rutas sin query string. |
| RNF-06 | Separar credenciales de los fuentes. | Variables de entorno y archivos `.env.example`; definir clave estable en despliegue. |
| RNF-07 | Mantener operaciones compuestas atómicas y evitar sobreventa concurrente. | Transacciones, `SELECT ... FOR UPDATE`, errores de conflicto. |
| RNF-08 | Interfaz web adaptable y accesible. | HTML/CSS/JS en las dos aplicaciones; la validación visual de accesibilidad no se ejecutó en este informe. |

## 5. Reglas de negocio principales

1. Una venta solo usa medicamentos y clientes activos.
2. Cantidades de línea deben ser enteros positivos; no se puede vender más stock vigente que el disponible.
3. El lote seleccionado para venta/tienda debe corresponder al medicamento y no estar vencido.
4. FEFO significa consumir primero el lote con vencimiento más próximo.
5. Los medicamentos con fórmula requieren la referencia de fórmula en back-office y un archivo compatible en tienda.
6. El pago en efectivo debe cubrir el total; otros métodos reciben el total exacto como monto pagado en back-office.
7. Un descuento no puede superar el total; el rol vendedor está sujeto al tope configurado.
8. Una factura de proveedor no se puede registrar dos veces para el mismo proveedor.
9. El total del pedido de tienda cumple `subtotal - descuento + costo_envio`.
10. La compra en línea descuenta el inventario de la sede seleccionada dentro de la transacción.
11. Los clientes nuevos requieren ciudad y país; el país desconocido de registros históricos se conserva como “Sin especificar”.
12. No se permite borrar clientes con facturas ni usuarios con ventas o entradas; se desactivan para preservar trazabilidad.

## 6. Límites y supuestos

- No hay especificación externa de cliente, presupuesto, SLA, matriz completa de pantallas ni aceptación formal; los requerimientos se reconstruyeron de rutas, servicios, esquema y README existentes.
- La tienda permite iniciar sesión en cuentas existentes, pero no crear cuentas desde el sitio ni pagar mediante una pasarela electrónica real.
- Las reglas legales descritas en comentarios del código no constituyen certificación de cumplimiento normativo.
