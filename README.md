# expedientes-deploy

Configuración de despliegue del sistema de gestión de expedientes jurídicos — Rosales y Asociados.

## Repositorios del sistema

| Repo | URL | Rama |
|---|---|---|
| `expedientes-app` | https://github.com/black7in/expedientes-app.git | `develop` |
| `expedientes-ai` | https://github.com/black7in/expedientes-ai.git | `master` |
| `expedientes-deploy` | https://github.com/black7in/expedientes-deploy.git | `master` |

---

## Requisitos del servidor

- Docker >= 24 + Docker Compose v2
- Git
- 4 GB RAM mínimo (el modelo E5-large ocupa ~1.2 GB en RAM durante indexación)
- Puerto 80 (o el que definas en `APP_PORT`) abierto en el firewall

---

## Primer despliegue completo

Seguir los pasos en orden. No saltear ninguno.

### 1. Clonar los tres repositorios

```bash
cd ~
git clone https://github.com/black7in/expedientes-app.git
git clone https://github.com/black7in/expedientes-ai.git
git clone https://github.com/black7in/expedientes-deploy.git
```

### 2. Configurar variables de entorno

```bash
cd ~/expedientes-deploy
cp .env.example .env
nano .env
```

Completar **todos** los valores marcados como CAMBIA_ESTO:

- `APP_KEY` — generar con el siguiente comando y pegar el resultado:
  ```bash
  docker run --rm php:8.3-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"
  ```
- `APP_URL` — URL pública del servidor, ej: `http://34.27.64.244`
- `APP_PORT` — puerto externo (80 por defecto; usar 8080 si el 80 está ocupado)
- `DB_PASSWORD` — contraseña segura para PostgreSQL
- `ANTHROPIC_API_KEY` — API key del proveedor LLM (ver opciones en `.env.example`)
- `LLM_MODEL` — modelo a usar (por defecto `claude-sonnet-4-6`)

### 3. Build de imágenes Docker

> Este paso tarda 5-10 minutos la primera vez (descarga dependencias PHP, Python y el modelo E5-large de HuggingFace ~1.2 GB). Las siguientes actualizaciones usan caché y tardan ~1-2 minutos.
> **Nunca usar `--no-cache`** — fuerza recompilar todo desde cero.

```bash
cd ~/expedientes-deploy
docker compose build
```

### 4. Levantar la base de datos primero

```bash
docker compose up -d postgres redis
```

Esperar que PostgreSQL esté saludable (verificar con `docker compose ps` — debe decir `healthy`):

```bash
docker compose ps postgres
```

### 5. Correr migraciones

```bash
docker compose run --rm app php artisan migrate --force
```

Esto crea todas las tablas:
- `users`, `personas`, `expedientes`, `partes`, `juzgados`, `tipos_proceso`, `actuaciones`, `documentos`
- `leyes_chunks`, `doc_chunks`, `jurisprudencia_chunks` (con extensión pgvector)
- `plantillas`, `generaciones`, `generacion_secciones` (módulo RAG)

### 6. Correr seeders

```bash
docker compose run --rm app php artisan db:seed --force
```

Esto crea:
- Usuarios iniciales: `admin@rosalesasociados.bo` / `password` y `abogado@rosalesasociados.bo` / `password`
- 4 tipos de proceso (Ley 439): Ordinario, Extraordinario, Monitorio, Ejecución
- Juzgados de ejemplo
- 5 plantillas RAG: Demanda Ejecutiva, Coactiva, Tercería, Desalojo, Ordinaria Civil

### 7. Levantar todos los servicios

```bash
docker compose up -d
```

### 8. Verificar que todo esté corriendo

```bash
docker compose ps
```

Todos los servicios deben aparecer como `running`. Verificar logs si alguno falla:

```bash
docker compose logs app
docker compose logs ai
docker compose logs nginx
```

### 9. Verificar el sistema en el navegador

Abrir `http://TU_IP` (o el `APP_URL` que configuraste). Debe aparecer la pantalla de login.

