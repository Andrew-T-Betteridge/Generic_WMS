import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { db } from "./db.js";
import { requireIdentity, type AuthIdentity } from "./auth.js";

export type AdminPrincipal = AuthIdentity & {
  adminUserId: string | null;
  displayName: string | null;
  localRoles: string[];
  permissions: string[];
  bootstrap: boolean;
};

function codeOf(error: unknown) {
  return String((error as Error)?.message ?? error).split(":")[0];
}

function legacyAdmin(identity: AuthIdentity) {
  const adminRole = (process.env.ADMIN_ROLE ?? "admin").toLowerCase();
  return identity.roles.some((r) => r.toLowerCase() === adminRole);
}

async function loadLocalPrincipal(
  clientId: string,
  identity: AuthIdentity,
): Promise<AdminPrincipal | null> {
  let result = await db.query(
    `select ADMIN_USER_ID,EMAIL,DISPLAY_NAME,ACTIVE,IS_OWNER,AUTH_PROVIDER,AUTH_SUBJECT
       from config.ADMIN_USER
      where CLIENT_ID=$1
        and AUTH_PROVIDER=$2
        and AUTH_SUBJECT=$3
      limit 1`,
    [clientId, identity.provider, identity.subject],
  );

  if (!result.rowCount && identity.emailVerified) {
    const byEmail = await db.query(
      `select ADMIN_USER_ID,EMAIL,DISPLAY_NAME,ACTIVE,IS_OWNER,AUTH_PROVIDER,AUTH_SUBJECT
         from config.ADMIN_USER
        where CLIENT_ID=$1
          and LOWER(EMAIL)=LOWER($2)
        limit 1`,
      [clientId, identity.email],
    );

    const candidate = byEmail.rows[0];
    if (
      candidate &&
      (!candidate.auth_subject ||
        (candidate.auth_provider === identity.provider &&
          candidate.auth_subject === identity.subject))
    ) {
      await db.query(
        `update config.ADMIN_USER
            set AUTH_PROVIDER=$3,
                AUTH_SUBJECT=$4,
                ACCOUNT_ID=$5::uuid,
                LAST_LOGIN_DSTAMP=now(),
                LAST_UPDATE_DSTAMP=now()
          where CLIENT_ID=$1
            and ADMIN_USER_ID=$2::uuid`,
        [
          clientId,
          candidate.admin_user_id,
          identity.provider,
          identity.subject,
          identity.accountId,
        ],
      );
      result = byEmail;
      result.rows[0].auth_provider = identity.provider;
      result.rows[0].auth_subject = identity.subject;
    }
  }

  if (!result.rowCount) return null;

  const user = result.rows[0];
  if (!user.active) throw new Error("ADMIN_USER_DISABLED");

  await db.query(
    `update config.ADMIN_USER
        set ACCOUNT_ID=COALESCE(ACCOUNT_ID,$3::uuid),
            LAST_LOGIN_DSTAMP=now(),
            LAST_UPDATE_DSTAMP=now()
      where CLIENT_ID=$1
        and ADMIN_USER_ID=$2::uuid`,
    [clientId, user.admin_user_id, identity.accountId],
  );

  const access = await db.query(
    `select
        COALESCE(array_agg(distinct ur.ROLE_CODE)
          filter(where ur.ROLE_CODE is not null),'{}') as roles,
        COALESCE(array_agg(distinct rp.PERMISSION_CODE)
          filter(where rp.PERMISSION_CODE is not null),'{}') as permissions
       from config.ADMIN_USER_ROLE ur
       join config.ADMIN_ROLE r
         on r.CLIENT_ID=ur.CLIENT_ID
        and r.ROLE_CODE=ur.ROLE_CODE
        and r.ACTIVE=true
       left join config.ADMIN_ROLE_PERMISSION rp
         on rp.CLIENT_ID=ur.CLIENT_ID
        and rp.ROLE_CODE=ur.ROLE_CODE
      where ur.CLIENT_ID=$1
        and ur.ADMIN_USER_ID=$2::uuid`,
    [clientId, user.admin_user_id],
  );

  return {
    ...identity,
    adminUserId: user.admin_user_id,
    displayName: user.display_name ?? null,
    localRoles: access.rows[0]?.roles ?? [],
    permissions: access.rows[0]?.permissions ?? [],
    bootstrap: false,
  };
}

