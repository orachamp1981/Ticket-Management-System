/*
Access-scoped views must call the frozen PKG_TMS_DATA_ACCESS predicate.
The exact predicate API is intentionally not invented in this foundation.
*/

CREATE OR REPLACE VIEW vw_tms_ticket_base AS
SELECT
  t.ticket_id,
  t.org_id,
  t.ticket_ref,
  t.subject,
  t.priority,
  t.status,
  t.category_id,
  t.requester_user_id,
  t.assigned_user_id,
  t.opened_date,
  t.resolved_date,
  t.closed_date,
  t.response_breached,
  t.resolution_breached,
  t.created_date,
  t.updated_date
FROM tms_tickets t;
