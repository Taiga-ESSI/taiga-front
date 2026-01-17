# Taiga Frontend

[![Managed with Taiga.io](https://img.shields.io/badge/managed%20with-TAIGA.io-709f14.svg)](https://tree.taiga.io/project/taiga/ "Managed with Taiga.io")

> **Fork UPC**: Esta versión incluye integración con Google SSO y panel de métricas para Learning Dashboard.

## Tabla de Contenidos

- [Características Añadidas](#características-añadidas)
- [Requisitos](#requisitos)
- [Instalación para Desarrollo](#instalación-para-desarrollo)
- [Configuración](#configuración)
- [Google SSO Setup](#google-sso-setup)
- [Panel de Métricas](#panel-de-métricas)
- [Docker](#docker)
- [Tests](#tests)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Troubleshooting](#troubleshooting)

---

## Características Añadidas

Esta versión fork incluye las siguientes mejoras:

1. **Google SSO Authentication**: Botón de login con Google usando Google Identity Services
2. **Panel de Métricas**: Visualización de métricas de proyecto con Chart.js
3. **Integración Learning Dashboard**: Conexión con LD-Taiga backend

---

## Requisitos

- Node.js 14+ (recomendado usar [nvm](https://github.com/creationix/nvm))
- npm 6+
- Gulp 4+

---

## Instalación para Desarrollo

### 1. Clonar el repositorio

```bash
git clone <repository-url>
cd taiga-front
```

### 2. Instalar dependencias

```bash
npm install
```

### 3. Configurar la aplicación

```bash
cp conf/conf.example.json conf/conf.json
```

Edita `conf/conf.json` según tu entorno (ver sección [Configuración](#configuración)).

### 4. Ejecutar servidor de desarrollo

```bash
npm start
# o
npx gulp
```

La aplicación estará disponible en `http://localhost:9001`

> **Nota**: El servidor de desarrollo incluye livereload en el puerto 35729.

---

## Configuración

### Archivo `conf/conf.json`

Este es el archivo principal de configuración del frontend. Aquí está la referencia completa:

```json
{
    "api": "http://localhost:9000/api/v1/",
    "eventsUrl": "ws://localhost:9000/events",
    "baseHref": "/",
    "eventsMaxMissedHeartbeats": 5,
    "eventsHeartbeatIntervalTime": 60000,
    "eventsReconnectTryInterval": 10000,
    "debug": false,
    "debugInfo": false,
    "defaultLanguage": "en",
    "themes": ["taiga"],
    "defaultTheme": "taiga",
    "defaultLoginEnabled": true,
    "publicRegisterEnabled": true,
    "googleAuth": {
        "enabled": true,
        "clientId": "tu-client-id.apps.googleusercontent.com",
        "allowedDomains": ["upc.edu", "estudiantat.upc.edu"]
    },
    "feedbackEnabled": true,
    "supportUrl": "https://community.taiga.io/",
    "privacyPolicyUrl": null,
    "termsOfServiceUrl": null,
    "maxUploadFileSize": null,
    "contribPlugins": [],
    "tagManager": { "accountId": null },
    "tribeHost": null,
    "enableAsanaImporter": false,
    "enableGithubImporter": false,
    "enableJiraImporter": false,
    "enableTrelloImporter": false,
    "gravatar": false,
    "rtlLanguages": ["ar", "fa", "he"]
}
```

### Opciones de Configuración

| Opción | Tipo | Descripción | Valor por Defecto |
|--------|------|-------------|-------------------|
| `api` | string | URL de la API del backend | `http://localhost:8000/api/v1/` |
| `eventsUrl` | string | URL de WebSocket para eventos | `null` |
| `baseHref` | string | Base path de la aplicación | `/` |
| `debug` | boolean | Modo debug | `false` |
| `defaultLanguage` | string | Idioma por defecto | `en` |
| `defaultLoginEnabled` | boolean | Mostrar login tradicional | `true` |
| `publicRegisterEnabled` | boolean | Permitir registro público | `true` |

### Opciones de Google SSO (NUEVO)

| Opción | Tipo | Descripción | Requerido |
|--------|------|-------------|-----------|
| `googleAuth.enabled` | boolean | Habilitar botón de Google | Sí |
| `googleAuth.clientId` | string | Google OAuth Client ID | **Sí para SSO** |
| `googleAuth.allowedDomains` | array | Dominios permitidos | **Sí para SSO** |

### Opciones de Integraciones OAuth

| Opción | Tipo | Descripción |
|--------|------|-------------|
| `gitHubClientId` | string | Client ID de GitHub |
| `gitLabClientId` | string | Client ID de GitLab |
| `gitLabUrl` | string | URL de GitLab |

### Opciones de Importadores

| Opción | Tipo | Descripción |
|--------|------|-------------|
| `enableGithubImporter` | boolean | Importador de GitHub |
| `enableJiraImporter` | boolean | Importador de Jira |
| `enableTrelloImporter` | boolean | Importador de Trello |
| `enableAsanaImporter` | boolean | Importador de Asana |

---

## Google SSO Setup

### Requisitos Previos

1. Tener un **Google OAuth Client ID** (ver backend README para instrucciones)
2. El **Client ID debe ser el mismo** que en el backend
3. Los **dominios deben coincidir** con la configuración del backend

### Configuración

Edita `conf/conf.json`:

```json
{
    "googleAuth": {
        "enabled": true,
        "clientId": "286907234950-xxxxx.apps.googleusercontent.com",
        "allowedDomains": ["upc.edu", "estudiantat.upc.edu"]
    }
}
```

### Funcionamiento

1. El usuario hace clic en "Sign in with Google"
2. Se abre popup de Google Identity Services
3. Usuario selecciona cuenta Google (filtrada por dominios permitidos)
4. Frontend recibe ID token de Google
5. Frontend envía token al backend (`/api/v1/auth/google`)
6. Backend valida token y devuelve token de sesión de Taiga

### Archivos Relacionados

```
app/
├── modules/auth/
│   ├── login.controller.coffee    # Controlador con lógica Google SSO
│   └── login.service.coffee       # Servicio de autenticación
├── partials/auth/
│   └── login.html                 # Template con botón Google
└── styles/
    └── google-auth.scss           # Estilos del botón
```

### Notas Importantes

- **HTTPS obligatorio** en producción para Google OAuth
- El hint de dominios (`allowedDomains`) filtra visualmente en el popup
- La validación real de dominio la hace el backend
- Si `defaultLoginEnabled: false`, solo se mostrará Google SSO

---

## Panel de Métricas

### Descripción

El panel de métricas muestra estadísticas del proyecto:

- User Stories por usuario
- Tasks completadas
- Puntos de sprint
- Velocidad del equipo

### Dependencias

El panel usa las siguientes librerías (incluidas en el build):

```json
{
  "dependencies": {
    "chart.js": "^3.x",
    "chartjs-plugin-datalabels": "^2.x"
  }
}
```

### Archivos Relacionados

```
app/
├── modules/projects/
│   └── metrics/
│       ├── metrics.controller.coffee
│       ├── metrics.service.coffee
│       └── metrics.html
└── styles/
    └── metrics.scss
```

### Configuración Backend

El panel consume la API de métricas del backend:

```
GET /api/v1/metrics/current?prj=<project-slug>
GET /api/v1/metrics/categories?prj=<project-slug>
```

---

## Docker

### Desarrollo con Docker

```bash
# Usando Docker Compose desde taiga-docker
cd ../taiga-docker
docker compose up taiga-front
```

### Dockerfile de Desarrollo

El archivo `docker/Dockerfile.dev` está configurado para desarrollo:

```bash
docker build -t taiga-front-dev -f docker/Dockerfile.dev .
docker run -d \
  -p 9001:80 \
  -e TAIGA_URL=http://localhost:9000 \
  -e TAIGA_WEBSOCKETS_URL=ws://localhost:9000 \
  taiga-front-dev
```

### Variables de Entorno (Docker)

| Variable | Descripción |
|----------|-------------|
| `TAIGA_URL` | URL base del backend |
| `TAIGA_WEBSOCKETS_URL` | URL de WebSocket |
| `TAIGA_SUBPATH` | Subpath de la aplicación |
| `PUBLIC_REGISTER_ENABLED` | Habilitar registro público |
| `ENABLE_GITHUB_AUTH` | Habilitar GitHub OAuth |
| `ENABLE_GITLAB_AUTH` | Habilitar GitLab OAuth |
| `GITHUB_CLIENT_ID` | Client ID de GitHub |
| `GITLAB_CLIENT_ID` | Client ID de GitLab |
| `GITLAB_URL` | URL de GitLab |

### Template de Configuración

El archivo `docker/conf.json.template` se usa para generar la configuración en Docker. Actualmente **no incluye** Google Auth - ver sección [TODO Docker](#todo-docker).

---

## Tests

### Unit Tests

```bash
# Ejecutar tests unitarios
npm test

# O con Gulp
npx gulp
npm test
```

### E2E Tests

Requisitos:
- Protractor
- Mocha
- Backend running

```bash
# Instalar dependencias E2E
npm install -g protractor mocha

# Actualizar webdriver
webdriver-manager update

# Iniciar Selenium (requiere Java JDK)
webdriver-manager start

# En otra terminal, ejecutar tests
protractor conf.e2e.js --suite=auth     # Tests de autenticación
protractor conf.e2e.js --suite=full     # Tests completos
```

---

## Estructura del Proyecto

```
taiga-front/
├── app/                    # Código fuente principal
│   ├── coffee/            # CoffeeScript modules
│   ├── modules/           # Módulos de la aplicación
│   │   ├── auth/          # Autenticación (incluye Google SSO)
│   │   ├── projects/      # Proyectos y métricas
│   │   └── ...
│   ├── partials/          # Templates HTML
│   ├── styles/            # SCSS styles
│   └── index.jade         # Template principal
├── conf/                   # Configuración
│   ├── conf.json          # Tu configuración local
│   └── conf.example.json  # Ejemplo de configuración
├── docker/                 # Archivos Docker
│   ├── Dockerfile
│   ├── Dockerfile.dev
│   ├── conf.json.template
│   └── config_env_subst.sh
├── e2e/                    # Tests E2E
├── test/                   # Tests unitarios
├── gulpfile.js            # Configuración Gulp
├── package.json           # Dependencias npm
└── karma.conf.js          # Configuración Karma
```

---

## Troubleshooting

### El botón de Google no aparece

1. Verifica que `googleAuth.enabled: true` en `conf/conf.json`
2. Verifica que `googleAuth.clientId` esté configurado
3. Revisa la consola del navegador por errores de carga del script de Google

### Error "popup_closed_by_user"

El usuario cerró el popup de Google. No es un error real.

### Error "idpiframe_initialization_failed"

- Verifica que el dominio esté en **Authorized JavaScript origins** en Google Cloud Console
- En desarrollo, asegúrate de usar `http://localhost:9001` (no `127.0.0.1`)

### Error CORS al conectar con backend

- Verifica la URL de la API en `conf/conf.json`
- Asegúrate de que el backend tenga configurado CORS correctamente

### Los estilos no se cargan

```bash
# Recompilar estilos
npx gulp styles
```

### Livereload no funciona

Verifica que el puerto 35729 esté disponible.

---

## TODO Docker

Pendiente de implementar en `docker/conf.json.template`:

```json
"googleAuth": {
    "enabled": ${GOOGLE_AUTH_ENABLED:-false},
    "clientId": "${GOOGLE_AUTH_CLIENT_ID}",
    "allowedDomains": ${GOOGLE_AUTH_ALLOWED_DOMAINS:-[]}
}
```

Y en `docker/config_env_subst.sh`:

```bash
# Google Auth
if [[ -z "${GOOGLE_AUTH_ENABLED}" ]]; then
    export GOOGLE_AUTH_ENABLED="false"
fi
```

---

## Community

If you **need help to setup Taiga**, want to **talk about some cool enhancement** or you have **some questions**, please go to [Taiga community](https://community.taiga.io/).

## Contribute to Taiga

There are many different ways to contribute to Taiga's platform, from patches, to documentation and UI enhancements, just find the one that best fits with your skills. Check out our detailed [contribution guide](https://community.taiga.io/t/how-can-i-contribute/159)

## Code of Conduct

Help us keep the Taiga Community open and inclusive. Please read and follow our [Code of Conduct](https://github.com/taigaio/code-of-conduct/blob/main/CODE_OF_CONDUCT.md).

## License

Every code patch accepted in this repository is licensed under [AGPL 3.0](LICENSE). You must be careful to not include any code that can not be licensed under this license.

Please read carefully [our license](LICENSE) and ask us if you have any questions as well as the [Contribution policy](https://github.com/taigaio/taiga-front/blob/main/CONTRIBUTING.md).

---

*Modificado por Pol Alcoverro* ❤️
