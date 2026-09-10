CREATE OR REPLACE PACKAGE PKG_TMS_AUTH AS

    ----------------------------------------------------------------------
    -- Authentication
    ----------------------------------------------------------------------
    FUNCTION IS_AUTHENTICATED (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Current APEX user
    ----------------------------------------------------------------------
    FUNCTION GET_CURRENT_USER_ID
        RETURN NUMBER;


    ----------------------------------------------------------------------
    -- Super User authority
    --
    -- Super User is not restricted by Function / Action / Permission.
    -- Business rules, data integrity, workflow and audit still apply.
    ----------------------------------------------------------------------
    FUNCTION IS_SUPER_USER (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Organization scope
    ----------------------------------------------------------------------
    FUNCTION HAS_SCOPE (
        P_USER_ID IN NUMBER,
        P_ORG_ID  IN NUMBER
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Canonical authorization API
    --
    -- Function + Action = Permission
    --
    -- Current organization is resolved from G_ORG_ID.
    ----------------------------------------------------------------------
    FUNCTION HAS_PERMISSION (
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Explicit organization authorization
    --
    -- Useful for server-side business packages where organization
    -- context is explicitly supplied.
    ----------------------------------------------------------------------
    FUNCTION HAS_PERMISSION (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Combined authorization check
    ----------------------------------------------------------------------
    FUNCTION CAN_ACCESS (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN;


    ----------------------------------------------------------------------
    -- Raise error when authorization fails
    ----------------------------------------------------------------------
    PROCEDURE ASSERT_ACCESS (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER DEFAULT NULL
    );

END PKG_TMS_AUTH;
/

CREATE OR REPLACE PACKAGE BODY PKG_TMS_AUTH AS

    ----------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------

    C_SUPER_USER_ROLE_CODE CONSTANT VARCHAR2(100) := 'SUPER_USER';


    ----------------------------------------------------------------------
    -- Get current APEX user ID
    --
    -- APP_USER is the authenticated APEX login.
    -- TMS_USERS.LOGIN_NAME is the application user identity.
    ----------------------------------------------------------------------
    FUNCTION GET_CURRENT_USER_ID
        RETURN NUMBER
    IS
        L_LOGIN_NAME TMS_USERS.LOGIN_NAME%TYPE;
        L_USER_ID    TMS_USERS.USER_ID%TYPE;
    BEGIN

        L_LOGIN_NAME := SYS_CONTEXT(
                            'APEX$SESSION',
                            'APP_USER'
                        );

        IF L_LOGIN_NAME IS NULL THEN
            RETURN NULL;
        END IF;


        SELECT USER_ID
          INTO L_USER_ID
          FROM TMS_USERS
         WHERE UPPER(LOGIN_NAME) = UPPER(TRIM(L_LOGIN_NAME));

        RETURN L_USER_ID;

    EXCEPTION

        WHEN NO_DATA_FOUND THEN
            RETURN NULL;

        WHEN TOO_MANY_ROWS THEN
            RETURN NULL;

        WHEN OTHERS THEN
            RETURN NULL;

    END GET_CURRENT_USER_ID;


    ----------------------------------------------------------------------
    -- Check whether the user exists and is active.
    ----------------------------------------------------------------------
    FUNCTION IS_AUTHENTICATED (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER;
    BEGIN

        IF P_USER_ID IS NULL THEN
            RETURN FALSE;
        END IF;


        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USERS
         WHERE USER_ID = P_USER_ID
           AND ACCOUNT_STATUS = 'ACTIVE';


        RETURN L_COUNT > 0;

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END IS_AUTHENTICATED;


    ----------------------------------------------------------------------
    -- Determine whether the user is the Super User.
    --
    -- IMPORTANT:
    --
    -- Super User is identified through the dedicated SUPER_USER
    -- system role attached to the user's membership.
    --
    -- The role is an identity / authority marker.
    -- It is NOT used as a permission requirement.
    --
    -- Once identified as Super User, HAS_PERMISSION returns TRUE
    -- without checking Function / Action / Permission rows.
    --
    -- Business rules are still enforced by the business packages.
    ----------------------------------------------------------------------
    FUNCTION IS_SUPER_USER (
        P_USER_ID IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER;
    BEGIN

        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ORGANIZATIONS UO
               JOIN TMS_USER_ORGANIZATION_ROLES UOR
                 ON UOR.USER_ORG_ID = UO.USER_ORG_ID
               JOIN TMS_ROLES R
                 ON R.ROLE_ID = UOR.ROLE_ID
               JOIN TMS_ROLE_DETAILS RD
                 ON RD.ROLE_ID = R.ROLE_ID
         WHERE UO.USER_ID = P_USER_ID
           AND UO.MEMBERSHIP_STATUS = 'ACTIVE'
           AND UOR.STATUS = 'ACTIVE'
           AND R.STATUS = 'ACTIVE'
           AND RD.IS_SYSTEM_ROLE = 'Y'
           AND UPPER(R.ROLE_CODE) = C_SUPER_USER_ROLE_CODE
           AND UO.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UO.EFFECTIVE_TO IS NULL
                   OR UO.EFFECTIVE_TO >= TRUNC(SYSDATE)
               )
           AND UOR.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UOR.EFFECTIVE_TO IS NULL
                   OR UOR.EFFECTIVE_TO >= TRUNC(SYSDATE)
               );


        RETURN L_COUNT > 0;

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END IS_SUPER_USER;


    ----------------------------------------------------------------------
    -- Check whether user has an active membership in an organization.
    --
    -- This is the organization boundary check.
    --
    -- Super User is not automatically granted a customer organization
    -- membership merely because the user is Super User.
    --
    -- Therefore even Super User business operations that specifically
    -- require an organization context can still validate that context.
    ----------------------------------------------------------------------
    FUNCTION HAS_SCOPE (
        P_USER_ID IN NUMBER,
        P_ORG_ID  IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER;
    BEGIN

        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        IF P_ORG_ID IS NULL THEN
            RETURN FALSE;
        END IF;


        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ORGANIZATIONS UO
               JOIN TMS_ORGANIZATIONS O
                 ON O.ORG_ID = UO.ORG_ID
         WHERE UO.USER_ID = P_USER_ID
           AND UO.ORG_ID = P_ORG_ID
           AND UO.MEMBERSHIP_STATUS = 'ACTIVE'
           AND O.STATUS = 'ACTIVE'
           AND UO.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UO.EFFECTIVE_TO IS NULL
                   OR UO.EFFECTIVE_TO >= TRUNC(SYSDATE)
               );


        RETURN L_COUNT > 0;

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END HAS_SCOPE;


    ----------------------------------------------------------------------
    -- Resolve G_ORG_ID from APEX session.
    --
    -- G_ORG_ID is the application organization context.
    --
    -- If no context exists:
    --   1. Super User may operate without an organization-specific
    --      permission restriction.
    --   2. Normal users cannot pass organization authorization.
    ----------------------------------------------------------------------
    FUNCTION GET_CURRENT_ORG_ID
        RETURN NUMBER
    IS
        L_ORG_ID VARCHAR2(100);
    BEGIN

        L_ORG_ID := APEX_UTIL.GET_SESSION_STATE('G_ORG_ID');

        IF L_ORG_ID IS NULL THEN
            RETURN NULL;
        END IF;


        RETURN TO_NUMBER(L_ORG_ID);

    EXCEPTION

        WHEN VALUE_ERROR THEN
            RETURN NULL;

        WHEN OTHERS THEN
            RETURN NULL;

    END GET_CURRENT_ORG_ID;


    ----------------------------------------------------------------------
    -- Internal permission check.
    --
    -- Permission resolution:
    --
    -- USER
    --   ↓
    -- USER ORGANIZATION
    --   ↓
    -- USER ORGANIZATION ROLE
    --   ↓
    -- ROLE
    --   ↓
    -- ROLE PERMISSION
    --   ↓
    -- PERMISSION
    --   ↓
    -- FUNCTION + ACTION
    --
    -- Global roles (ORG_ID IS NULL) are valid.
    -- Organization roles are valid only for the selected organization.
    ----------------------------------------------------------------------
    FUNCTION HAS_PERMISSION_INTERNAL (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER
    ) RETURN BOOLEAN
    IS
        L_COUNT NUMBER;
    BEGIN

        ------------------------------------------------------------------
        -- Authentication
        ------------------------------------------------------------------
        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- Function / Action are mandatory.
        ------------------------------------------------------------------
        IF P_FUNCTION_CODE IS NULL
           OR P_ACTION_CODE IS NULL
        THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- Super User bypasses permission restriction.
        --
        -- This does NOT bypass business rules.
        ------------------------------------------------------------------
        IF IS_SUPER_USER(P_USER_ID) THEN
            RETURN TRUE;
        END IF;


        ------------------------------------------------------------------
        -- Normal user requires an organization context.
        ------------------------------------------------------------------
        IF P_ORG_ID IS NULL THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- User must actually belong to the organization.
        ------------------------------------------------------------------
        IF NOT HAS_SCOPE(
                   P_USER_ID => P_USER_ID,
                   P_ORG_ID  => P_ORG_ID
               )
        THEN
            RETURN FALSE;
        END IF;


        ------------------------------------------------------------------
        -- Permission resolution.
        --
        -- Global role:
        --     R.ORG_ID IS NULL
        --
        -- Organization role:
        --     R.ORG_ID = selected organization
        --
        -- Permission is additive.
        ------------------------------------------------------------------
        SELECT COUNT(*)
          INTO L_COUNT
          FROM TMS_USER_ORGANIZATIONS UO

               JOIN TMS_USER_ORGANIZATION_ROLES UOR
                 ON UOR.USER_ORG_ID = UO.USER_ORG_ID

               JOIN TMS_ROLES R
                 ON R.ROLE_ID = UOR.ROLE_ID

               JOIN TMS_ROLE_PERMISSIONS RP
                 ON RP.ROLE_ID = R.ROLE_ID

               JOIN TMS_PERMISSIONS P
                 ON P.PERMISSION_ID = RP.PERMISSION_ID

               JOIN TMS_FUNCTIONS F
                 ON F.FUNCTION_ID = P.FUNCTION_ID

               JOIN TMS_ACTIONS A
                 ON A.ACTION_ID = P.ACTION_ID

         WHERE UO.USER_ID = P_USER_ID
           AND UO.ORG_ID = P_ORG_ID

           AND UO.MEMBERSHIP_STATUS = 'ACTIVE'

           AND UO.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UO.EFFECTIVE_TO IS NULL
                   OR UO.EFFECTIVE_TO >= TRUNC(SYSDATE)
               )

           AND UOR.STATUS = 'ACTIVE'

           AND UOR.EFFECTIVE_FROM <= TRUNC(SYSDATE)
           AND (
                   UOR.EFFECTIVE_TO IS NULL
                   OR UOR.EFFECTIVE_TO >= TRUNC(SYSDATE)
               )

           AND R.STATUS = 'ACTIVE'

           AND (
                   R.ORG_ID IS NULL
                   OR R.ORG_ID = P_ORG_ID
               )

           AND UPPER(F.FUNCTION_CODE)
                   = UPPER(TRIM(P_FUNCTION_CODE))

           AND UPPER(A.ACTION_CODE)
                   = UPPER(TRIM(P_ACTION_CODE));


        RETURN L_COUNT > 0;

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END HAS_PERMISSION_INTERNAL;


    ----------------------------------------------------------------------
    -- Canonical authorization API.
    --
    -- Uses current authenticated APEX user and G_ORG_ID.
    ----------------------------------------------------------------------
    FUNCTION HAS_PERMISSION (
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2
    ) RETURN BOOLEAN
    IS
        L_USER_ID NUMBER;
        L_ORG_ID  NUMBER;
    BEGIN

        L_USER_ID := GET_CURRENT_USER_ID;
        L_ORG_ID  := GET_CURRENT_ORG_ID;


        RETURN HAS_PERMISSION_INTERNAL(
                   P_USER_ID       => L_USER_ID,
                   P_FUNCTION_CODE => P_FUNCTION_CODE,
                   P_ACTION_CODE   => P_ACTION_CODE,
                   P_ORG_ID        => L_ORG_ID
               );

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END HAS_PERMISSION;


    ----------------------------------------------------------------------
    -- Explicit-user / explicit-organization authorization API.
    --
    -- Used by server-side PL/SQL packages when the user and organization
    -- are already known.
    ----------------------------------------------------------------------
    FUNCTION HAS_PERMISSION (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER
    ) RETURN BOOLEAN
    IS
    BEGIN

        RETURN HAS_PERMISSION_INTERNAL(
                   P_USER_ID       => P_USER_ID,
                   P_FUNCTION_CODE => P_FUNCTION_CODE,
                   P_ACTION_CODE   => P_ACTION_CODE,
                   P_ORG_ID        => P_ORG_ID
               );

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END HAS_PERMISSION;


    ----------------------------------------------------------------------
    -- Combined authorization check.
    ----------------------------------------------------------------------
    FUNCTION CAN_ACCESS (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        L_ORG_ID NUMBER;
    BEGIN

        ------------------------------------------------------------------
        -- If organization was supplied, use it.
        -- Otherwise resolve current application context.
        ------------------------------------------------------------------
        L_ORG_ID := P_ORG_ID;


        IF L_ORG_ID IS NULL THEN
            L_ORG_ID := GET_CURRENT_ORG_ID;
        END IF;


        RETURN HAS_PERMISSION_INTERNAL(
                   P_USER_ID       => P_USER_ID,
                   P_FUNCTION_CODE => P_FUNCTION_CODE,
                   P_ACTION_CODE   => P_ACTION_CODE,
                   P_ORG_ID        => L_ORG_ID
               );

    EXCEPTION

        WHEN OTHERS THEN
            RETURN FALSE;

    END CAN_ACCESS;


    ----------------------------------------------------------------------
    -- Raise an application error if authorization fails.
    --
    -- This procedure is intended for server-side business packages.
    --
    -- IMPORTANT:
    -- Super User passes authorization restriction here, but the calling
    -- business package MUST still execute its own business validations.
    ----------------------------------------------------------------------
    PROCEDURE ASSERT_ACCESS (
        P_USER_ID       IN NUMBER,
        P_FUNCTION_CODE IN VARCHAR2,
        P_ACTION_CODE   IN VARCHAR2,
        P_ORG_ID        IN NUMBER DEFAULT NULL
    )
    IS
        L_ORG_ID NUMBER;
    BEGIN

        ------------------------------------------------------------------
        -- Authentication
        ------------------------------------------------------------------
        IF NOT IS_AUTHENTICATED(P_USER_ID) THEN

            RAISE_APPLICATION_ERROR(
                -20001,
                'TMS-SECURITY-001: User is not authenticated or is inactive.'
            );

        END IF;


        ------------------------------------------------------------------
        -- Function required
        ------------------------------------------------------------------
        IF P_FUNCTION_CODE IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20002,
                'TMS-SECURITY-002: Function code is required.'
            );

        END IF;


        ------------------------------------------------------------------
        -- Action required
        ------------------------------------------------------------------
        IF P_ACTION_CODE IS NULL THEN

            RAISE_APPLICATION_ERROR(
                -20003,
                'TMS-SECURITY-003: Action code is required.'
            );

        END IF;


        ------------------------------------------------------------------
        -- Resolve organization context.
        ------------------------------------------------------------------
        L_ORG_ID := P_ORG_ID;

        IF L_ORG_ID IS NULL THEN
            L_ORG_ID := GET_CURRENT_ORG_ID;
        END IF;


        ------------------------------------------------------------------
        -- Authorization
        ------------------------------------------------------------------
        IF NOT HAS_PERMISSION_INTERNAL(
                   P_USER_ID       => P_USER_ID,
                   P_FUNCTION_CODE => P_FUNCTION_CODE,
                   P_ACTION_CODE   => P_ACTION_CODE,
                   P_ORG_ID        => L_ORG_ID
               )
        THEN

            RAISE_APPLICATION_ERROR(
                -20004,
                'TMS-SECURITY-004: User is not authorized for '
                || UPPER(TRIM(P_FUNCTION_CODE))
                || '.'
                || UPPER(TRIM(P_ACTION_CODE))
            );

        END IF;


        ------------------------------------------------------------------
        -- Authorization successful.
        --
        -- Business validation remains responsibility of the calling
        -- business package.
        ------------------------------------------------------------------
        NULL;

    END ASSERT_ACCESS;


END PKG_TMS_AUTH;
/