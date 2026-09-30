# Local R runtime
Sys.which("R")
"C:\\MY_RST~1\\R-46~1.1\\bin\\x64\\R.exe"

# Use this exact runtime from the project root whenever running R or Rscript.
# PowerShell examples:
#   & "C:\MY_RST~1\R-46~1.1\bin\x64\Rscript.exe" --vanilla tests/test_framework.R
#   & "C:\MY_RST~1\R-46~1.1\bin\x64\R.exe" --vanilla -e "source('R/survey_dsl.R'); print('ok')"

# Repo conventions
# - Run commands from D:\git\DSL (the project root), not from a nested folder.
# - Prefer exact paths and --vanilla so the session is reproducible and ignores user profile state.
# - This repo is a lightweight R prototype; keep changes small and test with the smallest relevant script.
# - For validation, prefer the smoke tests in tests/test_framework.R and the example scripts under examples/.
# - When extending survey logic, preserve the existing DSL vocabulary: survey_variable(), survey_state(), survey_transition(), survey_rule(), audit_survey(), run_survey(), and check_response().
# - If a route is unsupported, keep the original source text in the audit/route outputs rather than silently dropping the logic.
# - For survey examples, prefer simple, atomic examples that map clearly onto Boolean logic and routing states.

# Useful project commands
#   & "C:\MY_RST~1\R-46~1.1\bin\x64\Rscript.exe" --vanilla tests/test_framework.R
#   & "C:\MY_RST~1\R-46~1.1\bin\x64\Rscript.exe" --vanilla examples/school_activity_survey.R
#   & "C:\MY_RST~1\R-46~1.1\bin\x64\Rscript.exe" --vanilla examples/parsed_survey_information.R

# Troubleshooting
# - If Rscript is not found, use the full path above rather than relying on PATH.
# - If a script fails due to data-path assumptions, verify that the working directory is the project root and use file.path() or relative paths from there.
# - Keep new examples atomic and readable; this project is easier to reason about when each rule is a small, explicit Boolean state transition.