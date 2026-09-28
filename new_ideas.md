You have built a clean foundation. Mapping questionnaire logic to a finite state machine (FSM) or directed acyclic graph (DAG) with guarded transitions is the exact right entry point. By separating the survey state graph from data-checking rules, you avoid mixing skip logic with validation logic—a common pitfall in standard survey software.

Your core challenge moves from basic Boolean routing to **relational set logic over hierarchical data structures** (Households $\rightarrow$ Persons $\rightarrow$ Events/Items).

Below is a summary of existing domain languages, academic formalisms, and industry specifications, followed by concrete ideas to evolve your framework.

---

## 1. Summary of Existing Formalisms & Tools

Survey representation and data validation fall into three main domains: academic survey specification languages, statistical validation DSLs, and industry metadata standards.

### Academic & Domain-Specific Survey Languages

* **CADAC / Blaise (Statistics Netherlands):** Blaise is the gold standard in official statistics (used by US Census Bureau, UK ONS, Eurostat). Its language separates the **Datamodel** (variable definitions, types, blocks, and sub-tables) from the **Rules** (routing and edit checks).
* *Relevance to your model:* Blaise handles household structures via nested arrays/lists of blocks (e.g., `Person: Array[1..20] of BPerson`). It uses quantifiers like `COUNT`, `SUM`, and existential operators (`FORALL`, `EXISTS`) across array elements to enforce cross-row rules (e.g., "Number of children under 16 reported by Household Respondent must equal `COUNT(Persons where Age < 16)`").


* **Tripod / CSPro (US Census Bureau):** Uses a hierarchical dictionary model (Level $\rightarrow$ Record $\rightarrow$ Item). Routing occurs via explicit procedural code (`skip to`) or conditional blocks, but lacks a pure, graph-based declarative syntax.
* **Form / Data Collection DSLs (XForms / ODK / Survey123):** Built on the W3C XForms specification. Routing relies on XPath predicates (`relevant="/data/group_person/age > 18"`).
* *Relevance:* XPath handles parent/child relationships naturally using axes (`parent::`, `ancestor::`, `preceding-sibling::`). For multi-row consistency, XForms uses functions like `count(/data/person[age < 18])`.



### Statistical Data Editing & Validation DSLs (R Ecosystem)

Since your prototype is in R, two packages from the official statistics community closely match your validation layer:

* **`validate` (van der Loo & de Jonge / Statistics Netherlands):** A declarative DSL for data validation rules. It uses standard R syntax extended with domain operators.
* *Multi-row capability:* Allows grouping and cross-row operations using `exists()`, `for_all()`, or aggregated group keys (`sum(income) by household_id`).


* **`errorlocate` & `editrules`:** Implement the **Fellegi-Holt paradigm** for automatic error detection and minimal field imputation. They translate logical constraints into linear programming or satisfiability (SAT) problems to detect contradictory rules before data collection.

### Metadata Standards

* **DDI (Data Documentation Initiative) Lifecycle:** Uses DDI-ControlConstructs (Sequence, IfThenElse, RepeatWhile) to model questionnaires as formal state graphs. DDI-L is highly descriptive for archival and auditing, though heavy for direct execution.

---

## 2. Theoretical Framework for Multi-Row Household Logic

Standard Boolean algebra acts on single vectors of propositions ($f: \{0,1\}^n \to \{0,1\}$). Multi-row survey logic requires **First-Order Predicate Logic (FOL) over Bounded Multi-Sets (Relational Tuples)**.

To formalize household structures without blowing up complexity, your logic needs three core abstractions:

$$\text{Survey Context} = \langle \mathbf{H}, \mathbf{M}, \mathbf{R} \rangle$$

* $\mathbf{H}$: Household-level attributes (e.g., `tenure`, `num_children_reported`).
* $\mathbf{M}$: Set of Person/Member rows $m_1, m_2, \dots, m_k \in \mathbf{M}$.
* $\mathbf{R}$: Relational predicates or link matrices (e.g., $R(m_i, m_j) = \text{spouses}$).

### Key Logical Operators Needed

1. **Set Quantifiers over Members:**
* $\forall m \in \mathbf{M}: \text{Age}(m) \ge 0$
* $\exists m \in \mathbf{M}: \text{IsHouseholdHead}(m)$


