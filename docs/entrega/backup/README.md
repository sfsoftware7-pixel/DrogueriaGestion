# Respaldo para entrega

`respaldo_completo_fuentes.sql` reúne en un solo archivo los esquemas, vistas, rutinas, triggers, mejoras y datos ficticios de prueba disponibles en el proyecto para `drogueria_gestion` y `drogueria_db`.

Este es un respaldo armado desde los scripts fuente, no una exportación de una instancia MySQL activa. Al generarlo, MySQL no respondía en `127.0.0.1:3306`; por tanto, puede no contener datos ingresados después de instalar las bases ni las ventas de demostración que `database/init_db.py` genera dinámicamente.

## Restauración

Desde la raíz del proyecto, con MySQL activo y un usuario con permisos para crear bases:

```powershell
mysql -u USUARIO_ADMIN -p < docs/entrega/backup/respaldo_completo_fuentes.sql
```

**Atención:** los scripts de esquema ejecutan `DROP DATABASE` y recrean las dos bases. La restauración reemplaza su contenido actual.

## Respaldo de una instancia activa

Para obtener un volcado de los datos reales de una instancia MySQL, configure el login path `drogueria-backup` con `mysql_config_editor` y ejecute desde la raíz:

```powershell
powershell -ExecutionPolicy Bypass -File database/backup_mysql.ps1 -Database drogueria_gestion
powershell -ExecutionPolicy Bypass -File database/backup_mysql.ps1 -Database drogueria_db
```

El script guarda cada volcado con fecha y hora en esta carpeta. Los archivos de respaldo pueden contener datos personales; no se suben a Git.
