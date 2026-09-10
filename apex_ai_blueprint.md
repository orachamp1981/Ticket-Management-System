# Multi-Organization Ticket Management System (TMS)
> **v1.3 — ARCHITECTURE FREEZE** (foundation, unchanged): Dropped TMS_ORG_HIERARCHY (PARENT_ORG_ID only); G_ROLE_SET/G_PERMISSION_SET locked as cache-only, never string-evaluated by generated code; Data Access enforcement locked to VPD + access-scoped views applied consistently on every table; ORG_ID mandatory rule scoped to tenant-owned tables only; added TMS_COST_CENTRES as authorization-excluded. Sections 2–16 and 27 are under formal change-control (Section 32). Terminology standardized on G_SCOPE_TYPE throughout.
>
> **v1.5** — Section 24 re-designed for visual impact: navy-indigo/cyan-teal/amber palette (replacing the flatter slate-blue draft), Redwood-style card layout with soft elevation, a designed KPI dashboard landing and split-screen login instead of APEX defaults, and restrained motion guidance. Per-org branding dropped in favor of one unified premium theme for every tenant.
## Master Blueprint for Oracle APEX AI Assistant

> **How to use this document:** Paste this entire file (or section-by-section) into APEX AI Assistant as project context before asking it to generate anything. Every future prompt to the AI for a new module should begin with: *"Follow the TMS Master Blueprint. Do not deviate from sections 2, 26, and 27."* Keep this file version-controlled — it is the single source of truth the AI must obey.

---

## 1. Project Context and Objective

**Project name:** Multi-Organization Ticket Management System (TMS)

**Objective:** Build a low-code Oracle APEX application that lets multiple independent organizations (tenants) raise, track, resolve, and audit tickets/cases within one shared platform, while keeping each organization's data strictly isolated except where explicitly shared via a global/category model.

**Primary goals:**
- One codebase, one schema, many organizations (multi-tenant, not multi-copy).
- Zero data leakage between organizations unless explicitly authorized.
- Full audit trail on every state change.
- SLA-driven workflow with automated notifications.
- AI-assisted module generation that never violates the architecture below.

**Out of scope for AI generation:** core security tables, the authorization engine, the data access resolution engine, and the audit engine — these are hand-built and frozen (see Section 27).

---

## 2. Existing Architecture AI Must Respect

Before generating anything, APEX AI Assistant must treat the following as **immutable ground truth**:

- **Database:** Oracle Database 23ai, single pluggable database, single schema (`TMS_OWNER`), Oracle REST Data Services (ORDS) exposed only where explicitly listed.
- **App shell:** One APEX application (App ID reserved), Universal Theme (current release theme), one shared Application Item set for session context, one shared set of Authorization Schemes (Section 22).
- **Session context:** Every session carries `APP_USER`, `G_ORG_ID` (current organization context), `G_ROLE_SET` (resolved roles), `G_PERMISSION_SET` (resolved permissions), and `G_SCOPE_TYPE` (resolved data scope) as Application/Global Items — set exactly once, at authentication time, by the core engine, and re-resolved automatically on organization switch (Section 4). **No generated page or process may set these items directly.**
- **Naming convention:** Tables `TMS_<NOUN>`, packages `PKG_TMS_<DOMAIN>`, pages grouped by numeric range per module (see Section 29).
- **No page, region, or process may query business tables directly without going through the Data Access Resolution Engine (Section 7) for row-level filtering.**

---

## 3. Database/Schema Blueprint

Core tables the AI must treat as **read-only reference** (already exist, never regenerate):