Ingresar con `admin@rosalesasociados.bo` / `password`.

---

## Actualizar a nueva versión

```bash
bash ~/expedientes-deploy/update.sh
```

Con seeders (solo si cambiaron plantillas u otros datos iniciales):

```bash
bash ~/expedientes-deploy/update.sh --seed
```

El script `update.sh` hace automáticamente:
1. `git pull` en `expedientes-app` (rama `develop`) y `expedientes-ai` (rama `master`)
2. Rebuild de imágenes con caché
3. Restart de contenedores
4. Seeders (solo con `--seed`)

> **Nota:** `update.sh` no corre migraciones automáticamente. Si el deploy incluye migraciones nuevas, correrlas manualmente después del update:
> ```bash
> docker compose exec app php artisan migrate --force
> ```

---

## Servicios Docker

| Contenedor | Puerto externo | Descripción |
|---|---|---|
| `expedientes_app` | — | Laravel PHP-FPM |
| `expedientes_nginx` | `APP_PORT:80` | Proxy reverso + assets estáticos |
| `expedientes_ai` | — | FastAPI — NLP, RAG, embeddings |
| `expedientes_queue` | — | Queue worker (procesa documentos subidos) |
| `expedientes_postgres` | — | PostgreSQL 16 + pgvector |
| `expedientes_redis` | — | Caché y colas |

### Volúmenes persistentes

| Volumen | Contenido | Importancia |
|---|---|---|
| `postgres_data` | Base de datos completa | CRÍTICO — no eliminar |
| `storage_data` | Archivos PDF/DOCX subidos por usuarios | CRÍTICO — no eliminar |
| `public_data` | Assets compilados de Laravel (CSS/JS) | Regenerable |
| `huggingface_cache` | Modelo multilingual-e5-large (~1.2 GB) | Regenerable (pero tarda) |

---

## Comandos útiles

```bash
# Ver estado de todos los contenedores
docker compose ps

# Ver logs en tiempo real
docker compose logs -f
docker compose logs -f ai       # solo FastAPI
docker compose logs -f app      # solo Laravel

# Entrar a un contenedor
docker compose exec app bash
docker compose exec ai bash

# Correr migraciones
docker compose exec app php artisan migrate --force

# Correr seeders
docker compose exec app php artisan db:seed --force

# Correr solo el seeder de plantillas RAG
docker compose exec app php artisan db:seed --class=PlantillasSeeder --force

# Limpiar caché de Laravel
docker compose exec app php artisan config:clear
docker compose exec app php artisan cache:clear

# Reiniciar un servicio sin rebuild
docker compose restart ai
docker compose restart app

# Reconstruir solo el servicio IA (cuando cambia requirements.txt)
docker compose build ai && docker compose up -d ai
```

---

## Desarrollo local

Para desarrollo usar `docker-compose.dev.yml` (solo infraestructura — Laravel y Vite corren local):

```bash
# Solo base de datos y Redis
docker compose -f docker-compose.dev.yml up -d

# Con servicio IA (FastAPI)
docker compose -f docker-compose.dev.yml --profile ai up -d

# Rebuild del servicio IA (solo cuando cambia requirements.txt)
docker compose -f docker-compose.dev.yml build ai
docker compose -f docker-compose.dev.yml --profile ai up -d --force-recreate ai
```

Laravel y Vite en local:

```bash
cd expedientes-app
php artisan serve        # http://localhost:8000
npm run dev              # HMR en http://localhost:5173
php artisan queue:work   # (solo para pruebas de extracción de documentos)
```

El código Python de FastAPI se monta como volumen en dev — uvicorn recarga cambios automáticamente sin rebuild.

---

## Servidor GCP actual

- **IP:** `34.27.64.244`
- **Usuario:** `tecnoweb`
- **Acceso:** `ssh -i ~/.ssh/gcp_key tecnoweb@34.27.64.244`
- **Directorio:** `~/expedientes-deploy`
