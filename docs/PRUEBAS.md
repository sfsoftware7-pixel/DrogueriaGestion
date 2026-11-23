# Plan e informe de pruebas

## 1. Estrategia

Se preparó una suite automatizada en `tests/` con tres perspectivas complementarias. La caja negra comprueba respuestas observables HTTP; la caja blanca verifica reglas y ramas internas; la caja gris contrasta el comportamiento/consultas con restricciones del esquema SQL. Los casos de escritura real contra MySQL están separados de las pruebas que pueden ejecutarse sin datos persistentes.

## 2. Casos de prueba

### Caja negra (sin inspeccionar implementación en la ejecución del caso)

| ID | Entrada/acción | Resultado esperado |
|---|---|---|
| BN-01 | GET `/api/ventas` sin sesión | HTTP 401, JSON de sesión expirada. |
| BN-02 | POST `/api/auth/login` con JSON vacío | HTTP 422, campo obligatorio señalado, sin consultar credenciales. |
| BN-03 | POST login con cuerpo no JSON | HTTP 400, mensaje de JSON requerido. |
| BN-04 | GET ruta inexistente bajo `/api/` | HTTP 404. |
| BN-05 | GET `/api/ventas` con sesión vendedor inválida/no autenticada | Se deniega sin datos; sesión real se cubre con fixture de integración. |

### Caja blanca (estructura y caminos de reglas)

| ID | Regla/camino | Resultado esperado |
|---|---|---|
| BB-01 | Entero mínimo válido, límite inferior y superior fuera de rango | Normalización correcta; valor fuera de rango produce error 422 de validación. |
| BB-02 | Decimal con empate de centavo | Redondeo comercial `ROUND_HALF_UP`. |
| BB-03 | Email con espacios/mayúsculas | Se recorta y normaliza a minúsculas; inválido acumula error. |
| BB-04 | Escape de `%`, `_` y barra en patrón LIKE | Los comodines se convierten en caracteres literales. |
| BB-05 | FEFO con dos lotes y pedido parcial/total | Asigna primero vencimiento más próximo y conserva saldo. |
| BB-06 | FEFO con stock insuficiente | Devuelve fallo sin asignación parcial utilizable. |
| BB-07 | Consulta FULLTEXT con operador y comodines | Operadores no entran al término booleano; LIKE escapa comodines. |

### Caja gris (lógica conocida más contrato de persistencia)

| ID | Contrato | Resultado esperado |
|---|---|---|
| BG-01 | FK/UNIQUE/CHECK de ambas bases | El DDL declara integridad referencial, unicidad y cantidades/precios válidos. |
| BG-02 | Trigger de detalle de venta | Verifica correspondencia medicamento-lote, vencimiento y existencia. |
| BG-03 | Flujo de venta | El servicio contiene `FOR UPDATE`, filtro de fecha vigente, detalle y movimiento kárdex. |
| BG-04 | Flujo de tienda | Servicio usa transacción, `FOR UPDATE`, descuentos en inventario e historial. |
| BG-05 | Pedido | El esquema impone `total = subtotal - descuento + costo_envio`; duplicar producto en pedido no se admite. |
| BG-06 | Integridad de monto | La función de cálculo de ventas evita descuento mayor al total y efectivo insuficiente. |

## 3. Ejecución automatizada

Desde la raíz, instalar dependencias de gestión y pruebas (`python -m pip install -r requirements.txt`) y ejecutar:

```powershell
python -m pytest -q
```

La prueba de integración con base de datos requiere una instancia MySQL 8.x desechable y esquema separado `drogueria_gestion_test`. Nunca apuntar estas pruebas a `drogueria_gestion` con datos que se deban conservar. La suite incluida no ejecuta escrituras en MySQL por defecto.

## 4. Resultado de ejecución en este entorno

| Verificación | Resultado |
|---|---|
| Inspección de scripts, módulos, rutas, reglas y esquema | Completada como revisión estática. |
| `python -m pytest --version` | No ejecutable: `pytest` no está instalado. |
| Importación de dependencias Flask/PyMySQL | No ejecutable: falta PyMySQL (la importación se detuvo antes de consultar Flask). |
| Disponibilidad del servicio MySQL | No se pudo verificar: Windows denegó consulta de servicios por permisos del entorno. |
| Casos automatizados | Implementados en `tests/`; pendientes de ejecución tras instalar dependencias. No se reportan como aprobados. |

## 5. Criterios de aceptación y pendientes

- Casos BN/BB/BG aprobados al ejecutar `pytest` en entorno con dependencias.
- Para ampliar la evidencia de integración, instalar el esquema de gestión de prueba, ejecutar ventas/entradas reales y comparar inventario, detalle y kárdex antes/después.
- No se midieron carga, latencia, concurrencia real, accesibilidad visual, navegador cruzado, recuperación de respaldos ni despliegue HTTPS; deben registrarse como no probados.
- Las comprobaciones grises de DDL son comprobaciones de contrato del código fuente y no sustituyen una ejecución efectiva en MySQL.
