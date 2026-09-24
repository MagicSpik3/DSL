source(file.path("R", "survey_dsl.R"))
source(file.path("examples", "school_activity_survey.R"), local = TRUE)

audit <- audit_survey(school_activity_survey)
stopifnot(audit$ok, length(audit$reachable) == 9L, !length(audit$errors))

short_path <- run_survey(school_activity_survey, list(
  has_activities = FALSE,
  phone_time_daily_hours = 2
))
stopifnot(identical(short_path$status, "complete"))
stopifnot(identical(short_path$path, c("start", "activities", "phone_time", "end")))

long_path <- run_survey(school_activity_survey, list(
  has_activities = TRUE,
  has_formal_club = TRUE,
  club_name = "Chess Club",
  is_sport = "mind_sport",
  competes = TRUE,
  club_time_weekly_hours = 3,
  phone_time_daily_hours = 1
))
stopifnot(identical(long_path$status, "complete"))
stopifnot(length(long_path$path) == 9L)

issues <- check_response(school_activity_survey, list(
  has_activities = FALSE,
  phone_time_daily_hours = 5
))
stopifnot(length(issues) == 1L, identical(issues[[1L]]$severity, "warning"))
cat("survey DSL smoke tests passed\n")