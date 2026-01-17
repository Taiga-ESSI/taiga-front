# Google SSO Frontend Integration

## Overview
- Adds a Google Identity Services button to the login and invitation acceptance flows (AngularJS views).
- The script `https://accounts.google.com/gsi/client` is loaded once during bootstrap; rendering and login are managed with the official `google.accounts.id` API.
- The UI is available only when `googleAuth.enabled` is `true` and a `clientId` is provided in `conf.json`.

## Cambios aplicados (taiga-front)
- `taiga-front/conf/conf.json`, `conf/conf.example.json` y `dist/conf.json`: incorporan el bloque `googleAuth` con flags `enabled`, `clientId` y `allowedDomains` que el frontend consume en tiempo de arranque.
- `taiga-front/app-loader/app-loader.coffee`: carga asincronamente el script de Google Identity Services cuando la configuracion esta activa y expone una promesa reutilizable.
- `taiga-front/app/coffee/modules/auth.coffee`: define `attachGoogleLogin`, integra la llamada `auth.login` reutilizando el manejador existente y comparte la logica entre login normal e invitaciones.
- `taiga-front/app/partials/includes/modules/login-form.jade` y `.../invitation-login-form.jade`: incluyen el nuevo parcial `google-login` dentro del bloque de proveedores alternativos.
- `taiga-front/app/partials/includes/modules/google-login.jade`: parcial dedicado al boton, estados de carga e indicacion de dominios permitidos.
- `taiga-front/app/styles/modules/auth/login-form.scss` y `app/styles/layout/invitation.scss`: estilos especificos para el contenedor `.google-auth` y feedback visual durante la carga.
- `taiga-front/app/locales/taiga/locale-en.json` y `taiga-front/app/locales/taiga/locale-es.json`: agregan las claves `LOGIN_FORM.ERROR_GOOGLE_INIT`, `LOGIN_FORM.GOOGLE_LOADING`, `LOGIN_FORM.GOOGLE_DOMAIN_HINT` para mostrar estados y restricciones del boton.
- `taiga-front/app/partials` y `app/coffee/modules/auth.coffee`: Pol Alcoverro comentó los formularios y controladores del login/registro clásicos (login normal, register y flujos de invitación), manteniendo el código original comentado y mostrando únicamente el acceso mediante Google.

## Configuration (`taiga-front/conf/conf.json`)
```json
{
  "googleAuth": {
    "enabled": true,
    "clientId": "<your Google OAuth client ID>",
    "allowedDomains": [
      "upc.edu",
      "estudiantat.upc.edu"
    ]
  }
}
```
- `enabled`: toggles the button; the backend must also be configured.
- `clientId`: must match one of the IDs listed in `GOOGLE_AUTH_CLIENT_IDS` on the backend.
- `allowedDomains`: optional hint for users; displayed under the button and kept in sync with backend policy.

After updating `conf.json`, rebuild the frontend bundle if you deploy static assets (`npm run build` or equivalent). When developing with `npm run start`, remember that the file actually served is `dist/conf.json`; keep that copy in sync with the source config (the watcher does not overwrite it automatically).

## UX Behaviour
- The Google button appears beneath the classic credential form inside the existing “alternative login” wrapper.
- When an ID token is requested, the UI shows a lightweight loading state and disables the button to prevent duplicate submissions.
- Invitation pages include the invitation token automatically in the Google login payload so project access is granted on first sign-in.
- If the Google script cannot be loaded or the client configuration is invalid, users receive a translated toast notification and the button disappears.

## Request Flow
- On success, the callback posts `{type: 'google', credential, client_id}` to `/api/v1/auth`. The standard auth success handler (token storage, redirect logic, analytics) is re-used, so no extra wiring is needed.
- For invitation acceptance it also adds `invitation_token` to the payload.

## Styling and Extensibility
- New CSS hooks: `.google-auth`, `.google-auth__button`, `.google-auth__loading`, `.google-auth__hint` for theming the container; the stock styles live in `app/styles/modules/auth/login-form.scss` and `app/styles/layout/invitation.scss`.
- The domain hint text is populated dynamically from `googleAuth.allowedDomains` (prefixed with `@` automatically). Update the config list to reflect policy changes; no code changes required.

## Legal & Stability Notes
- Google Identity Services is the recommended (and actively maintained) replacement for the deprecated Google Platform Library; using the official button ensures long-term stability and compliance with brand/UX requirements.
- The script is loaded from Google at runtime; make sure outgoing HTTPS requests to `accounts.google.com` are permitted in production.
- No user information other than the ID token leaves the browser; credential validation occurs entirely on the backend.

## Troubleshooting
- If the button never appears, verify both the frontend config and the backend env vars (`googleAuth.enabled` must be in sync with `GOOGLE_AUTH_ENABLED`).
- A “Google sign-in is temporarily unavailable” toast indicates the GIS script failed to load (network/cookie blockers). Users can still fall back to password login.
- Backend responses with domain or configuration errors are surfaced via toast notifications; check the browser console and server logs for the detailed reason.
- During development, ensure `http://localhost:9001/conf.json` returns the expected `googleAuth` block; if not, update `dist/conf.json` and restart `npm run start`.

## Recommended Follow-up
- Add the Google OAuth client origin (`https://<your-domain>`) to the allowed JavaScript origins in Google Cloud Console.
- Consider localising the new translation keys (`LOGIN_FORM.ERROR_GOOGLE_INIT`, `LOGIN_FORM.GOOGLE_LOADING`, `LOGIN_FORM.GOOGLE_DOMAIN_HINT`) for non-English/Spanish locales as needed.