export async function resolveAdminPrincipal(
  req: FastifyRequest,
  clientId: string,
): Promise<AdminPrincipal> {
  const identity = await requireIdentity(req, clientId);
  const local = await loadLocalPrincipal(clientId, identity);
  if (local) return local;

  if (legacyAdmin(identity)) {
    return {
      ...identity,
      adminUserId: null,
      displayName: null,
      localRoles: [],
      permissions: ["*"],
      bootstrap: true,
    };
  }

  throw new Error("ADMIN_ACCESS_REQUIRED");
}

export async function requirePermission(
  req: FastifyRequest,
  clientId: string,
  permission: string,
): Promise<AdminPrincipal> {
  const principal = await resolveAdminPrincipal(req, clientId);
  if (
    !principal.permissions.includes("*") &&
    !principal.permissions.includes(permission)
  ) {
    throw new Error(`PERMISSION_REQUIRED:${permission}`);
  }
  return principal;
}

export async function auditAdminChange(
  clientId: string,
  principal: AdminPrincipal,
  entityType: string,
  entityId: string,
  action: string,
  beforeData: unknown,
  afterData: unknown,
  reason?: string | null,
) {
  await db.query(
    `insert into audit.AUDIT_EVENT
      (CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,BEFORE_DATA,AFTER_DATA)
     values($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)`,
    [
      clientId,
      entityType,
      entityId,
      action,
      principal.email,
      reason ?? null,
      beforeData == null ? null : JSON.stringify(beforeData),
      afterData == null ? null : JSON.stringify(afterData),
    ],
  );
}

function replyAdminError(reply: FastifyReply, error: unknown) {
  const code = codeOf(error);
  const status =
    code === "AUTHENTICATION_REQUIRED"
      ? 401
      : code === "ADMIN_USER_NOT_FOUND"
        ? 404
        : code.endsWith("_NOT_FOUND")
          ? 404
          : code.includes("ALREADY_EXISTS")
            ? 409
            : code.startsWith("INVALID_") || code.endsWith("_REQUIRED")
              ? 400
              : 403;
  return reply.code(status).send({ error: code });
}

async function roleCodesExist(clientId: string, roles: string[]) {
  if (!roles.length) return true;
  const result = await db.query(
    `select count(*)::int as count
       from config.ADMIN_ROLE
      where CLIENT_ID=$1
        and ROLE_CODE=any($2::varchar[])
        and ACTIVE=true`,
    [clientId, roles],
  );
  return Number(result.rows[0]?.count ?? 0) === new Set(roles).size;
}

