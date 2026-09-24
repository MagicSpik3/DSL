# Survey DSL Prototype

This project contains a small, dependency-free R framework for describing and checking survey logic.

The core model is deliberately narrow:

- `survey_variable()` defines captured data.
- `survey_state()` defines a question or control-flow node.
- `survey_transition()` defines a guarded transition between states.
- `survey_rule()` defines a cross-variable quality rule.
- `audit_survey()` checks the state graph before fieldwork.
- `run_survey()` traverses the graph using a respondent context.
- `check_response()` checks only questions reached by that respondent.

Try the example from the project root:

```sh
Rscript --vanilla examples/school_activity_survey.R
Rscript --vanilla tests/test_framework.R
```

Predicates are currently controlled R expressions such as `has_activities == TRUE` or `!has_activities && phone_time_daily_hours >= 4`. This is an intentionally small prototype boundary: a later parser can compile YAML, a visual editor, or legacy survey specifications into the same model without changing the execution and audit engine.