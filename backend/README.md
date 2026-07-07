# FitHuman Backend

FastAPI backend for production app data:

- Email/password login with JWT access tokens.
- User fitness profile from onboarding.
- Gemini-generated monthly workout plans stored per user.
- Current workout progress, completed sessions, and streaks.
- Daily water intake and water goal tracking.

## API Surface

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/users/me`
- `PATCH /api/v1/users/me/profile`
- `POST /api/v1/onboarding/complete`
- `GET /api/v1/workout-plans/current`
- `POST /api/v1/workout-plans/generate`
- `POST /api/v1/workout-plans/current/continue`
- `GET /api/v1/workouts/progress`
- `PUT /api/v1/workouts/progress`
- `POST /api/v1/workouts/complete`
- `GET /api/v1/water/today`
- `GET /api/v1/water/history`
- `POST /api/v1/water/intake`
- `PATCH /api/v1/water/goal`

## Local Run

```bash
cd backend
cp .env.example .env
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

Keep `.env` out of git. Store MongoDB Atlas and Gemini secrets only on the backend.