2. **Bounded Aggregation & Count Operators:**
* $\mathbf{Count}(\{m \in \mathbf{M} \mid \text{Age}(m) < 18\}) = \text{H.reported\_children}$
* $\mathbf{Sum}(\{m.\text{income} \mid m \in \mathbf{M}\}) = \text{H.total\_household\_income}$


3. **Relational Pairwise Consistency (Symmetry / Antisymmetry):**
* If $m_i$ reports $m_j$ as a spouse, then $m_j$ must report $m_i$ as a spouse.
* $\forall m_i, m_j \in \mathbf{M} \times \mathbf{M}: \text{SpouseOf}(m_i, m_j) \implies \text{SpouseOf}(m_j, m_i)$.



---

## 3. Concrete Ideas for Further Research & Evolving Your DSL

### A. Extend the Guard Predicate Engine with Standardized Quantifiers

Instead of writing raw R expressions that the compiler marks as "unsupported," define a structured **Abstract Syntax Tree (AST)** or expression grammar for multi-row logic.

Introduce explicit relational primitives into your transition guards and `survey_rule()` definitions:

```r
# Concept: Household Cross-Row Rule
survey_rule(
  id = "chk_child_count",
  scope = "household",
  predicate = eq(
    H$reported_children,
    count_where(M, function(m) m$age < 18)
  ),
  message = "Reported child count does not match the number of member records under 18."
)

# Concept: Pairwise Symmetry Check
survey_rule(
  id = "chk_spouse_symmetry",
  scope = "household_relational",
  predicate = is_symmetric(M, link_col = "spouse_member_id"),
  message = "Spousal relationship is not reciprocal."
)

```

### B. Dual-Graph Architecture: Flow Graph vs. Constraint Graph

Your prototype uses a State Machine for survey routing. For complex questionnaires, split the system into two explicit layers:

```
┌─────────────────────────────────────────┐
│     Flow Graph (Directed Graph / FSM)   │  ──> Controls Navigation & Skips
│     Nodes = Questions, Edges = Guards   │      (Single-Respondent View)
└─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│   Constraint Graph (Hypergraph / SAT)   │  ──> Controls Inter-Variable Audit
│   Nodes = Variables, Hyperedges = Rules │      (Cross-Row Household View)
└─────────────────────────────────────────┘

```

* **Flow Graph:** Governs sequence during administration (`run_survey()`).
* **Constraint Graph:** Validates data post-hoc or at household completion (`check_response()`). Evaluating household-level constraints during single-row traversal often leads to false positives because other member rows may not be filled out yet.

### C. Static Formal Verification (SAT / SMT Solvers)

Because you already compile your questionnaire into a state graph and an explicit dependency report (`was_round9_variable_dependencies.tsv`), you can leverage **Satisfiability Modulo Theories (SMT)** solvers (like Z3 via `z3r` or Python/C bindings).

Static checks you can perform before field deployment:

1. **Dead State Detection:** Is there a question state $S_k$ whose guard condition evaluates to FALSE under all valid prior response combinations?
2. **Unreachable Routes:** Are there path preconditions that form logical contradictions (e.g., $A > 10 \land A < 5$)?
3. **Complete Partitioning:** Do outgoing transitions from a choice question cover 100% of the valid response space without silent fallbacks?

### D. Relational Roster Mechanics ("Looping States")

In household surveys, person rows are generated dynamically via a household roster. Consider formalizing roster generation in the DSL state machine:

```r
# Dynamic State Generator
survey_roster_loop(
  id = "person_loop",
  target_count = H$num_members,  # Derived from roster question
  item_states = list(
    survey_state("person_name"),
    survey_state("person_age"),
    survey_state("person_employment")
  )
)

```

During audit, the engine expands the loop into indexed instances ($m_1, m_2, \dots, m_n$) to evaluate both row-level routes and set-level aggregate rules seamlessly.

---

## Suggested Next Steps

1. **Abstract Syntax Tree (AST) for Predicates:** Replace raw R expression parsing in YAML specs with a formal parser (e.g., using `rlang` ASTs or a small parser built with `lark`/`rparse`) to turn "unsupported" YAML routes into structured, executable predicate objects.
2. **Integrate `validate` semantics:** Examine the `validate` R package source code to see how it handles `by = household_key` assertions, or import it directly for the `survey_rule()` evaluation layer.
3. **Formalize the Roster State:** Add explicit dynamic node structures (Loops/Rosters) to your core state machine so that `run_survey()` can naturally process array-like structures without forcing flat CSV layouts too early.


