/*
====================================================================
TMS ACCESS-SCOPED VIEWS
Blueprint Version : v1.5

RULES
--------------------------------------------------------------------
1. Business data must never be exposed through a raw APEX view.
2. Row-level visibility is resolved by PKG_TMS_DATA_ACCESS.
3. No hardcoded:
       WHERE ORG_ID = :G_ORG_ID
4. Super User access is resolved by the data-access engine.
5. Organization hierarchy/access rules remain centralized.
6. VPD/RLS will provide the second enforcement layer.
7. TMS_COST_CENTRES is intentionally outside the data-access engine.
====================================================================
*/


/* ================================================================
   TICKET BASE VIEW
   ================================================================

   This is the standard access-scoped source for:

       - Interactive Reports
       - Interactive Grids
       - Charts
       - Dashboards
       - Ticket LOV/report regions

   The view does NOT implement its own authorization rules.

   PKG_TMS_DATA_ACCESS is the single source of row-level access.
   ================================================================ */

CREATE OR REPLACE VIEW VW_TMS_TICKET_BASE AS
SELECT
    T.TICKET_ID,
    T.ORG_ID,
    T.TICKET_REF,
    T.SUBJECT,
    T.DESCRIPTION,
    T.PRIORITY,
    T.STATUS,
    T.CATEGORY_ID,
    T.REQUESTER_USER_ID,
    T.ASSIGNED_USER_ID,
    T.ASSIGNED_DEPARTMENT_ID,
    T.OPENED_DATE,
    T.RESOLVED_DATE,
    T.CLOSED_DATE,
    T.SLA_RESPONSE_DUE,
    T.SLA_RESOLUTION_DUE,
    T.RESPONSE_BREACHED,
    T.RESOLUTION_BREACHED,
    T.CREATED_BY,
    T.CREATED_DATE,
    T.UPDATED_BY,
    T.UPDATED_DATE,
    T.RECORD_VERSION
FROM
    TMS_TICKETS T
WHERE
    PKG_TMS_DATA_ACCESS.CAN_ACCESS_ORG(T.ORG_ID) = 1;