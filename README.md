# FitHuman <img width="1024" height="1024" alt="Untitled design" src="https://github.com/user-attachments/assets/f3a71ce9-5080-4251-bdb0-a88fef4bf2aa" />


FitHuman is an iOS fitness app that helps users build and follow a monthly workout plan, track daily hydration, monitor calories burned, and keep workout progress synced across sessions. The app is built with SwiftUI and uses a FastAPI backend for authentication, user profiles, workout plans, workout history, streaks, and water tracking.

## Highlights

- Email/password account creation and login
- Gemini-generated monthly workout plans based on weight, height, and fitness goal
- Daily workout view with circuit progress, rest timers, streak tracking, and completion state
- Calories burned summary with average calories, total calories, completed workout count, and history
- Water tracker with daily goal progress, quick add, custom intake entry, 7-day history, and average intake
- Profile tab for account details, body stats, plan status, wake-up time, plan changes, and logout
- FastAPI backend with MongoDB persistence and JWT authentication

## Screenshots

<p align="center">
  <strong>Workout</strong>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <strong>Water</strong>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <strong>Calories Burned</strong>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <strong>Profile</strong>
</p>

<p align="center">
  <img width="180" alt="Workout tab screenshot" src="https://github.com/user-attachments/assets/9377c602-92f3-466c-8d44-0bc9b6f511f5" />
  <img width="180" height = "364" alt="Water tab screenshot" src="https://github.com/user-attachments/assets/cc0ee7ca-5668-4bb2-88b6-5f789bade882" />
  <img width="180" height = "364" alt="Calories Burned tab screenshot" src="https://github.com/user-attachments/assets/92f03d8b-f1b1-4f14-9b73-6dce3d3ac720" />
  <img width="180" height = "364" alt="Profile tab screenshot" src="https://github.com/user-attachments/assets/d70c7fe0-b90d-47ed-8e1a-918f12ed6bda" />
</p>

## Tech Stack

### iOS App

- Swift
- SwiftUI
- iOS 17+
- Xcode project: `FitHuman.xcodeproj`

### Backend

- Python 3.11+
- FastAPI
- MongoDB / MongoDB Atlas
- JWT authentication
- Google Gemini API
- uv for dependency management

## Project Structure

```text
FitHuman/
├── FitHuman/                 # SwiftUI iOS app
│   ├── App/                  # App entry point
│   ├── Models/               # Swift data models
│   ├── Services/             # API client, app config, token storage
│   ├── ViewModels/           # App state and API orchestration
│   └── Views/                # Auth, tabs, workout, water, profile screens
├── backend/                  # FastAPI backend
│   ├── app/
│   │   ├── api/              # API routes
│   │   ├── core/             # Config and security
│   │   ├── db/               # MongoDB connection
│   │   └── services/         # Gemini integration
│   └── tests/                # Backend tests
├── DEPLOYMENT.md             # Production deployment notes
└── README.md
```

## Prerequisites

- Xcode 15 or newer
- iOS 17 simulator or device
- Python 3.11+
- uv
- MongoDB connection string
- Gemini API key

Install `uv` if needed:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Backend Setup

Create a backend environment file:

```bash
cd backend
touch .env
```

Add the required values:

```env
MONGODB_URI=mongodb+srv://your-user:your-password@your-cluster.mongodb.net/
MONGODB_DB_NAME=fithuman
JWT_SECRET=replace-with-a-long-random-secret
JWT_ACCESS_TOKEN_MINUTES=10080
GEMINI_API_KEY=your-gemini-api-key
GEMINI_MODEL=gemini-2.5-flash
CORS_ORIGINS=[]
```

Install dependencies and start the API:

```bash
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

## iOS Setup

1. Open `FitHuman.xcodeproj` in Xcode.
2. Select the `FitHuman` scheme.
3. Choose an iOS simulator or connected device.
4. Confirm `FITHUMAN_API_BASE_URL` points to your backend API URL.
5. Build and run.

The API base URL should include `/api/v1/`, for example:

```text
https://your-backend-host.example.com/api/v1/
```

For local simulator testing, use:

```text
http://127.0.0.1:8000/api/v1/
```

## Main Tabs

### Workout

The Workout tab shows the current daily plan, monthly plan status, set progress, exercise list, workout start/resume controls, rest timers, streaks, and completion feedback.

### Water

The Water tab tracks daily water intake, shows progress toward the daily goal, displays the past 7 days, supports quick 250 mL logging, and allows custom intake amounts.

### Calories Burned

The Calories Burned tab summarizes completed workout calories with average calories, total calories, workout count, and a session history list.

### Profile

The Profile tab shows account details, body stats, monthly plan status, wake-up time for reminders, plan update controls, and logout.

## Backend API

The backend exposes endpoints for auth, users, workout plans, workout progress, workout completion, calories, and water tracking.

Key routes include:

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/users/me`
- `PATCH /api/v1/users/me/profile`
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

## Running Tests

From the backend directory:

```bash
uv run pytest
```

## Deployment

FitHuman has two deployable parts:

- Backend: deploy the FastAPI app from `backend/` to a container host such as Render, Railway, Fly.io, Google Cloud Run, or AWS App Runner.
- iOS app: configure a production HTTPS `FITHUMAN_API_BASE_URL`, then distribute with TestFlight or the App Store.

See `DEPLOYMENT.md` for production environment variables, Docker build notes, health checks, and iOS release configuration.

## Security Notes

- Do not commit `.env` files.
- Keep `JWT_SECRET`, `MONGODB_URI`, and `GEMINI_API_KEY` server-side only.
- Use an HTTPS backend URL for release builds.
- Rotate secrets before production release if they were ever shared or committed.

## Roadmap Ideas

- Progress charts for workout consistency and hydration trends
- Editable water goals from the iOS UI
- Exercise substitutions
- Voice assistance for exercise
- Gif of the exercise for the user
- Implemet Google and Apple Auth login

