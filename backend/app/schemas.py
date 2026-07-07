from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, model_validator

FitnessGoal = Literal["Lose Weight", "Gain Muscle", "Lose Weight + Gain Muscle"]
ExerciseCategory = Literal["home_workout", "cardio"]
ExecutionStyle = Literal["counted", "timed", "manual_timed"]


class UserProfile(BaseModel):
    weight_kg: float = Field(gt=0)
    height_cm: float = Field(gt=0)
    goal: FitnessGoal


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str | None = Field(default=None, max_length=120)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class Exercise(BaseModel):
    name: str
    category: ExerciseCategory
    execution_style: ExecutionStyle
    target_reps: int = Field(ge=0)
    target_seconds: int = Field(ge=0)
    rest_seconds: int = Field(ge=0)

    @model_validator(mode="after")
    def normalize_duration_units(self):
        if (
            self.category == "cardio"
            and self.execution_style == "manual_timed"
            and 1 <= self.target_seconds <= 90
        ):
            self.target_seconds *= 60

        return self


class DailyPlan(BaseModel):
    day_name: str
    is_rest_day: bool
    set_count: int = Field(ge=0, le=6)
    exercises: list[Exercise]


class WeeklyPlanResponse(BaseModel):
    weekly_plan: list[DailyPlan]


class UserOut(BaseModel):
    id: str
    email: EmailStr
    name: str | None = None
    profile: UserProfile | None = None
    current_streak: int = 0
    created_at: datetime


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class WorkoutPlanOut(BaseModel):
    id: str
    weekly_plan: list[DailyPlan]
    profile_snapshot: UserProfile
    starts_at: datetime
    ends_at: datetime
    is_active: bool
    days_remaining: int
    today_plan: DailyPlan | None = None


class WorkoutProgressIn(BaseModel):
    plan_id: str
    current_exercise_index: int = Field(ge=0)
    is_workout_complete: bool = False


class WorkoutProgressOut(WorkoutProgressIn):
    updated_at: datetime


class CurrentWorkoutPlanResponse(BaseModel):
    plan: WorkoutPlanOut | None
    needs_new_plan: bool
    today_progress: WorkoutProgressOut | None = None
    today_is_workout_complete: bool = False
    current_streak: int = 0


class CompleteWorkoutRequest(BaseModel):
    plan_id: str | None = None
    day_name: str | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    set_count: int | None = Field(default=None, ge=0, le=6)
    exercises: list[Exercise] = Field(default_factory=list)
    completed_at: datetime | None = None


class CompleteWorkoutResponse(BaseModel):
    completed_on: str
    current_streak: int
    already_completed: bool
    duration_seconds: int | None = None
    calories_burned: int | None = None


class WorkoutSessionOut(BaseModel):
    id: str
    completed_on: str
    day_name: str | None = None
    duration_seconds: int | None = None
    calories_burned: int | None = None
    calorie_estimate_source: str | None = None
    set_count: int | None = None
    exercises: list[Exercise] = Field(default_factory=list)
    completed_at: datetime


class WorkoutCaloriesSummaryOut(BaseModel):
    sessions: list[WorkoutSessionOut]
    average_calories_burned: float
    total_calories_burned: int
    workout_count: int


class WaterLogOut(BaseModel):
    day: str
    current_intake_ml: float
    daily_goal_ml: float
    last_intake_at: datetime | None = None
    updated_at: datetime


class WaterHistoryDayOut(BaseModel):
    day: str
    current_intake_ml: float | None = None
    daily_goal_ml: float
    last_intake_at: datetime | None = None
    updated_at: datetime | None = None


class WaterHistoryOut(BaseModel):
    days: list[WaterHistoryDayOut]
    average_intake_ml: float
    total_intake_ml: float
    logged_day_count: int


class AddWaterRequest(BaseModel):
    amount_ml: float = Field(gt=0)


class UpdateWaterGoalRequest(BaseModel):
    daily_goal_ml: float = Field(gt=0)
