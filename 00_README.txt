TMS Executable Database Foundation v1.5
Run order:
01_core_tables.sql
02_security_and_reference_tables.sql
03_ticket_tables.sql
04_indexes_constraints.sql
05_packages.sql
06_audit_triggers.sql
07_views.sql
08_seed_reference_data.sql

IMPORTANT:
- This is an executable FOUNDATION generated from the v1.5 Blueprint.
- VPD policies are intentionally NOT installed here because Section 27 freezes their final policy definition and deployment must be completed by the hand-built security engine.
- Run in TMS_OWNER schema on Oracle Database 23ai.
