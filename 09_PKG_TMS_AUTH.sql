CREATE OR REPLACE PACKAGE PKG_TMS_AUTH AS

    FUNCTION IS_AUTHENTICATED (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION HAS_CAPABILITY (
        P_USER_ID      IN NUMBER,
        P_CAPABILITY   IN VARCHAR2
    ) RETURN BOOLEAN;

    FUNCTION HAS_ACTION (
        P_USER_ID      IN NUMBER,
        P_ACTION       IN VARCHAR2,
        P_ORG_ID       IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN;

    FUNCTION HAS_SCOPE (
        P_USER_ID          IN NUMBER,
        P_ORG_ID           IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION CAN_ACCESS (
        P_USER_ID      IN NUMBER,
        P_ACTION       IN VARCHAR2,
        P_ORG_ID       IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN;

END PKG_TMS_AUTH;
/

CREATE OR REPLACE PACKAGE BODY PKG_TMS_AUTH AS

    ----------------------------------------------------------------------
    -- PRIVATE FUNCTIONS
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- Check whether the user is a Super User
    ----------------------------------------------------------------------
    FUNCTION IS_SUPER_USER (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER := 0;
    BEGIN

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USERS
         WHERE USER_ID   = P_USER_ID
           AND STATUS    = 'ACTIVE'
           AND USER_TYPE = 'SUPER_USER';

        RETURN L_COUNT > 0;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;

        WHEN OTHERS THEN
            RETURN FALSE;
    END IS_SUPER_USER;


    ----------------------------------------------------------------------
    -- Check whether the user has the requested action through
    -- one of his/her assigned roles.
    --
    -- USER
    --   ↓
    -- USER_ROLE
    --   ↓
    -- ROLE
    --   ↓
    -- ROLE_CAPABILITY
    --   ↓
    -- CAPABILITY
    --   ↓
    -- ACTION
    ----------------------------------------------------------------------
    FUNCTION HAS_ACTION_CAPABILITY (
        P_USER_ID IN NUMBER,
        P_ACTION  IN VARCHAR2
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER := 0;
    BEGIN

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ROLES UR
               JOIN TMS_ROLE_CAPABILITIES RC
                 ON RC.ROLE_ID = UR.ROLE_ID
               JOIN TMS_CAPABILITIES C
                 ON C.CAPABILITY_ID = RC.CAPABILITY_ID
               JOIN TMS_ACTIONS A
                 ON A.CAPABILITY_ID = C.CAPABILITY_ID
         WHERE UR.USER_ID = P_USER_ID
           AND A.ACTION_CODE = UPPER(TRIM(P_ACTION))
           AND NVL(UR.STATUS, 'ACTIVE') = 'ACTIVE'
           AND NVL(RC.STATUS, 'ACTIVE') = 'ACTIVE'
           AND NVL(C.STATUS, 'ACTIVE') = 'ACTIVE'
           AND NVL(A.STATUS, 'ACTIVE') = 'ACTIVE';

        RETURN L_COUNT > 0;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;

        WHEN OTHERS THEN
            RETURN FALSE;
    END HAS_ACTION_CAPABILITY;



    ----------------------------------------------------------------------
    -- PUBLIC FUNCTIONS
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- Check whether the user exists and is active.
    ----------------------------------------------------------------------
    FUNCTION IS_AUTHENTICATED (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER := 0;
    BEGIN

        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USERS
         WHERE USER_ID = P_USER_ID
           AND STATUS  = 'ACTIVE';

        RETURN L_COUNT > 0;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;

        WHEN OTHERS THEN
            RETURN FALSE;
    END IS_AUTHENTICATED;



    ----------------------------------------------------------------------
    -- Check whether user possesses a specific capability.
    ----------------------------------------------------------------------
    FUNCTION HAS_CAPABILITY (
        P_USER_ID    IN NUMBER,
        P_CAPABILITY IN VARCHAR2
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER := 0;
    BEGIN

        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ROLES UR
               JOIN TMS_ROLE_CAPABILITIES RC
                 ON RC.ROLE_ID = UR.ROLE_ID
               JOIN TMS_CAPABILITIES C
                 ON C.CAPABILITY_ID = RC.CAPABILITY_ID
         WHERE UR.USER_ID = P_USER_ID
           AND C.CAPABILITY_CODE = UPPER(TRIM(P_CAPABILITY))
           AND NVL(UR.STATUS, 'ACTIVE') = 'ACTIVE'
           AND NVL(RC.STATUS, 'ACTIVE') = 'ACTIVE'
           AND NVL(C.STATUS, 'ACTIVE') = 'ACTIVE';

        RETURN L_COUNT > 0;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;

        WHEN OTHERS THEN
            RETURN FALSE;
    END HAS_CAPABILITY;



    ----------------------------------------------------------------------
    -- Check whether user has access to an organization.
    --
    -- Super User:
    --     System-wide organization scope.
    --
    -- Normal User:
    --     Must have an active explicit scope.
    ----------------------------------------------------------------------
    FUNCTION HAS_SCOPE (
        P_USER_ID IN NUMBER,
        P_ORG_ID  IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER := 0;
    BEGIN

        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        IF P_ORG_ID IS NULL THEN
            RETURN FALSE;
        END IF;


        IF IS_SUPER_USER(P_USER_ID) THEN
            RETURN TRUE;
        END IF;


        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_SCOPE US
         WHERE US.USER_ID = P_USER_ID
           AND US.ORG_ID  = P_ORG_ID
           AND NVL(US.STATUS, 'ACTIVE') = 'ACTIVE';


        RETURN L_COUNT > 0;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;

        WHEN OTHERS THEN
            RETURN FALSE;
    END HAS_SCOPE;



    ----------------------------------------------------------------------
    -- Combined authorization check.
    --
    -- Sequence:
    --
    -- 1. Authentication
    -- 2. Super User
    -- 3. Action capability
    -- 4. Organization scope
    ----------------------------------------------------------------------
    FUNCTION CAN_ACCESS (
        P_USER_ID IN NUMBER,
        P_ACTION  IN VARCHAR2,
        P_ORG_ID  IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN
    IS
    BEGIN

        ------------------------------------------------------------------
        -- USER MUST BE ACTIVE
        ------------------------------------------------------------------
        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- ACTION IS REQUIRED
        ------------------------------------------------------------------
        IF P_ACTION IS NULL THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- SUPER USER
        --
        -- System-level authority.
        ------------------------------------------------------------------
        IF IS_SUPER_USER(P_USER_ID) THEN
            RETURN TRUE;
        END IF;


        ------------------------------------------------------------------
        -- ACTION / CAPABILITY CHECK
        ------------------------------------------------------------------
        IF NOT HAS_ACTION_CAPABILITY(
                   P_USER_ID => P_USER_ID,
                   P_ACTION  => P_ACTION
               )
        THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- ORGANIZATION SCOPE
        --
        -- If the operation is organization-specific, scope is mandatory.
        ------------------------------------------------------------------
        IF P_ORG_ID IS NOT NULL THEN

            IF NOT HAS_SCOPE(
                       P_USER_ID => P_USER_ID,
                       P_ORG_ID  => P_ORG_ID
                   )
            THEN
                RETURN FALSE;
            END IF;

        END IF;


        ------------------------------------------------------------------
        -- ALL SECURITY CHECKS PASSED
        ------------------------------------------------------------------
        RETURN TRUE;


    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;

    END CAN_ACCESS;



    ----------------------------------------------------------------------
    -- Raise an application error if authorization fails.
    --
    -- This is the preferred procedure for business packages because
    -- execution stops immediately when access is denied.
    ----------------------------------------------------------------------
    PROCEDURE ASSERT_ACCESS (
        P_USER_ID IN NUMBER,
        P_ACTION  IN VARCHAR2,
        P_ORG_ID  IN NUMBER DEFAULT NULL
    )
    IS
    BEGIN

        ------------------------------------------------------------------
        -- AUTHENTICATION
        ------------------------------------------------------------------
        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN

            RAISE_APPLICATION_ERROR(
                -20001,
                'TMS-SECURITY-001: User is not authenticated or inactive.'
            );

        END IF;


        ------------------------------------------------------------------
        -- ACTION REQUIRED
        ------------------------------------------------------------------
        IF P_ACTION IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20002,
                'TMS-SECURITY-002: Security action is required.'
            );

        END IF;


        ------------------------------------------------------------------
        -- SUPER USER
        ------------------------------------------------------------------
        IF IS_SUPER_USER(P_USER_ID) THEN
            RETURN;
        END IF;


        ------------------------------------------------------------------
        -- ACTION / CAPABILITY
        ------------------------------------------------------------------
        IF NOT HAS_ACTION_CAPABILITY(
                   P_USER_ID => P_USER_ID,
                   P_ACTION  => P_ACTION
               )
        THEN

            RAISE_APPLICATION_ERROR(
                -20003,
                'TMS-SECURITY-003: User is not authorized for action '
                || UPPER(TRIM(P_ACTION))
            );

        END IF;


        ------------------------------------------------------------------
        -- ORGANIZATION SCOPE
        ------------------------------------------------------------------
        IF P_ORG_ID IS NOT NULL THEN

            IF NOT HAS_SCOPE(
                       P_USER_ID => P_USER_ID,
                       P_ORG_ID  => P_ORG_ID
                   )
            THEN

                RAISE_APPLICATION_ERROR(
                    -20004,
                    'TMS-SECURITY-004: User is outside the permitted '
                    || 'organization scope.'
                );

            END IF;

        END IF;


        ------------------------------------------------------------------
        -- AUTHORIZATION SUCCESSFUL
        ------------------------------------------------------------------
        NULL;

    END ASSERT_ACCESS;


END PKG_TMS_AUTH;
/