source(file.path("R", "survey_dsl.R"))
source(file.path("examples", "school_activity_survey.R"), local = TRUE)
source(file.path("R", "survey_parser.R"))

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

parsed <- parse_survey_text("Survey information.txt")
stopifnot(length(parsed$sections) == 8L, length(parsed$questions) == 15L)
stopifnot(any(vapply(parsed$questions, function(question) identical(question$type, "boolean"), logical(1))))
stopifnot(any(vapply(parsed$questions, function(question) identical(question$type, "number"), logical(1))))
conditional <- parsed$questions[[4L]]
stopifnot(identical(conditional$depends_on, parsed$questions[[3L]]$id))
compiled <- compile_parsed_survey(parsed, "business_accounts_v1")
compiled_audit <- audit_survey(compiled)
stopifnot(compiled_audit$ok, length(compiled_audit$reachable) == 17L)
yes_path <- run_survey(compiled, list(
  are_you_able_to_report_figures_for_the_period_01_january_2025_to_31_december_2025 = TRUE,
  for_the_reporting_period_what_was_your_business_s_total_turnover = 100,
  does_your_business_produce_goods_or_services_that_protect_the_environment = TRUE,
  of_total_turnover_approximately_what_percentage_related_to_the_production_of_environmental_goods_or_services = "75-100%"
))
stopifnot(identical(yes_path$path[[5L]], "of_total_turnover_approximately_what_percentage_related_to_the_production_of_environmental_goods_or_services"))
no_path <- run_survey(compiled, list(
  are_you_able_to_report_figures_for_the_period_01_january_2025_to_31_december_2025 = TRUE,
  for_the_reporting_period_what_was_your_business_s_total_turnover = 100,
  does_your_business_produce_goods_or_services_that_protect_the_environment = FALSE
))
stopifnot(!"of_total_turnover_approximately_what_percentage_related_to_the_production_of_environmental_goods_or_services" %in% no_path$path)
cat("survey DSL smoke tests passed\n")