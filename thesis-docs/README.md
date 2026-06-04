# DermaTrack — Thesis Documentation

Generated from the actual codebase (read-only investigation; no invented features, tables, or tests). Diagrams are PlantUML/Mermaid **source**; render with the steps in `diagrams/README.md`.

## File index

| File | What it is |
|---|---|
| `00_system_overview.md` | **Phase 0** — plain-language system description, tech stack, RBAC capabilities per role, UI-vs-implemented gaps, and the full database schema (source of truth for all diagrams). |
| `diagrams/README.md` | Figure caption + 3–5 sentence description for every diagram, plus PNG/SVG render commands. |
| `diagrams/system_usecase.puml` | System-wide use-case diagram (all actors + `<<include>>`/`<<extend>>`). |
| `diagrams/patient_usecase.puml` | Patient-only use cases. |
| `diagrams/doctor_usecase.puml` | Doctor-only use cases (consent-gated). |
| `diagrams/admin_usecase.puml` | Admin-only use cases (+ note on non-implemented modules). |
| `diagrams/database_erd.puml` | Entity-Relationship Diagram (PlantUML). |
| `diagrams/database_erd.mmd` | Same ERD in Mermaid (renders in GitHub/VS Code). |
| `diagrams/class_diagram.puml` | Domain models + key service classes. |
| `diagrams/seq_authentication.puml` | Sequence: login-as → sign-in → role routing. |
| `diagrams/seq_scan_analysis.puml` | Sequence: capture → analyze (Roboflow+HF) → severity result. |
| `diagrams/seq_doctor_review.puml` | Sequence: consent-gated doctor review + note. |
| `diagrams/seq_prescription.puml` | Sequence: doctor issues prescription → patient views. |
| `diagrams/seq_break_glass.puml` | Sequence: admin time-limited read-only emergency access + audit. |
| `diagrams/seq_chat.puml` | Sequence: patient↔doctor messaging over Realtime. |
| `diagrams/activity_diagram.puml` | Core workflow: scan → severity → consent → review → follow-up. |
| `diagrams/dfd_context.puml` | Data Flow Diagram Level 0 (context). |
| `diagrams/dfd_level1.puml` | Data Flow Diagram Level 1 (processes + data stores). |
| `diagrams/architecture_diagram.puml` | Component / layered architecture. |
| `diagrams/deployment_diagram.puml` | Deployment topology. |
| `diagrams/status_statediagram.puml` | State diagram: break-glass session lifecycle. |
| `diagrams/scan_review_state.puml` | State diagram: scan review status (extra). |
| `diagrams/rbac_matrix.puml` | RBAC permission matrix (extra, security). |
| `diagrams/trust_boundary_dfd.puml` | Security trust-boundary data flow (extra, security). |
| `testing/security_testing.md` | OWASP-aligned security testing with live access-control evidence, summary table, and risk assessment. |
| `testing/functional_testing.md` | Unit (24 pass, 5% coverage), integration (live), functional test-case tables per role, system/UAT/performance/compatibility/regression. |
| `testing/security_assessment.md` | **Security assessment** — full actor×operation×resource **vulnerability matrix** (23 tests, executed live with DB ground-truth), narrative + risk section. |
| `testing/admin_functional_testing.md` | **Admin access functional testing** — real Pass/Fail per admin capability with a UI-vs-DB enforcement cross-reference. |
| `improvement_assessment.md` | Whole-app assessment + prioritized improvement recommendations (P0→P2). |

## Suggested chapter mapping for the paper
- **Chapter 3 (Design):** `00_system_overview.md` + use-case, ERD, class, DFD, architecture, deployment diagrams.
- **Chapter 3 (Detailed design):** sequence + activity + state diagrams; RBAC matrix + trust-boundary for the security design section.
- **Chapter 4 (Testing):** `testing/security_testing.md` + `testing/functional_testing.md`.

## Notes
- Rendered PNG/SVG are **not** included yet (PlantUML jar not installed). See `diagrams/README.md` to render, or ask and they can be produced (Java 21 is available).
- A `.docx` of the testing chapters can be produced with Pandoc: `pandoc testing/security_testing.md -o security_testing.docx` (if Pandoc is installed).
- Verified app version at time of writing: **v0.5.1** (reminder fix); `flutter test` 24/24; `flutter analyze` 0 errors.