Using UML—or any high-density formal modeling language—brings a structural precision that raw graph diagrams like basic state machines struggle to maintain as questionnaires grow.

The core issue you are hitting with your Mermaid diagrams is **flat visual explosion**: representing every question, branch, and member instance as an individual graph node turns a simple household questionnaire into a tangled "spaghetti" diagram.

Here is a breakdown of the pros and cons of using UML (or UML-like concepts) as the underlying metamodel, followed by structural techniques to solve the scaling problem.

---

## 1. UML as a Survey Language Metamodel: Pros & Cons

UML is not just one diagram type; it is a family of structural and behavioral views built on a unified metamodel.

### Pros

* **Native Multi-Level Modeling (Classes vs. Instances):** UML cleanly separates the *template* from the *data*. A `Person` Class defines the question schema once. A `Household` object contains an aggregation of `Person` instances ($1..*$). You don't diagram 4 separate person branches; you diagram 1 `Person` class with an multiplicity constraint ($N$).
* **Encapsulation & Subtyping (Inheritance):** You can model specialized respondent types cleanly. A `Child` and an `Adult` can inherit from a base `HouseholdMember` class, sharing core variables (`age`, `gender`) while adding conditional sub-questionnaires (`employment` for Adults, `schooling` for Children).
* **State Machine Views (Behavior) + Class Views (Structure):** UML separates structural relationships (Class Diagrams) from temporal flow (State Machine Diagrams / Activity Diagrams). This avoids forcing variable dependencies and respondent navigation onto the exact same visual canvas.
* **Composite States (Hierarchical FSMs):** UML State Machines support nested/composite states and parallel regions. A whole section (e.g., "Housing Conditions") can be treated as a single state node that expands internally when zoomed in.

### Cons

* **Verbosity & XML/XMI Bloat:** UML's standard interchange format (XMI) is notoriously heavy and unreadable. Hand-crafting or parsing raw UML models without a heavy graphical modeling tool (like Enterprise Architect or MagicDraw) adds significant framework overhead.
* **Over-Engineering for Simple Logic:** UML carries a lot of object-oriented baggage (visibility, polymorphism, operations) that isn't directly relevant to survey design.
* **Layout Engine Deficits:** Standard UML drawing tools struggle with auto-layout just as much as Mermaid when generating SVGs programmatically.

---

## 2. Solving the Scale Issue: Structural Abstractions

To make the survey language scale both **up** (macro architecture for humans) and **down** (micro question execution for engines), you do not need full UML compliance. Instead, adopt three core UML design patterns in your DSL:

### A. Hierarchical / Composite States (Zoom-In / Zoom-Out)

Instead of a flat graph where every question is a node, group questions into **Composite Modules** (Sections, Rosters, Loops).

* **Macro View (Level 0):** Show only Sections and high-level routing.

$$\text{Household Cover} \longrightarrow \text{Member Roster Loop} \longrightarrow \text{Dwelling Section} \longrightarrow \text{End}$$


* **Micro View (Level 1):** Expand a single composite node (e.g., `Member Roster Loop`) to see its internal state machine without rendering the rest of the survey.

### B. Distinguish the Flow Graph from the Data Schema

Your current Mermaid visual is likely crowded because it tries to show both **Variable Dependencies** and **Navigation Logic** simultaneously.

Split them into two distinct view generators:

1. **Structure / Class View:** Shows variables, data types, and household-to-member relationships ($1 \to N$).
2. **Navigation Activity View:** Shows execution flow between high-level blocks, suppressing intra-section linear question steps ($Q1 \to Q2 \to Q3$ becomes a single "Section 1" block).

### C. Roster Abstraction (Parameterization over Multi-Row Expansion)

Never render multiple rows in the visual state machine. Render a **Loop Construct** with an explicit context variable (e.g., `for each person in Household.members`).

---

## 3. Comparing Diagrammatic Representations for DSL Visuals

| Feature | Flat State Graph (Current) | UML Activity / State Machine | DFD / Dependency Graph | BPMN (Business Process) |
| --- | --- | --- | --- | --- |
| **Best Used For** | Micro-auditing single skip patterns | Hierarchical survey logic & OOP schemas | Variable dependency & audit tracking | High-level enumerator workflows |
| **Human Legibility** | Breaks at ~30+ nodes | High (if using composite states) | Moderate (can look like a mesh) | High for non-technical stakeholders |
| **Roster / Array Support** | Poor (requires unrolling or dynamic hacks) | Native (Loops, Composite Regions, Collections) | Poor | Native (Sub-processes with Loop markers) |

