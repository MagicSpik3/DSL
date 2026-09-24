source(file.path("R", "survey_dsl.R"))
source(file.path("R", "survey_parser.R"))

parsed <- parse_survey_text(file.path("unprocessed", "Survey information.txt"))
compiled <- compile_parsed_survey(parsed, "business_accounts_v1")

write_parsed_survey(parsed, "structured", "business_accounts_v1")
audit <- write_state_machine(compiled, "state_machine", "business_accounts_v1")
cat(sprintf("Parsed %d sections and %d questions.\n", length(parsed$sections), length(parsed$questions)))
cat(sprintf("State machine audit: %s\n", if (audit$ok) "passed" else "failed"))
cat("Wrote structured/ and state_machine/ artifacts.\n")