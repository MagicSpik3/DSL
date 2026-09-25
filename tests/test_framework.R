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
diagram <- mermaid_state_machine(compiled)
stopifnot(grepl("flowchart TD", diagram, fixed = TRUE))
stopifnot(grepl("Does your business produce goods or services", diagram, fixed = TRUE))
temp_structured <- tempfile()
temp_state_machine <- tempfile()
write_parsed_survey(parsed, temp_structured, "test_survey")
write_state_machine(compiled, temp_state_machine, "test_survey")
stopifnot(file.exists(file.path(temp_structured, "test_survey.rds")))
stopifnot(file.exists(file.path(temp_structured, "test_survey_questions.tsv")))
stopifnot(file.exists(file.path(temp_state_machine, "test_survey.mmd")))
stopifnot(file.exists(file.path(temp_state_machine, "test_survey_audit.txt")))

child_demo <- survey(
  "child_demo",
  variables = list(
    survey_variable("NCHILD", "number", "How many children do you have?"),
    survey_variable("NAME1", "text", "What is your first child's name?")
  ),
  states = list(
    survey_state("start", transitions = list(
      survey_transition("NCHILD_QUESTION")
    )),
    survey_state("NCHILD_QUESTION", question = "NCHILD", transitions = list(
      survey_transition("has_children", when = "NCHILD > 0"),
      survey_transition("end", when = "NCHILD == 0")
    )),
    survey_state("has_children", question = "NAME1", transitions = list(
      survey_transition("end")
    )),
    survey_state("end", terminal = TRUE)
  ),
  start = "start"
)

bad_row <- data.frame(
  NCHILD = 0,
  CHILDNAME1 = "Alice",
  stringsAsFactors = FALSE
)
issues <- audit_survey_responses(child_demo, bad_row)
stopifnot(length(issues) == 1L)
stopifnot(any(grepl("no children|NCHILD|child", issues[[1L]]$message, ignore.case = TRUE)))

household_rows <- data.frame(
  OSGRIDREF = c("4291970560570", "4291970560570", "4291970560571", "4291970560571"),
  AREA = c("1803", "1803", "1803", "1803"),
  ADDRESS = c("4", "4", "5", "5"),
  NCHILD = c(0, 0, 1, 0),
  NAME1 = c("Alice", "Bob", "Charlie", "Dana"),
  stringsAsFactors = FALSE
)
key <- survey_household_key(household_rows)
stopifnot(identical(key, c("4291970560570|1803|4", "4291970560570|1803|4", "4291970560571|1803|5", "4291970560571|1803|5")))
report <- survey_response_issue_matrix(child_demo, household_rows)
stopifnot(identical(report$household_key, key))
stopifnot(identical(report$household_member_index, c(1L, 2L, 1L, 2L)))

no_child_but_spouse_name <- survey_row_routing_issues(child_demo, list(
  NCHILD = 0,
  NAME2 = "JEAN OLIVER"
))
stopifnot(!length(no_child_but_spouse_name))

simplified_household <- data.frame(
  OSGRIDREF = c("1100000001", "1100000001", "1100000001", "1100000001", "1100000001"),
  AREA = c("01", "01", "01", "01", "01"),
  ADDRESS = c("100", "100", "100", "100", "100"),
  Person = 1:5,
  PNAM = c("Adult A", "Adult B", "Adult C", "Teen A", "Child A"),
  AGE = c(48L, 47L, 29L, 16L, 14L),
  RELTOHRP = c("respondent", "partner", "adult child", "dependent child", "dependent child"),
  NCHILD = c(2L, 2L, 1L, 0L, 0L),
  NDEPC = c(1L, 1L, 0L, 0L, 0L),
  NNDEPC = c(0L, 0L, 1L, 0L, 0L),
  stringsAsFactors = FALSE
)
key <- survey_household_key(simplified_household)
stopifnot(identical(key, rep("1100000001|01|100", 5L)))
stopifnot(identical(unique(key), "1100000001|01|100"))
stopifnot(identical(length(unique(simplified_household$PNAM)), 5L))

cat("survey DSL smoke tests passed\n")