async function activeOwnerCount(clientId: string) {
  const result = await db.query(
    `select count(distinct u.ADMIN_USER_ID)::int as count
       from config.ADMIN_USER u
       join config.ADMIN_USER_ROLE ur
         on ur.CLIENT_ID=u.CLIENT_ID
        and ur.ADMIN_USER_ID=u.ADMIN_USER_ID
      where u.CLIENT_ID=$1
        and u.ACTIVE=true
        and ur.ROLE_CODE='OWNER'`,
    [clientId],
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function isActiveOwner(clientId: string, userId: string) {
  const result = await db.query(
    `select 1
       from config.ADMIN_USER u
       join config.ADMIN_USER_ROLE ur
         on ur.CLIENT_ID=u.CLIENT_ID
        and ur.ADMIN_USER_ID=u.ADMIN_USER_ID
      where u.CLIENT_ID=$1
        and u.ADMIN_USER_ID=$2::uuid
        and u.ACTIVE=true
        and ur.ROLE_CODE='OWNER'
      limit 1`,
    [clientId, userId],
  );
  return Boolean(result.rowCount);
}

export function registerAdminAccessRoutes(
  app: FastifyInstance,
  clientId: string,
) {
  app.get("/api/admin/me", async (req, reply) => {
    try {
      const p = await requirePermission(req, clientId, "admin.access");
      return {
        adminUserId: p.adminUserId,
        email: p.email,
        displayName: p.displayName,
        roles: p.localRoles,
        permissions: p.permissions,
        bootstrap: p.bootstrap,
      };
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.post("/api/admin/bootstrap/self", async (req, reply) => {
    const client = await db.connect();
    try {
      const identity = await requireIdentity(req, clientId);
      if (!legacyAdmin(identity)) throw new Error("ADMIN_ROLE_REQUIRED");

      await client.query("begin");
      await client.query("lock table config.ADMIN_USER in share row exclusive mode");

      const existing = await client.query(
        "select count(*)::int as count from config.ADMIN_USER where CLIENT_ID=$1",
        [clientId],
      );
      if (Number(existing.rows[0]?.count ?? 0) > 0) {
        throw new Error("ADMIN_BOOTSTRAP_ALREADY_COMPLETE");
      }

      const created = await client.query(
        `insert into config.ADMIN_USER
          (CLIENT_ID,ACCOUNT_ID,EMAIL,DISPLAY_NAME,AUTH_PROVIDER,AUTH_SUBJECT,ACTIVE,IS_OWNER,CREATED_BY)
         values($1,$2::uuid,$3,$4,$5,$6,true,true,$3)
         returning ADMIN_USER_ID,EMAIL,DISPLAY_NAME,ACTIVE,IS_OWNER`,
        [
          clientId,
          identity.accountId,
          identity.email,
          identity.email.split("@")[0],
          identity.provider,
          identity.subject,
        ],
      );
      const user = created.rows[0];

      await client.query(
        `insert into config.ADMIN_USER_ROLE(CLIENT_ID,ADMIN_USER_ID,ROLE_CODE)
         values($1,$2::uuid,'OWNER')`,
        [clientId, user.admin_user_id],
      );

      await client.query("commit");

      return reply.code(201).send({
        adminUserId: user.admin_user_id,
        email: user.email,
        displayName: user.display_name,
        roles: ["OWNER"],
        bootstrapComplete: true,
      });
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return replyAdminError(reply, e);
    } finally {
      client.release();
    }
  });

  app.get("/api/admin/permissions", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "role.read");
      const result = await db.query(
        `select PERMISSION_CODE,CATEGORY,DESCRIPTION,DANGEROUS
           from config.ADMIN_PERMISSION
          order by CATEGORY,PERMISSION_CODE`,
      );
      return result.rows;
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.get("/api/admin/roles", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "role.read");
      const result = await db.query(
        `select
            r.ROLE_CODE,
            r.ROLE_NAME,
            r.DESCRIPTION,
            r.SYSTEM_ROLE,
            r.ACTIVE,
            COALESCE(
              array_agg(rp.PERMISSION_CODE order by rp.PERMISSION_CODE)
                filter(where rp.PERMISSION_CODE is not null),
              '{}'
            ) as permissions
           from config.ADMIN_ROLE r
           left join config.ADMIN_ROLE_PERMISSION rp
             on rp.CLIENT_ID=r.CLIENT_ID
            and rp.ROLE_CODE=r.ROLE_CODE
          where r.CLIENT_ID=$1
          group by r.ROLE_CODE,r.ROLE_NAME,r.DESCRIPTION,r.SYSTEM_ROLE,r.ACTIVE
          order by r.SYSTEM_ROLE desc,r.ROLE_NAME`,
        [clientId],
      );
      return result.rows;
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.post("/api/admin/roles", async (req, reply) => {
    try {
      const principal = await requirePermission(req, clientId, "role.create");
      const body = (req.body ?? {}) as {
        roleCode?: string;
        roleName?: string;
        description?: string;
        permissions?: string[];
      };
      const roleCode = String(body.roleCode ?? "").trim().toUpperCase();
      const roleName = String(body.roleName ?? "").trim();
      const permissions = [
        ...new Set((body.permissions ?? []).map((x) => String(x).trim())),
      ];

      if (!/^[A-Z0-9_]{2,30}$/.test(roleCode))
        throw new Error("INVALID_ROLE_CODE");
      if (!roleName || roleName.length > 80)
        throw new Error("INVALID_ROLE_NAME");
      if (!(await roleCodesExist(clientId, [])))
        throw new Error("INVALID_ROLE");
      if (
        permissions.length &&
        Number(
          (
            await db.query(
              `select count(*)::int as count
                 from config.ADMIN_PERMISSION
                where PERMISSION_CODE=any($1::varchar[])`,
              [permissions],
            )
          ).rows[0]?.count ?? 0,
        ) !== permissions.length
      ) {
        throw new Error("INVALID_PERMISSION");
      }

      const client = await db.connect();
      try {
        await client.query("begin");
        const created = await client.query(
          `insert into config.ADMIN_ROLE
            (CLIENT_ID,ROLE_CODE,ROLE_NAME,DESCRIPTION,SYSTEM_ROLE,ACTIVE)
           values($1,$2,$3,$4,false,true)
           returning *`,
          [clientId, roleCode, roleName, body.description ?? null],
        );
        for (const permission of permissions) {
          await client.query(
            `insert into config.ADMIN_ROLE_PERMISSION
              (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
             values($1,$2,$3)`,
            [clientId, roleCode, permission],
          );
        }
        await client.query("commit");
        await auditAdminChange(
          clientId,
          principal,
          "ADMIN_ROLE",
          roleCode,
          "CREATE",
          null,
          { ...created.rows[0], permissions },
        );
        return reply.code(201).send({
          ...created.rows[0],
          permissions,
        });
      } catch (e) {
        await client.query("rollback");
        throw e;
      } finally {
        client.release();
      }
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.patch("/api/admin/roles/:roleCode", async (req, reply) => {
    try {
      const principal = await requirePermission(req, clientId, "role.update");
      const { roleCode: rawRoleCode } = req.params as { roleCode: string };
      const roleCode = rawRoleCode.toUpperCase();
      const body = (req.body ?? {}) as {
        roleName?: string;
        description?: string | null;
        active?: boolean;
      };

      const before = await db.query(
        "select * from config.ADMIN_ROLE where CLIENT_ID=$1 and ROLE_CODE=$2",
        [clientId, roleCode],
      );
      if (!before.rowCount) throw new Error("ADMIN_ROLE_NOT_FOUND");
      if (before.rows[0].system_role)
        throw new Error("SYSTEM_ROLE_IMMUTABLE");

      const roleName =
        body.roleName === undefined
          ? before.rows[0].role_name
          : String(body.roleName).trim();
      if (!roleName || roleName.length > 80)
        throw new Error("INVALID_ROLE_NAME");

      const updated = await db.query(
        `update config.ADMIN_ROLE
            set ROLE_NAME=$3,
                DESCRIPTION=$4,
                ACTIVE=$5,
                LAST_UPDATE_DSTAMP=now()
          where CLIENT_ID=$1 and ROLE_CODE=$2
          returning *`,
        [
          clientId,
          roleCode,
          roleName,
          body.description === undefined
            ? before.rows[0].description
            : body.description,
          body.active === undefined ? before.rows[0].active : body.active,
        ],
      );

      await auditAdminChange(
        clientId,
        principal,
        "ADMIN_ROLE",
        roleCode,
        "UPDATE",
        before.rows[0],
        updated.rows[0],
      );
      return updated.rows[0];
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.put(
    "/api/admin/roles/:roleCode/permissions",
    async (req, reply) => {
      const client = await db.connect();
      try {
        const principal = await requirePermission(
          req,
          clientId,
          "role.permission.assign",
        );
        const { roleCode: rawRoleCode } = req.params as { roleCode: string };
        const roleCode = rawRoleCode.toUpperCase();
        const body = (req.body ?? {}) as { permissions?: string[] };
        const permissions = [
          ...new Set((body.permissions ?? []).map((x) => String(x).trim())),
        ];

        const role = await db.query(
          "select * from config.ADMIN_ROLE where CLIENT_ID=$1 and ROLE_CODE=$2",
          [clientId, roleCode],
        );
        if (!role.rowCount) throw new Error("ADMIN_ROLE_NOT_FOUND");
        if (role.rows[0].system_role && roleCode === "OWNER")
          throw new Error("OWNER_ROLE_PERMISSIONS_IMMUTABLE");

        const valid = await db.query(
          `select count(*)::int as count
             from config.ADMIN_PERMISSION
            where PERMISSION_CODE=any($1::varchar[])`,
          [permissions],
        );
        if (Number(valid.rows[0]?.count ?? 0) !== permissions.length)
          throw new Error("INVALID_PERMISSION");

        const before = await db.query(
          `select COALESCE(array_agg(PERMISSION_CODE order by PERMISSION_CODE),'{}') as permissions
             from config.ADMIN_ROLE_PERMISSION
            where CLIENT_ID=$1 and ROLE_CODE=$2`,
          [clientId, roleCode],
        );

        await client.query("begin");
        await client.query(
          "delete from config.ADMIN_ROLE_PERMISSION where CLIENT_ID=$1 and ROLE_CODE=$2",
          [clientId, roleCode],
        );
        for (const permission of permissions) {
          await client.query(
            `insert into config.ADMIN_ROLE_PERMISSION
              (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
             values($1,$2,$3)`,
            [clientId, roleCode, permission],
          );
        }
        await client.query("commit");

        await auditAdminChange(
          clientId,
          principal,
          "ADMIN_ROLE",
          roleCode,
          "PERMISSIONS",
          { permissions: before.rows[0]?.permissions ?? [] },
          { permissions },
        );
        return { roleCode, permissions };
      } catch (e) {
        try {
          await client.query("rollback");
        } catch {}
        return replyAdminError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  app.get("/api/admin/users", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "user.read");
      const result = await db.query(
        `select
            u.ADMIN_USER_ID,
            u.EMAIL,
            u.DISPLAY_NAME,
            u.ACTIVE,
            u.IS_OWNER,
            u.AUTH_PROVIDER,
            u.AUTH_SUBJECT,
            u.LAST_LOGIN_DSTAMP,
            u.CREATED_DSTAMP,
            COALESCE(
              array_agg(ur.ROLE_CODE order by ur.ROLE_CODE)
                filter(where ur.ROLE_CODE is not null),
              '{}'
            ) as roles
           from config.ADMIN_USER u
           left join config.ADMIN_USER_ROLE ur
             on ur.CLIENT_ID=u.CLIENT_ID
            and ur.ADMIN_USER_ID=u.ADMIN_USER_ID
          where u.CLIENT_ID=$1
          group by
            u.ADMIN_USER_ID,u.EMAIL,u.DISPLAY_NAME,u.ACTIVE,u.IS_OWNER,
            u.AUTH_PROVIDER,u.AUTH_SUBJECT,u.LAST_LOGIN_DSTAMP,u.CREATED_DSTAMP
          order by u.ACTIVE desc,LOWER(u.EMAIL)`,
        [clientId],
      );
      return result.rows;
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.post("/api/admin/users", async (req, reply) => {
    const client = await db.connect();
    try {
      const principal = await requirePermission(req, clientId, "user.create");
      const body = (req.body ?? {}) as {
        email?: string;
        displayName?: string;
        roles?: string[];
      };
      const email = String(body.email ?? "").trim().toLowerCase();
      const displayName = String(body.displayName ?? "").trim() || null;
      const roles = [
        ...new Set((body.roles ?? []).map((x) => String(x).trim().toUpperCase())),
      ];

      if (
        !email ||
        email.length > 254 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
      ) {
        throw new Error("INVALID_EMAIL");
      }
      if (displayName && displayName.length > 120)
        throw new Error("INVALID_DISPLAY_NAME");
      if (!(await roleCodesExist(clientId, roles)))
        throw new Error("INVALID_ROLE");

      await client.query("begin");
      const created = await client.query(
        `insert into config.ADMIN_USER
          (CLIENT_ID,EMAIL,DISPLAY_NAME,ACTIVE,IS_OWNER,CREATED_BY)
         values($1,$2,$3,true,$4,$5)
         returning *`,
        [
          clientId,
          email,
          displayName,
          roles.includes("OWNER"),
          principal.email,
        ],
      );
      const user = created.rows[0];

      for (const role of roles) {
        await client.query(
          `insert into config.ADMIN_USER_ROLE(CLIENT_ID,ADMIN_USER_ID,ROLE_CODE)
           values($1,$2::uuid,$3)`,
          [clientId, user.admin_user_id, role],
        );
      }
      await client.query("commit");

      await auditAdminChange(
        clientId,
        principal,
        "ADMIN_USER",
        user.admin_user_id,
        "CREATE",
        null,
        { ...user, roles },
      );
      return reply.code(201).send({ ...user, roles });
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return replyAdminError(reply, e);
    } finally {
      client.release();
    }
  });

  app.patch("/api/admin/users/:userId", async (req, reply) => {
    try {
      const { userId } = req.params as { userId: string };
      const body = (req.body ?? {}) as {
        displayName?: string | null;
        active?: boolean;
      };
      const required =
        body.active === false ? "user.disable" : "user.update";
      const principal = await requirePermission(req, clientId, required);

      const before = await db.query(
        "select * from config.ADMIN_USER where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid",
        [clientId, userId],
      );
      if (!before.rowCount) throw new Error("ADMIN_USER_NOT_FOUND");

      if (
        body.active === false &&
        (await isActiveOwner(clientId, userId)) &&
        (await activeOwnerCount(clientId)) <= 1
      ) {
        throw new Error("LAST_OWNER_PROTECTED");
      }

      const displayName =
        body.displayName === undefined
          ? before.rows[0].display_name
          : body.displayName == null
            ? null
            : String(body.displayName).trim();
      if (displayName && displayName.length > 120)
        throw new Error("INVALID_DISPLAY_NAME");

      const updated = await db.query(
        `update config.ADMIN_USER
            set DISPLAY_NAME=$3,
                ACTIVE=$4,
                LAST_UPDATE_DSTAMP=now()
          where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid
          returning *`,
        [
          clientId,
          userId,
          displayName,
          body.active === undefined ? before.rows[0].active : body.active,
        ],
      );

      await auditAdminChange(
        clientId,
        principal,
        "ADMIN_USER",
        userId,
        "UPDATE",
        before.rows[0],
        updated.rows[0],
      );
      return updated.rows[0];
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });

  app.put("/api/admin/users/:userId/roles", async (req, reply) => {
    const client = await db.connect();
    try {
      const principal = await requirePermission(
        req,
        clientId,
        "user.role.assign",
      );
      const { userId } = req.params as { userId: string };
      const body = (req.body ?? {}) as { roles?: string[] };
      const roles = [
        ...new Set((body.roles ?? []).map((x) => String(x).trim().toUpperCase())),
      ];

      const user = await db.query(
        "select * from config.ADMIN_USER where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid",
        [clientId, userId],
      );
      if (!user.rowCount) throw new Error("ADMIN_USER_NOT_FOUND");
      if (!(await roleCodesExist(clientId, roles)))
        throw new Error("INVALID_ROLE");

      const before = await db.query(
        `select COALESCE(array_agg(ROLE_CODE order by ROLE_CODE),'{}') as roles
           from config.ADMIN_USER_ROLE
          where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid`,
        [clientId, userId],
      );
      const oldRoles: string[] = before.rows[0]?.roles ?? [];

      if (
        user.rows[0].active &&
        oldRoles.includes("OWNER") &&
        !roles.includes("OWNER") &&
        (await activeOwnerCount(clientId)) <= 1
      ) {
        throw new Error("LAST_OWNER_PROTECTED");
      }

      await client.query("begin");
      await client.query(
        "delete from config.ADMIN_USER_ROLE where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid",
        [clientId, userId],
      );
      for (const role of roles) {
        await client.query(
          `insert into config.ADMIN_USER_ROLE(CLIENT_ID,ADMIN_USER_ID,ROLE_CODE)
           values($1,$2::uuid,$3)`,
          [clientId, userId, role],
        );
      }
      await client.query(
        `update config.ADMIN_USER
            set IS_OWNER=$3,
                LAST_UPDATE_DSTAMP=now()
          where CLIENT_ID=$1 and ADMIN_USER_ID=$2::uuid`,
        [clientId, userId, roles.includes("OWNER")],
      );
      await client.query("commit");

      await auditAdminChange(
        clientId,
        principal,
        "ADMIN_USER",
        userId,
        "ROLES",
        { roles: oldRoles },
        { roles },
      );
      return { adminUserId: userId, roles };
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return replyAdminError(reply, e);
    } finally {
      client.release();
    }
  });

  app.get("/api/admin/audit", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "audit.read");
      const query = req.query as {
        entityType?: string;
        entityId?: string;
        limit?: string;
      };
      const limit = Math.max(
        1,
        Math.min(200, Number(query.limit ?? 100) || 100),
      );
      const result = await db.query(
        `select
            AUDIT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,
            BEFORE_DATA,AFTER_DATA,CREATED_DSTAMP
           from audit.AUDIT_EVENT
          where CLIENT_ID=$1
            and ($2::varchar is null or ENTITY_TYPE=$2)
            and ($3::varchar is null or ENTITY_ID=$3)
          order by CREATED_DSTAMP desc,AUDIT_ID desc
          limit $4`,
        [clientId, query.entityType ?? null, query.entityId ?? null, limit],
      );
      return result.rows;
    } catch (e) {
      return replyAdminError(reply, e);
    }
  });
}
