# Survey DSL Prototype

This project contains a small, dependency-free R framework for describing and checking survey logic.

For poorly structured source material, `R/survey_parser.R` provides a deliberately conservative first stage. It identifies sections, question-shaped lines, answer options, guidance, source line numbers, and review cues before compiling the result into the DSL. It does not pretend that implicit routing or domain meaning can be recovered perfectly; those remain visible for human review.

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
Rscript --vanilla examples/parsed_survey_information.R
```

Predicates are currently controlled R expressions such as `has_activities == TRUE` or `!has_activities && phone_time_daily_hours >= 4`. This is an intentionally small prototype boundary: a later parser can compile YAML, a visual editor, or legacy survey specifications into the same model without changing the execution and audit engine.