| Table | Purpose |
|---|---|
| `TMS_ORGANIZATIONS` | Master list of tenant organizations. Hierarchy is a simple tree via `PARENT_ORG_ID` on this table — **no separate `TMS_ORG_HIERARCHY` table** (Architecture Freeze decision, see note below) |
| `TMS_DEPARTMENTS` | Departments, each FK'd to exactly one Organization |
| `TMS_COST_CENTRES` | `COST_CENTRE_ID`, `ORG_ID` FK, `DEPARTMENT_ID` FK (optional), `COST_CENTRE_CODE`, `COST_CENTRE_NAME`, `STATUS` — an **optional classification only**, explicitly outside the authorization hierarchy (Section 4); never referenced by `PKG_TMS_AUTH` or `PKG_TMS_DATA_ACCESS` |
| `TMS_USERS` | Application users — identity/account only (maps to APEX/IDCS) |
| `TMS_USER_DETAILS` | Person/professional profile (name, employee code, contact) — 1:1 with `TMS_USERS`, never merged into it |
| `TMS_USER_ORGANIZATIONS` | Membership only: User ↔ Organization ↔ Department, `IS_PRIMARY`, `MEMBERSHIP_STATUS`, `EFFECTIVE_FROM/TO` |
| `TMS_USER_ORGANIZATION_ROLES` | Authority only: Role(s) attached to a specific `TMS_USER_ORGANIZATIONS` membership row |
| `TMS_ROLES` | Role catalog. `ORG_ID` nullable: **NULL = Global/platform-defined role** (visible to and usable by every org, edited only by platform admins), **populated = Organization-specific custom role** (created and edited only by that org's Admin) — mirrors the Category Global-vs-Org pattern in Section 9 |
| `TMS_ROLE_DETAILS` | Role metadata (description, category, is-system-role flag) — descriptive only, carries no authority itself |
| `TMS_FUNCTIONS` | Capability/module catalog (e.g. `TICKET`, `ORGANIZATION`, `SLA_RULE`, `REPORTING`) — **not** the atomic permission itself |
| `TMS_ACTIONS` | Verb catalog (e.g. `CREATE`, `VIEW`, `UPDATE`, `DELETE`, `APPROVE`, `CLOSE`, `REASSIGN`, `EXPORT`, `OVERRIDE`) — reusable across every Function |
| `TMS_PERMISSIONS` | The atomic permission: unique `(FUNCTION_ID, ACTION_ID)` pair, e.g. `TICKET` + `CREATE` = "can create tickets." A derived `PERMISSION_CODE` (`TICKET_CREATE`) is stored for display/logging only — the FK pair is the real grant unit |
| `TMS_ROLE_PERMISSIONS` | Role ↔ Permission grants (replaces a flat Role↔Function table) |
| `TMS_DELEGATIONS` | Temporary delegated authority (role/permission-level, time-boxed) |
| `TMS_CATEGORIES` | Global vs org-specific category catalog |
| `TMS_AUDIT_LOG` | Immutable audit trail |
| `TMS_SLA_RULES` | SLA thresholds per category/priority/org |
| `TMS_NOTIFICATIONS_LOG` | Sent notification history |

Tables the AI **is allowed to design and generate**, following the naming/pattern rules below:

| Table | Purpose |
|---|---|
| `TMS_TICKETS` | Core ticket header |
| `TMS_TICKET_DETAILS` | Extended/domain-specific attributes per category |
| `TMS_TICKET_COMMENTS` | Discussion thread |
| `TMS_TICKET_ATTACHMENTS` | File metadata |
| `TMS_TICKET_HISTORY` | State transition log (feeds audit) |
| `TMS_TICKET_WATCHERS` | Users following a ticket |
| Module-specific child tables | Any new module's own tables, always FK'd to `TMS_TICKETS.TICKET_ID` |

**Mandatory columns on every new business table:**
Every **tenant-owned** business record must carry `ORG_ID NOT NULL FK TMS_ORGANIZATIONS`, `CREATED_BY`, `CREATED_DATE`, `UPDATED_BY`, `UPDATED_DATE`, `RECORD_VERSION` (optimistic locking), and — where the table represents anything ticket-related — `TICKET_ID FK`. **Global/system metadata tables are explicitly exempt from `ORG_ID`** (e.g. `TMS_MODULE_REGISTER`, `TMS_STATUS_TRANSITIONS`, `TMS_GLOBAL_TEMPLATE`) but must still carry `CREATED_BY/DATE`, `UPDATED_BY/DATE`, and — in their table comment or a `TMS_ROLE_DETAILS`-style descriptor — document why they have no organization owner. The AI must not default `ORG_ID NOT NULL` onto a genuinely global table just to follow the general rule; equally, it must not omit `ORG_ID` from a tenant-owned table on the assumption that "it seems minor."

**Architecture Freeze note (Organization Hierarchy):** `TMS_ORG_HIERARCHY` was considered and deliberately dropped — a single `PARENT_ORG_ID` column on `TMS_ORGANIZATIONS` covers the real requirement (a straightforward tree for parent/child data visibility, Section 4). If a genuine future requirement needs a non-tree relationship (e.g., an organization with more than one parent), that is a distinct, change-controlled addition (Section 32) — not something the AI should introduce speculatively.

---

## 4. Organization and Multi-Organization Model

- Every organization is a row in `TMS_ORGANIZATIONS` with a unique `ORG_ID`, `ORG_CODE`, `PARENT_ORG_ID` (nullable, for hierarchy), `STATUS` (Active/Suspended/Onboarding), and `ORG_TYPE`.
- Organizations can be **hierarchical** (a parent org can optionally see aggregated child-org data — controlled by an explicit `CAN_VIEW_CHILD_DATA` flag, never assumed).
- Each Organization owns its own set of `TMS_DEPARTMENTS` rows (`DEPARTMENT.ORGANIZATION_ID` FK, mandatory) — a Department can never be shared across Organizations, and this is enforced as a **referential business rule**, not just an LOV filter: `DEPARTMENT.ORGANIZATION_ID` must equal the `ORGANIZATION_ID` on the membership row it's attached to, checked at both the APEX validation layer and the database constraint/trigger layer.
- **Membership vs. Role are two distinct relationships, not one:**
  - `TMS_USER_ORGANIZATIONS` records *that* a user belongs to an Organization (and which Department, whether it's their `IS_PRIMARY` org, `MEMBERSHIP_STATUS`, `EFFECTIVE_FROM/TO`).
  - `TMS_USER_ORGANIZATION_ROLES` records *what authority* that membership carries (one or more Roles attached to a specific `TMS_USER_ORGANIZATIONS` row).
  - This split exists so membership lifecycle (joining/leaving/transferring departments) never has to touch role/authority data, and vice versa.
- **Org LOV → Department LOV is always cascading**, never independent: Department LOV is filtered by the already-selected Organization (`WHERE organization_id = :ORG_ITEM AND status = 'ACTIVE'`), so a Super User picking Organization A can never see Organization B's departments in the same form.
- **Scope by actor:** a Super User assigning membership gets an unrestricted Organization LOV; an Organization Admin creating a user gets the Organization pre-set to their own (no LOV shown) — but this is presentation only. The backend authorization layer independently re-validates that any submitted `ORGANIZATION_ID` is within the acting user's authorized scope, regardless of what the UI displayed or hid.
- A user can hold **more than one organization membership** simultaneously (multiple `TMS_USER_ORGANIZATIONS` rows), with exactly one flagged `IS_PRIMARY = 'Y'` at a time. Switching active organization context via the session picker re-resolves `G_ORG_ID`, `G_ROLE_SET`, `G_PERMISSION_SET`, and `G_SCOPE_TYPE` through the core engine — never set manually by generated code. **This organization switch is not the forbidden "role picker":** the user chooses *which organization* to act in; the system then automatically resolves *every* effective role and permission for that organization via the union rule (Section 5). The user never chooses which of their roles to operate under.
- **Registered-organization onboarding:** when a new Organization is created via self-registration + Super User approval, the initial Admin user does **not** pick an Organization from an LOV — `ORGANIZATION_ID` is pre-assigned from the registration record itself, with department/cost-centre context defaulted per Section 10.
- Cost Centre is treated as an **optional classification**, not a mandatory authorization dimension, and is intentionally kept out of `TMS_USER_ORGANIZATIONS` — it lives in its own `TMS_COST_CENTRES` table (Section 3), never referenced by the authorization or data-access engines. If a real requirement later demands Cost-Centre-based authorization, that is a deliberate, change-controlled architecture extension (Section 32), not a default the AI introduces.
- No business table stores organization name — always `ORG_ID` FK, resolved via LOV/join at display time.

---

## 5. User, Role, Function, Action and Scope Model

Five-layer model — the AI must never collapse these layers into one flag or one table:

1. **User** (`TMS_USERS`) — identity/account only: login, credentials mapping, org-agnostic.
2. **User Detail** (`TMS_USER_DETAILS`) — the person/professional profile (name, employee code, contact info), 1:1 with `TMS_USERS`. Kept separate so identity churn (e.g., account status) never touches profile data and vice versa.
3. **Membership** (`TMS_USER_ORGANIZATIONS`) — *that* the user belongs to an Organization/Department (Section 4). Carries no authority by itself.
4. **Role** (`TMS_USER_ORGANIZATION_ROLES` → `TMS_ROLES`) — a named bundle of Permissions (e.g., "Org Admin," "Agent," "Requester," "Approver"), attached to a specific membership row, so the same user can be "Agent" in Org A and "Requester" in Org B without the two ever being confused. A Role is either **Global** (`ORG_ID IS NULL`, platform-defined, usable by any org) or **Organization-specific** (`ORG_ID` populated, custom-built and maintained only by that org's Admin) — see Section 9 for the pattern this mirrors.
5. **Function + Action → Permission + Scope** — a **Function** (capability, e.g. `TICKET`) combined with an **Action** (verb, e.g. `CREATE`) forms one atomic **Permission** (`TMS_PERMISSIONS`); Roles are named sets of Permissions (`TMS_ROLE_PERMISSIONS`). Every UI action (button, process, report row) checks: *does the resolved Permission Set include this Function+Action pair, and does the resolved Scope (Section 7) include this record?* Both must pass.

**Multiple Roles on one membership:** a user's Permission Set is the **union** of every active Role attached to their current membership — permissions are purely additive, there is no session-level "pick one active role" step and no explicit deny/override mechanic. If a genuine need for restrictive/deny permissions emerges later, that is a deliberate architecture change (Section 32 change-control), not a default the AI should ever introduce on its own.

**Rule for AI:** never hardcode "if role = 'Admin'" in generated code, and never write directly to `TMS_USERS` when the data actually belongs in `TMS_USER_DETAILS` (e.g., an employee code is a profile attribute, not an identity attribute). Always check grants via the shared `PKG_TMS_AUTH.HAS_PERMISSION(p_function_code, p_action_code)` call — never query `TMS_ROLE_PERMISSIONS` directly from generated code.

---

## 6. Authorization Context

A single PL/SQL-resolved "Authorization Context" is computed once per session/org-switch and cached in Application Items:

- `G_ORG_ID` — active organization
- `G_ROLE_SET` — comma-list or resolved collection of role codes for that org (union of every active Role on the current membership, per Section 5)
- `G_PERMISSION_SET` — flattened set of all Function+Action Permission pairs granted by those roles (formerly `G_FUNCTION_SET`)
- `G_SCOPE_TYPE` — Own / Team / Organization / Child-Organizations / Global
- `G_DELEGATED_FROM` — populated only if acting under delegation (Section 8)

This context is exposed to generated code **only** through `PKG_TMS_AUTH` functions — never by reading Application Items directly in a generated page, so the resolution logic can change without breaking modules.

**Architecture Freeze note (G_ROLE_SET is cache, not authority):** `G_ROLE_SET` and `G_PERMISSION_SET` are a cached *representation* of the resolved context, not the source of truth. Generated code must **never** evaluate them directly — no `INSTR(:G_ROLE_SET, 'ADMIN')`, no `:G_ROLE_SET LIKE '%ADMIN%'`, no string-matching of any kind. The only legitimate authorization check, everywhere, is `PKG_TMS_AUTH.HAS_PERMISSION(p_function_code, p_action_code)`. This is non-negotiable even for "quick" conditions on a button or region.

---

## 7. Data Access Resolution Engine

A single package, `PKG_TMS_DATA_ACCESS`, is the **only** legitimate path to row-level filtering, and is the single source of access logic regardless of which mechanism ultimately enforces it.

**Architecture Freeze decision — defense in depth, applied consistently:** `PKG_TMS_DATA_ACCESS` centralizes the access logic; it is enforced through **both** of the following, on every business table, not a mix chosen table-by-table:

- Oracle **Virtual Private Database (VPD/RLS)** policy on `TMS_TICKETS` and all child/business tables, calling into `PKG_TMS_DATA_ACCESS` for the predicate, **and**
- Every generated Interactive Report/Grid/chart is built on an **access-scoped APEX view** that also calls the same `PKG_TMS_DATA_ACCESS` predicate function — so visibility is enforced twice, by two independent layers, using one shared logic source.

**Rule for AI:** every generated report, chart, or LOV that touches a business table must be built on the access-scoped view — never a raw table source, and never a hand-written `WHERE ORG_ID = :G_ORG_ID` — because that misses hierarchy/delegation/scope nuances the engine already handles. The AI must not silently rely on VPD alone for one table and a manual view for another; the two-layer pattern applies uniformly, so a gap in one layer is still caught by the other.

---

## 8. Delegation Model

- `TMS_DELEGATIONS` records: `DELEGATOR_USER_ID`, `DELEGATE_USER_ID`, `ORG_ID`, `ROLE_ID` (optional — can delegate a whole role or specific Permissions), `START_DATE`, `END_DATE`, `STATUS`, `REASON`.
- While active, the delegate's resolved `G_PERMISSION_SET` includes the delegator's grants **for that org only**, added into the same union described in Section 5 — not a separate permission channel — and every action performed under delegation is audit-logged with both `ACTING_USER` and `ACTING_ON_BEHALF_OF`.
- Delegation never grants Permissions the delegate didn't already have access to request (i.e., an org can restrict which roles are delegable).
- Delegation is **single-hop only**: a delegate cannot re-delegate what they were delegated. `PKG_TMS_AUTH` must reject any attempt to create a delegation where the delegator's own grant is itself delegated (not directly owned).
- Expired delegations are deactivated by a scheduled job, not by client-side date checks.

---

## 9. Category/Global-vs-Organization Model

- `TMS_CATEGORIES` holds both **global categories** (`ORG_ID IS NULL`, visible to all orgs, maintained centrally) and **org-specific categories** (`ORG_ID` populated, maintained by that org's admins).
- Every ticket's category LOV shows: all global categories + that org's own categories, never another org's private categories.
- Global categories cannot be edited or deleted by an org admin — enforced by Authorization Scheme, not just UI hiding.
- New modules that introduce their own lookup data must follow this same Global/Org split pattern rather than inventing a new one.
- **Roles follow this identical pattern** (Section 5): Global roles are platform-defined and centrally maintained; Organization-specific roles are created and maintained only by that org's Admin, scoped by `ORG_ID` exactly like a Category.

---

## 10. Organization Onboarding

Standard onboarding sequence (a wizard-style APEX process, not ad-hoc SQL), supporting both Super-User-initiated and self-registration paths:

1. Create `TMS_ORGANIZATIONS` row with `STATUS = 'Onboarding'` (from a Super User action, or from an approved self-registration record that captured Organization Information + Initial Admin Information together).
2. Create the initial Admin's `TMS_USERS` + `TMS_USER_DETAILS` rows (if the person doesn't already exist as a user).
3. Create the `TMS_USER_ORGANIZATIONS` membership row — `ORGANIZATION_ID` is **pre-assigned** from the newly created Organization (the Admin is never shown an Organization LOV here), with `IS_PRIMARY = 'Y'` and a default Department context.
4. Create the `TMS_USER_ORGANIZATION_ROLES` row attaching the Org Admin role to that membership.
5. Seed default org-specific Departments and categories (copied from a template set, editable after).
6. Apply default SLA rules (copied from global defaults, editable after).
7. Flip `STATUS = 'Active'` only after the Admin confirms configuration — tickets cannot be created for an org still in `Onboarding`.
8. Every onboarding step is audit-logged individually (not just "org created").

---

## 11. Ticket Architecture and Lifecycle

**Core states:** `New → Assigned → In Progress → Pending (Customer/Internal) → Resolved → Closed`, plus `Reopened` (from Closed, time-boxed) and `Cancelled`.

- State transitions are governed by a transition table (`TMS_STATUS_TRANSITIONS`: from-status, to-status, required Function), not hardcoded IF/ELSE in page processes — this lets new modules reuse the same lifecycle engine.
- Every transition writes a row to `TMS_TICKET_HISTORY` (old status, new status, actor, timestamp, comment).
- `TICKET_ID` is a surrogate sequence-based key; a separate human-readable `TICKET_REF` (e.g., `ORGCODE-YYYY-000123`) is generated at insert.

---

## 12. Workflow and UAT Rules

- Workflow steps (assignment, approval, escalation) are driven by `TMS_WORKFLOW_RULES` keyed on Category + Org + Priority, not hardcoded per module.
- **UAT rule:** no module is promoted from Dev to UAT without: (a) at least one full lifecycle test per role involved, (b) a negative-path test proving unauthorized roles are blocked, (c) sign-off recorded against the module's entry in a `TMS_MODULE_REGISTER` tracking table.
- AI-generated modules must ship with a UAT checklist (see Section 30) alongside the code.

---

## 13. Closed-Ticket Immutability

- Once `STATUS = 'Closed'`, the ticket header, its details child rows, and its comments become **read-only at the database level** — enforced by a trigger on `TMS_TICKETS`/child tables that raises an error on UPDATE/DELETE unless the session is running under the dedicated `PKG_TMS_REOPEN.REOPEN_TICKET` procedure, which itself is Function-gated and fully audited.
- Generated pages must disable all DML controls (buttons, editable grid columns) whenever `STATUS = 'Closed'`, but this is a UX convenience only — the trigger is the real enforcement, and AI-generated code must never be the only line of defense here.

---

## 14. Audit Requirements

- Every INSERT/UPDATE/DELETE on a business table fires a row into `TMS_AUDIT_LOG`: table name, PK, action, old/new value (JSON), actor, timestamp, session org context.
- Audit logging is implemented once, centrally, via a generic trigger/package pattern (`PKG_TMS_AUDIT.LOG_CHANGE`) that new tables call from their own triggers — **AI must add the audit trigger call to any new table it creates**, never skip it because "the table seems minor."
- `TMS_AUDIT_LOG` itself is insert-only; no update/delete privilege exists for any application role.

---

## 15. SLA and Notification Architecture

- `TMS_SLA_RULES`: Org + Category + Priority → response-time and resolution-time targets.
- A scheduled job (`PKG_TMS_SLA_MONITOR`) evaluates open tickets against targets and raises breach flags — generated modules never compute SLA math themselves, they only display the flags/timestamps the engine produces.
- Notifications (email, in-app) are dispatched through one shared `PKG_TMS_NOTIFY.SEND` procedure with templated content per event type, logged to `TMS_NOTIFICATIONS_LOG`. New modules register new event types in a lookup table rather than writing their own `UTL_MAIL`/`APEX_MAIL` calls.

---

## 16. Integration Principles

- All outbound integrations go through ORDS-fronted PL/SQL APIs or `APEX_WEB_SERVICE` calls wrapped in a package per integration (`PKG_INT_<SYSTEM>`) — never inline `APEX_WEB_SERVICE.MAKE_REQUEST` calls inside a page process.
- Inbound integrations (e.g., ticket creation from email or another system) land in a staging table first, are validated, then processed by the same core ticket-creation package the UI uses — **one creation path, many entry points.**
- Every integration credential uses APEX Web Credentials, never hardcoded tokens/passwords in package bodies.

---

## 17. APEX Page-Generation Standards

- One module = one page group in a reserved numeric range (e.g., Tickets: 100–199, Organizations: 200–299, Reports: 900–999).
- Every list page = Interactive Report or Interactive Grid built on a view that already applies the Data Access predicate (Section 7) — never a raw table source.
- Every form page uses a page-level Process (`PKG_TMS_<MODULE>.SAVE`) rather than APEX's automatic DML process, so business rules and audit hooks run consistently.
- Breadcrumb + page template + region template must come from the shared Universal Theme customization — no per-page custom CSS unless routed through the shared static application files.

---

## 18. LOV Standards

- All LOVs are **named, shared SQL LOVs** (not inline query LOVs) so they can be reused and centrally updated: `LOV_TMS_ORG`, `LOV_TMS_CATEGORY_BY_ORG`, `LOV_TMS_STATUS`, `LOV_TMS_USER_BY_ORG_ROLE`, etc.
- Org-scoped LOVs always filter by `:G_ORG_ID` and, where relevant, the Global/Org category split (Section 9) — never return unfiltered full-table lists.
- Cascading LOVs (e.g., Sub-Category depends on Category) use APEX's native cascading LOV mechanism, not JavaScript-only filtering.

---

## 19. Button/Action Standards

- Every action button maps 1:1 to a Function+Action Permission pair checked both by an Authorization Scheme on the button **and** re-checked server-side inside the process it triggers (never trust client-side hiding alone).
- Standard button set per ticket form: `Save`, `Save and Close`, `Cancel`, `Reassign`, `Escalate`, `Close Ticket`, `Reopen` — buttons not applicable to the current status/role are hidden via server-side condition, not just disabled.
- Destructive actions (Cancel, Delete, Reopen-a-Closed-ticket) require a confirmation Dynamic Action dialog and are always audit-logged with a reason code.

---

## 20. Validation Standards

- Field-level validations live as declarative APEX Page Validations wherever possible; cross-field/business-rule validations live in the shared package (`PKG_TMS_<MODULE>.VALIDATE`) called from a single "Validate" process, so the same rule applies whether the record is saved from the UI or an integration.
- Every validation has a **specific, actionable** error message tied to the offending item (`apex_error.add_error` with `p_page_item_name`), never a generic "Error occurred."
- No validation may be bypassed for any role — if an Admin needs an override path, it is a distinct, audited Function (e.g., `SLA_OVERRIDE`), not a skipped validation.

---

## 21. Dynamic Action Standards

- Use Dynamic Actions for pure UI behavior only (show/hide, cascading LOVs, confirmation dialogs, client-side formatting) — **never** for business-rule enforcement or data writes that bypass the page process/PL/SQL API.
- Any Dynamic Action that calls an Ajax/PL;SQL process must call into the shared package layer, not embed inline SQL/PLSQL in the DA's "Execute Server-side Code" action.
- Name Dynamic Actions descriptively (`DA_Show_Reassign_Fields`, not `DA1`).

---

## 22. Authorization Scheme Standards

- One Authorization Scheme per Permission (`AUTH_TICKET_CREATE`, `AUTH_TICKET_CLOSE`, `AUTH_SLA_OVERRIDE`, …), each simply calling `PKG_TMS_AUTH.HAS_PERMISSION('TICKET', 'CREATE')` — schemes are thin wrappers, all logic lives in the package.
- Every new button, region, and page in a generated module must be wired to the matching existing scheme, or a newly registered Function/Action/Permission + scheme set — the AI is never allowed to leave a sensitive action with **no** authorization scheme attached.
- Page-level "must not be public" schemes are applied at the page level in addition to component-level schemes (defense in depth).

---

## 23. Reports and Data Visibility

- All reports (Interactive Reports, Grids, Dashboards, charts) source from views that already bake in the Data Access predicate — a report never has broader visibility than the underlying data engine allows, regardless of how it's built.
- Cross-organization aggregate reports (e.g., for a parent org, or platform admins) are a **distinct, explicitly authorized** report category (`AUTH_CROSS_ORG_REPORTING`), never a side-effect of a badly-scoped query.
- Exports (CSV/Excel/PDF) inherit the same row-level scope as the on-screen report — no "export everything" shortcut.

---

## 24. Theme/UI/Presentation Standards

**Base theme:** Oracle APEX Universal Theme (current release), built on the modern Redwood-style layout patterns — card-based regions, generous whitespace, soft elevation — not the older boxy/dense enterprise look. Generated pages must not introduce custom theme styles per page; any styling need is routed through the shared static application CSS file, never inline.

**Primary palette (Theme Roller — locked):** a deep navy-indigo primary (`~#1B2A4A`–`#22345C`) for headers, nav, and primary chrome, paired with a vivid cyan-teal accent (`~#06B6D4`–`#14B8A6`) for primary buttons, links, and active states, and a warm amber (`~#F59E0B`) used sparingly as a highlight color (key metrics, featured CTAs) — never as a status color, to keep it visually distinct. Content backgrounds sit on a soft neutral (`~#F8FAFC`), with white cards elevated on a subtle shadow rather than hard borders. This combination reads as modern SaaS product, not generic database-app chrome.

**Typography:** the Universal Theme's default system font stack, with a clear three-level hierarchy (page title → region title → body) and deliberately generous line-height/spacing — density is the enemy of "attractive," so lists and forms favor breathing room over cramming.

**Cards & elevation:** regions use rounded corners (`~8–12px`) and a soft drop-shadow for elevation instead of heavy borders; primary actions get a filled accent-color button, secondary actions stay outlined/text-only — one clear visual hierarchy of "what matters most on this page," never five equally-weighted buttons competing for attention.

**Dashboard/landing experience:** the org's home page opens on KPI cards (open tickets, SLA breaches today, avg. resolution time, tickets by priority) with icon + big number + small trend indicator, followed by a status-distribution chart (donut or bar) — not a bare Interactive Report as the first thing a user sees. Reports and forms remain the workhorse views underneath, but the entry point is designed, not defaulted.

**Login/branding screen:** a designed split-screen login (brand mark + short value copy on one side, the login form on the other) rather than APEX's bare default login page — this is the one screen every user sees before anything else, so it carries the most weight for "does this look like a serious product."

**Status badges** (Section 11 lifecycle) use one fixed semantic color map, applied via a shared CSS class (`.tms-status-new`, `.tms-status-assigned`, etc.) — never ad-hoc inline styles, never redefined per module:

| Status | Color |
|---|---|
| New | Neutral grey/blue |
| Assigned | Indigo |
| In Progress | Amber |
| Pending (Customer/Internal) | Yellow |
| Resolved | Teal/light-green |
| Closed | Solid green |
| Reopened | Red-orange |
| Cancelled | Muted grey |

**Priority badges** use a separate fixed map and must never reuse a status color: Critical = red, High = orange, Medium = amber, Low = blue-grey.

**SLA-breach indicator** is always red, regardless of the ticket's current status or priority color, so a breach is never visually confusable with a routine "in progress" amber.

**Branding is unified, not per-organization:** one polished theme applies identically across every tenant — no per-org re-skinning, no per-org accent color. This keeps the "amazing to look at" bar consistent for every organization instead of only as good as whichever org bothered to configure branding, and keeps the one-codebase principle (Section 1) intact. AI-generated modules must never introduce org-conditional styling.

**Iconography:** one consistent icon per module (nav + page headers), sourced from the Universal Theme's built-in icon library — no mixed icon sets.

**Motion:** subtle, restrained transitions only (hover states, panel expand/collapse, status-change confirmation) — enough to feel responsive and modern, never decorative animation that gets in the user's way.

**Accessibility:** WCAG 2.1 AA contrast minimums are enforced by the locked Theme Roller palette itself (not just checked after generation) — every generated page must additionally pass standard APEX accessibility checks (labels, contrast, keyboard navigation) before promotion. The richer palette above was chosen to stay AA-compliant, not in spite of it.

**Dark mode:** explicitly out of scope for v1 — deferred, not silently omitted. Introducing it later means defining a dark-safe variant for every status/priority color above, which is a standards-section change (Section 32) when it happens, not a per-page decision.

---

## 25. Reusable PL/SQL / Business-Engine Standards

- Every module's business logic lives in a package named `PKG_TMS_<MODULE>` with a consistent public interface shape: `CREATE_`, `UPDATE_`, `VALIDATE_`, `SAVE_`, `CHANGE_STATUS_`.
- Shared engines (`PKG_TMS_AUTH`, `PKG_TMS_DATA_ACCESS`, `PKG_TMS_AUDIT`, `PKG_TMS_NOTIFY`, `PKG_TMS_SLA_MONITOR`) are called, never re-implemented, by module packages.
- No business logic in anonymous PL/SQL blocks on pages beyond a single call into the module package.

---

## 26. What AI Is Allowed to Create

- New module tables (following Section 3 patterns) and their FKs into `TMS_TICKETS`/`TMS_ORGANIZATIONS`.
- New module PL/SQL packages following the Section 25 interface shape.
- New pages, regions, IRs/IGs, LOVs, Dynamic Actions, and buttons **within a reserved page-number range**, wired to existing or newly-registered Authorization Schemes.
- New Function/Action combinations registered in `TMS_FUNCTIONS`/`TMS_ACTIONS`/`TMS_PERMISSIONS`, and their corresponding thin Authorization Schemes.
- New Category, SLA rule, and Workflow rule *data* (not engine logic) for a new module.
- New notification event types (registered, not custom-coded mail calls).

---

## 27. What AI Is Absolutely Forbidden to Change

- `PKG_TMS_AUTH`, `PKG_TMS_DATA_ACCESS`, `PKG_TMS_AUDIT`, `PKG_TMS_NOTIFY`, `PKG_TMS_SLA_MONITOR` internals.
- Any VPD/RLS policy definition.
- The closed-ticket immutability trigger logic.
- `TMS_ORGANIZATIONS`, `TMS_DEPARTMENTS`, `TMS_USERS`, `TMS_USER_DETAILS`, `TMS_ROLES`, `TMS_ROLE_DETAILS`, `TMS_FUNCTIONS`, `TMS_ACTIONS`, `TMS_PERMISSIONS`, `TMS_ROLE_PERMISSIONS`, `TMS_USER_ORGANIZATIONS`, `TMS_USER_ORGANIZATION_ROLES`, `TMS_DELEGATIONS` table structures.
- The additive/union-only permission model (Section 5) — the AI must never introduce a deny/override permission or a session role-picker without an explicit change-control request (Section 32).
- Shared Application Items (`G_ORG_ID`, `G_ROLE_SET`, `G_PERMISSION_SET`, `G_SCOPE_TYPE`, `G_DELEGATED_FROM`) — read-only to generated code.
- The Universal Theme roller/global CSS.
- Anything that would let a page bypass the Data Access Resolution Engine (raw table-sourced reports on business data, hardcoded `WHERE ORG_ID = :X` filters, client-side-only security).
- The audit log table's structure or its insert-only privilege model.

---

## 28. Prompt Template for Every Future Module

```
You are generating a new module for the TMS platform.
Follow the TMS Master Blueprint in full — especially Sections 2, 17–25 (standards)
and Section 27 (forbidden changes). Do not re-implement or modify any shared
engine (Auth, Data Access, Audit, Notify, SLA Monitor).

Module name: <NAME>
Business purpose: <ONE PARAGRAPH>
New tables needed (if any): <LIST, following Section 3 mandatory columns>
New Function/Action/Permission combinations needed: <LIST — Function (capability), Action (verb), and what the resulting Permission gates>
Page range reserved: <e.g., 500-599>
Lifecycle/status model: <reuse Section 11 pattern, or state deltas>
Reports needed: <list, noting any cross-org reporting requirement>
Integration touchpoints (if any): <list>
Notification events needed: <list>

Deliverables:
1. DDL for new tables (with FK, audit trigger call, mandatory columns).
2. PKG_TMS_<MODULE> package spec + body (CREATE_/UPDATE_/VALIDATE_/SAVE_/CHANGE_STATUS_).
3. Authorization Scheme + Function registration script.
4. Page design: list page (IR/IG on access-scoped view), form page (buttons per
   Section 19, validations per Section 20, DAs per Section 21).
5. LOV definitions per Section 18.
6. UAT checklist per Section 30.
7. A short "What I did NOT touch" note confirming Section 27 items are untouched.
```

---

## 29. Implementation Sequence

1. **Foundation (manual, not AI-generated):** core schema, `PKG_TMS_AUTH`, `PKG_TMS_DATA_ACCESS`, `PKG_TMS_AUDIT`, VPD policies, session/context resolution, base theme.
2. **Organization module:** onboarding wizard, org admin pages.
3. **User/Role/Function admin module:** role assignment, delegation management UI.
4. **Category module:** global + org category management.
5. **Core Ticket module:** create/view/update/lifecycle, comments, attachments, history.
6. **SLA + Notification module:** rule configuration UI, monitor job wiring.
7. **Workflow/Approval module.**
8. **Reporting/Dashboard module** (including cross-org reporting for parent orgs).
9. **Integrations** (email-to-ticket, outbound webhooks, etc.).
10. Each subsequent domain-specific module (built by AI using the Section 28 template) plugs in after step 5, once the ticket core exists.

---

## 30. Testing and Acceptance Criteria

Per module, before promotion:

- [ ] Every Function-gated action tested as an authorized role (succeeds) and an unauthorized role (blocked, with correct message).
- [ ] Data Access Resolution verified: a user in Org A cannot see/edit/export Org B records via any page, report, or API in the module.
- [ ] Full lifecycle path tested end-to-end (create → all valid transitions → closed → reopen if applicable).
- [ ] Closed-ticket immutability verified at the DB level (attempt a direct UPDATE as a privileged role outside the reopen procedure — must fail).
- [ ] Audit log verified to contain a row for every write performed during testing.
- [ ] SLA breach flag verified against at least one deliberately-aged test record.
- [ ] Notifications verified sent (or logged) for each registered event type.
- [ ] Delegation path tested if the module exposes any delegable Function.
- [ ] Accessibility check passed.
- [ ] No orphaned Function/Authorization Scheme (every button/page has an active scheme).

---

## 31. Definition of Done

A module is **Done** only when:
1. All Section 30 acceptance criteria pass.
2. It has zero direct references to business tables outside the Data Access Resolution pattern.
3. It has zero business logic embedded in page processes/Dynamic Actions beyond calls into its `PKG_TMS_<MODULE>` package.
4. Its Functions, Authorization Schemes, and page range are registered in `TMS_MODULE_REGISTER`.
5. UAT sign-off is recorded against that register entry.
6. The "What I did NOT touch" confirmation (Section 28 deliverable 7) has been reviewed and matches Section 27.

---

## 32. Change-Control Mechanism

- This Blueprint document is versioned (semantic version at the top of the file, e.g., `v1.2`) and stored under source control alongside the APEX app export.
- Any change to Sections 2–16 (architecture/model sections) or Section 27 (forbidden list) requires a written change request, architect sign-off, and a version bump — AI Assistant must not be asked to "just adjust the architecture" inline in a module-generation prompt.
- Changes to Sections 17–25 (standards) can be proposed by any developer but require one reviewer approval before the Blueprint version is bumped.
- Every AI-generated module must declare, in its delivery notes, which Blueprint version it was generated against, so drift is traceable if the Blueprint later changes.
- A quarterly review checks generated modules against the current Blueprint version for standards drift.

---

*End of Blueprint — v1.5*