---

## Next Steps for Improving Your Prototype

1. **Introduce Composite States in your DSL:** Add a `survey_section()` or `survey_module()` wrapper in R that acts as a single state node in high-level diagrams, containing child states within it.
2. **Multi-Level Visual Exporters:** Modify your Mermaid generator to support a `depth` parameter (e.g., `mermaid_state_machine(survey, depth = "section")` vs `depth = "question"`).
3. **Formalize the Roster Class Model:** Define household structures as typed objects/tables before mapping their internal question flows.


I’ll read `new_ideas.md`, then compare its proposals against the current DSL’s model, validation gaps, and existing examples so I can separate immediately useful ideas from scope creep and suggest a practical next step.

Read 

Read 

Read , lines 150 to 392

Read , lines 100 to 136

`new_ideas.md` contains several useful directions, especially around the gap between single-row routing and household-level validation.

**Most valuable ideas**

1. **Separate flow logic from validation logic**
   This is already partly present:
   - Flow: `survey_state()`, `survey_transition()`, `run_survey()`
   - Validation: `survey_rule()`, `audit_survey_responses()`, `survey_issue_report()`

   Make this an explicit architectural principle. Routing answers “what question comes next?” Validation answers “is the completed data coherent?”

2. **Add household-scoped rules**
   This is the most important missing capability. The current code creates household keys and member indexes, but does not yet compare rows within a household.

   A useful next abstraction might be:

   ```r
   survey_group_rule(
     id = "children_match_roster",
     group_by = c("OSGRIDREF", "AREA", "ADDRESS"),
     when = ...,
     message = ...
   )
   ```

   Initial rules could support:
   - reported child count equals matching child-member rows
   - exactly one household reference person
   - spouse/partner references are reciprocal
   - household-level values are consistent across member rows
   - person numbers are unique within a household

3. **Use structured predicates instead of increasingly complex R strings**
   The AST idea is sound, particularly because unsupported YAML routes are currently retained but skipped. However, I would not begin with a general parser. Start with a small set of structured operations:

   - `equals()`
   - `count_where()`
   - `exists()`
   - `all_where()`
   - `sum_by()`
   - `same_across_group()`

   This gives the project useful relational logic without committing to a full formal language.

4. **Introduce roster metadata before dynamic looping**
   The proposed roster abstraction is relevant, but dynamic state expansion is probably premature. First represent the data model explicitly:

   ```text
   Household 1 -> many Person rows
   Person 1 -> many Event or Item rows
   ```

   Define row roles, identifiers, group keys, and relationship columns first. Then add looping behavior to the survey runner once the schema is stable.

5. **Improve diagrams through hierarchy**
   The document is right that the current flat Mermaid output will become difficult to use. Composite sections or modules would help:

   - household cover
   - household roster
   - person interview
   - housing
   - employment
   - assets

   Generate both:
   - a high-level section diagram
   - a detailed question-level diagram for one selected section

**Ideas I would defer**

- **Full UML/XMI support:** likely too much machinery for this project. Borrow the useful concepts, such as multiplicity and composite states, without adopting UML as the implementation format.
- **SAT/SMT integration:** potentially valuable for advanced static route analysis, but only after route expressions have a well-defined structured representation.
- **Immediate integration with external validation packages:** worth researching, but the project should first define its own household rule contract and test cases.

**Suggested order of work**

1. Define a small household/member schema and document required identifiers.
2. Add `survey_group_rule()` or equivalent household-scoped validation.
3. Implement the child-count example as the first cross-row rule.
4. Add tests for valid and invalid four-person households.
5. Add a few general relational rules, such as uniqueness and reciprocal relationships.
6. Introduce structured predicates only when real rules demonstrate the need.
7. Add section/module metadata and hierarchical diagram output.

The strongest practical next step is therefore **household-scoped validation**, beginning with count-to-roster reconciliation. The ideas in `new_ideas.md` are useful as a roadmap, but the project should avoid jumping directly to UML, dynamic FSM expansion, or solver integration before its household data model is explicit.