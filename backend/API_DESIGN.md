# FitHuman API Design

The iOS app currently stores production-critical data in `UserDefaults` and calls Gemini directly from the device. These functions should move behind authenticated backend APIs.

## Auth

- Register user: `POST /api/v1/auth/register`
- Login user: `POST /api/v1/auth/login`
- Current user: `GET /api/v1/users/me`

The Swift app should store the returned bearer token in Keychain, not `UserDefaults`.

## Onboarding and Profile

- Save profile: `PATCH /api/v1/users/me/profile`
- Complete onboarding and generate first monthly plan: `POST /api/v1/onboarding/complete`
- Change plan from Profile: `POST /api/v1/workout-plans/generate`

Payload:

```json
{
  "weight_kg": 75,
  "height_cm": 178,
  "goal": "Lose Weight + Gain Muscle"
}
```

## Workout Plans

- Current monthly plan: `GET /api/v1/workout-plans/current`
- Continue expired plan for another 30 days: `POST /api/v1/workout-plans/current/continue`
- Generate replacement plan: `POST /api/v1/workout-plans/generate`

The backend stores a generated 7-day template and repeats it for 30 days by `starts_at` and `ends_at`.

## Workout Execution

- Save in-progress exercise index: `PUT /api/v1/workouts/progress`
- Restore in-progress exercise index: `GET /api/v1/workouts/progress`
- Complete today's workout and update streak: `POST /api/v1/workouts/complete`

This replaces local-only `currentExerciseIndex`, `isWorkoutComplete`, and `currentStreak` persistence.

## Water Tracking

- Get today's water log: `GET /api/v1/water/today`
- Add intake: `POST /api/v1/water/intake`
- Change daily goal: `PATCH /api/v1/water/goal`

This replaces local-only water intake and midnight reset state.
