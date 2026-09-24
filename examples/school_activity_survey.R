source(file.path("R", "survey_dsl.R"))

school_activity_survey <- survey(
  id = "school_activity_v1",
  variables = list(
    survey_variable("has_activities", "boolean", "Do you regularly do any after-school activities?"),
    survey_variable("has_formal_club", "boolean", "Are any activities with a formal club?"),
    survey_variable("club_name", "text", "What is the club called?"),
    survey_variable("is_sport", "choice", "What kind of club is it?", choices = c("physical_sport", "mind_sport", "esport", "other")),
    survey_variable("competes", "boolean", "Do you compete?"),
    survey_variable("club_time_weekly_hours", "number", "How many hours per week does the club take?"),
    survey_variable("phone_time_daily_hours", "number", "How many hours per day do you spend using phone apps?")
  ),
  states = list(
    survey_state("start", transitions = list(survey_transition("activities"))),
    survey_state("activities", question = "has_activities", transitions = list(
      survey_transition("formal_club", "has_activities == TRUE"),
      survey_transition("phone_time")
    )),
    survey_state("formal_club", question = "has_formal_club", transitions = list(
      survey_transition("club_name", "has_formal_club == TRUE"),
      survey_transition("phone_time")
    )),
    survey_state("club_name", question = "club_name", transitions = list(survey_transition("club_type"))),
    survey_state("club_type", question = "is_sport", transitions = list(survey_transition("competition"))),
    survey_state("competition", question = "competes", transitions = list(survey_transition("club_time"))),
    survey_state("club_time", question = "club_time_weekly_hours", transitions = list(survey_transition("phone_time"))),
    survey_state("phone_time", question = "phone_time_daily_hours", transitions = list(survey_transition("end"))),
    survey_state("end", terminal = TRUE)
  ),
  start = "start",
  rules = list(survey_rule(
    "high_phone_low_activity", "!has_activities && phone_time_daily_hours >= 4",
    "High phone use may have been interpreted as an activity.", "warning"
  ))
)

print(audit_survey(school_activity_survey))
print(run_survey(school_activity_survey, list(
  has_activities = FALSE,
  phone_time_daily_hours = 5
)))