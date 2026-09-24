source(file.path("R", "survey_dsl.R"))
source(file.path("R", "survey_parser.R"))

parsed <- parse_survey_text("Survey information.txt")
compiled <- compile_parsed_survey(parsed, "business_accounts_v1")

cat(sprintf("Parsed %d sections and %d questions.\n", length(parsed$sections), length(parsed$questions)))
print(data.frame(
  id = vapply(parsed$questions, `[[`, character(1), "id"),
  type = vapply(parsed$questions, `[[`, character(1), "type"),
  section = vapply(parsed$questions, `[[`, character(1), "section"),
  stringsAsFactors = FALSE
))
print(audit_survey(compiled))