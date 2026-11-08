# CMS de artículos con Strapi y Google Cloud

Este proyecto construye un CMS headless para crear y publicar artículos sin depender de WordPress. Strapi ofrece un panel para gestionar el contenido y una API REST para que otros sitios o aplicaciones lo consulten. La infraestructura de la versión en Google Cloud se describe con Terraform.

## Qué permite hacer

- Crear, editar, guardar como borrador y publicar artículos desde el panel de administración.
- Organizar artículos con título, slug, resumen, contenido enriquecido y categoría.
- Consultar los artículos mediante una API REST para usarlos desde una web, una aplicación móvil u otro frontend.
- Separar el trabajo editorial del desarrollo de la interfaz: los editores cambian el contenido desde Strapi sin modificar el código del frontend.
- Guardar el contenido en PostgreSQL y los archivos cargados en Google Cloud Storage en el despliegue de Google Cloud.

El tipo de contenido **Artículo** está definido en `src/api/articulo/content-types/articulo/schema.json`. Strapi registra sus rutas, controlador y servicio en `src/api/articulo/`.

## Ejecutar en local

Se requiere Node.js 22 o una versión compatible con `package.json`.

```bash
npm ci
npm run develop
```

Abre <http://localhost:1337/admin> y crea la cuenta administradora. La ejecución local usa SQLite y guarda los datos en `.tmp/`. Para consultar artículos sin autenticarte, habilita `find` y `findOne` para el tipo Artículo en **Settings → Users & Permissions Plugin → Roles → Public**. Después consulta `/api/articulos`.

## Arquitectura en Google Cloud

La aplicación está desplegada en Cloud Run en un entorno temporal de demostración. Su URL se comparte directamente con las personas que vayan a probarla y puede dejar de estar disponible cuando se eliminen los recursos.

```text
Editor → HTTPS → Cloud Run (Strapi)
                       ├── Cloud SQL (PostgreSQL)
                       ├── Cloud Storage (archivos)
                       └── Secret Manager (claves)

Cloud Build crea la imagen → Artifact Registry la almacena
Terraform declara y aprovisiona los recursos de Google Cloud
```

Cloud Run ejecuta el contenedor; Cloud SQL conserva los artículos; Cloud Storage conserva las imágenes y otros archivos; Secret Manager guarda las claves de aplicación. Una cuenta de servicio permite que Strapi acceda a los recursos requeridos.

## Infraestructura como código

Los archivos Terraform están en `terraform/`:

- `versions.tf`: proveedor de Google y versiones requeridas.
- `variables.tf`: región, proyecto, imagen, base de datos y secretos.
- `main.tf`: servicios de Google Cloud y sus permisos.
- `outputs.tf`: URL del servicio y nombre del bucket.

La variable `enable_gcp` está desactivada por defecto, por lo que el plan inicial no crea recursos facturables. Para revisar la configuración:

```bash
cd terraform
terraform init
terraform validate
terraform plan
```

Para un despliegue propio, crea un archivo local de variables a partir de `terraform.tfvars.example`. Define un proyecto de Google Cloud con facturación habilitada, configura los secretos y construye la imagen con `gcloud builds submit`. Después revisa el plan antes de ejecutar `terraform apply`. Los archivos `.tfvars` reales y el estado de Terraform no se deben subir al repositorio: el estado puede contener valores sensibles.

La infraestructura de la demostración se puede eliminar con `terraform destroy` usando el mismo archivo local de variables. El bucket evita borrar archivos por accidente (`force_destroy = false`); si contiene archivos, hay que retirarlos o respaldarlos antes de destruirlo.

## Fuentes

- [Strapi 5: inicio rápido](https://docs.strapi.io/cms/quick-start)
- [Strapi 5: bases de datos](https://docs.strapi.io/cms/configurations/database)
- [Google Cloud: Cloud Run](https://docs.cloud.google.com/run/docs/overview/what-is-cloud-run)
- [Google Cloud: conectar Cloud Run con PostgreSQL](https://docs.cloud.google.com/sql/docs/postgres/connect-run)
