source(file.path("R", "survey_dsl.R"))
source(file.path("R", "survey_parser.R"))
source(file.path("R", "survey_yaml.R"))

parsed <- parse_yaml_survey(file.path("unprocessed", "WAS_Round9_Paper_Questionnaire.yaml"))
stopifnot(length(parsed$questions) == 892L)
stopifnot(any(vapply(parsed$questions, function(question) length(question$route_conditions) > 0L, logical(1))))

compiled <- compile_yaml_survey(parsed, "was_round9_test")
audit <- audit_survey(compiled)
stopifnot(audit$ok, length(compiled$states) == 894L)
stopifnot(all(vapply(compiled$states, function(state) nzchar(state$id), logical(1))))
cat("WAS Round 9 YAML integration test passed\n")