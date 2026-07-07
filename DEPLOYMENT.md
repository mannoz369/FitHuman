# FitHuman Deployment

FitHuman has two deployable parts:

1. The FastAPI backend in `backend/`.
2. The iOS app in `FitHuman/`, distributed through TestFlight or the App Store.

The iOS app must call a public HTTPS backend URL. A local URL such as `127.0.0.1` only works on the simulator and will not work for other phones.

## Backend

Use any container host that can deploy a Dockerfile from the `backend/` directory. Render, Railway, Fly.io, Google Cloud Run, AWS App Runner, and similar hosts all fit this model.

Build locally:

```bash
docker build -t fithuman-api ./backend
```

Run locally from the built image:

```bash
docker run --env-file backend/.env -p 8000:8000 fithuman-api
```

Required production environment variables:

```text
MONGODB_URI=mongodb+srv://...
MONGODB_DB_NAME=fithuman
JWT_SECRET=<long-random-secret>
JWT_ACCESS_TOKEN_MINUTES=10080
GEMINI_API_KEY=<server-side-gemini-key>
GEMINI_MODEL=gemini-2.5-flash
CORS_ORIGINS=[]
```

After deployment, verify:

```bash
curl https://your-backend-host.example.com/health
```

Expected response:

```json
{"status":"ok"}
```

The API base URL used by the iOS app is the deployed host plus `/api/v1/`, for example:

```text
https://your-backend-host.example.com/api/v1/
```

## iOS

The app reads `FITHUMAN_API_BASE_URL` from the generated Info.plist.

Debug builds default to:

```text
http://127.0.0.1:8000/api/v1/
```

Release builds must use the production HTTPS URL. In Xcode, open the FitHuman target build settings and replace the Release value for `FITHUMAN_API_BASE_URL` with your deployed backend URL:

```text
https://your-backend-host.example.com/api/v1/
```

Then archive the app and distribute it through TestFlight first. Once TestFlight login, onboarding, workout generation, workout progress, and water tracking work against the deployed backend, submit the same archive flow to the App Store.
