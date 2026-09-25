source(file.path("R", "survey_dsl.R"))
source(file.path("R", "survey_parser.R"))
source(file.path("R", "survey_yaml.R"))

result <- write_yaml_survey_outputs(
  file.path("unprocessed", "WAS_Round9_Paper_Questionnaire.yaml"),
  structured_dir = "structured",
  state_machine_dir = "state_machine",
  id = "was_round9"
)

cat(sprintf("Parsed %d YAML questions.\n", length(result$parsed$questions)))
cat(sprintf("Compiled %d states.\n", length(result$definition$states)))
cat(sprintf("Audit: %s (%d warnings).\n", if (result$audit$ok) "passed" else "failed", length(result$audit$warnings)))
cat("Wrote structured/was_round9* and state_machine/was_round9* artifacts.\n")