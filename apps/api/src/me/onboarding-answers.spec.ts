import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ApiErrorResponse } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SportsModule } from "@repo/core/sports";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { OnboardingAnswersController } from "./onboarding-answers.controller.js";

/**
 * `PUT /v1/me/onboarding-answers` over real HTTP and Postgres (ADR-024 §2,
 * ADR-035 §4, §5): the answers fill only what the profile leaves empty.
 * There is no read endpoint for these fields yet, so the stored profile is
 * read back with SQL. Sessions come from `x-test-user` through a fake `AuthService`.
 */
describe("PUT /v1/me/onboarding-answers (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  const users: string[] = [];
  const inactiveSport = `retired-${randomUUID().slice(0, 8)}`;

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function newUser(): Promise<string> {
    const id = randomUUID();
    users.push(id);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Compte", `${id}@test.local`]);
    return id;
  }

  function put(user: string | null, body: unknown): Promise<Response> {
    return fetch(`${baseUrl}/v1/me/onboarding-answers`, {
      method: "PUT",
      headers: {
        "content-type": "application/json",
        ...(user ? { "x-test-user": user } : {}),
      },
      body: JSON.stringify(body),
    });
  }

  async function profileOf(user: string) {
    const [row] = await sql(
      `select first_name, last_name, to_char(birth_date, 'YYYY-MM-DD') as birth_date, gender, level, goals::text[] as goals
         from users.user_profile where user_id = $1`,
      [user],
    );
    return row;
  }

  async function sportsOf(user: string): Promise<string[]> {
    const rows = await sql("select sport_code from users.user_sport where user_id = $1 order by position", [user]);
    return rows.map((row: { sport_code: string }) => row.sport_code);
  }

  const answers = {
    firstName: "  Léa ",
    lastName: "Martin",
    birthDate: "1990-04-12",
    gender: "female",
    sportCodes: ["ride", "run"],
    goals: ["health", "compete"],
    level: "intermediate",
  };

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({
          databaseUrl: TEST_DATABASE_URL,
          redisUrl: TEST_REDIS_URL,
        }),
        UsersModule,
        SportsModule,
      ],
      controllers: [OnboardingAnswersController],
      providers: [
        SessionGuard,
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? {
                    userId,
                    email: `${userId}@test.local`,
                    name: "Compte",
                    role: "user",
                    twoFactorEnabled: false,
                  }
                : null;
            },
          },
        },
        { provide: APP_PIPE, useClass: ZodValidationPipe },
        { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
        { provide: APP_FILTER, useClass: GlobalExceptionFilter },
      ],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;

    await sql(
      "insert into sports.sport_type (code, category, icon_name, is_active) values ($1, 'test', 'figure.run', false)",
      [inactiveSport],
    );
  }, 30_000);

  afterAll(async () => {
    if (app) {
      await sql('delete from "user" where id = any($1)', [users]);
      await sql("delete from sports.sport_type where code = $1", [inactiveSport]);
      await app.close();
    }
  });

  it("writes every answer on a new account, sports in the order of selection", async () => {
    const user = await newUser();

    const response = await put(user, answers);

    expect(response.status).toBe(204);
    expect(await profileOf(user)).toEqual({
      first_name: "Léa",
      last_name: "Martin",
      birth_date: "1990-04-12",
      gender: "female",
      level: "intermediate",
      goals: ["health", "compete"],
    });
    expect(await sportsOf(user)).toEqual(["ride", "run"]);
  });

  it("changes nothing on a second call with other answers", async () => {
    const user = await newUser();
    expect((await put(user, answers)).status).toBe(204);
    const before = await profileOf(user);

    const response = await put(user, {
      firstName: "Paul",
      lastName: "Durand",
      birthDate: "1985-01-01",
      gender: "male",
      sportCodes: ["swim"],
      goals: [],
      level: "professional",
    });

    expect(response.status).toBe(204);
    expect(await profileOf(user)).toEqual(before);
    expect(await sportsOf(user)).toEqual(["ride", "run"]);
  });

  it("keeps the first name of an older account and fills the rest, without touching user.name", async () => {
    const user = await newUser();
    await sql("insert into users.user_profile (user_id, first_name) values ($1, 'Léonie')", [user]);

    expect((await put(user, answers)).status).toBe(204);

    expect(await profileOf(user)).toEqual({
      first_name: "Léonie",
      last_name: "Martin",
      birth_date: "1990-04-12",
      gender: "female",
      level: "intermediate",
      goals: ["health", "compete"],
    });
    expect((await sql('select name from "user" where id = $1', [user]))[0].name).toBe("Compte");
  });

  it("never replaces sports the athlete already has", async () => {
    const user = await newUser();
    await sql("insert into users.user_sport (user_id, sport_code, position) values ($1, 'hike', 0)", [user]);

    expect((await put(user, answers)).status).toBe(204);

    expect(await sportsOf(user)).toEqual(["hike"]);
    expect((await profileOf(user)).first_name).toBe("Léa");
  });

  describe("age limit of 15, to the day (UTC)", () => {
    const today = new Date();
    const fifteenthBirthday = (offsetDays: number) =>
      new Date(Date.UTC(today.getUTCFullYear() - 15, today.getUTCMonth(), today.getUTCDate() + offsetDays))
        .toISOString()
        .slice(0, 10);

    it("accepts an athlete whose 15th birthday is today", async () => {
      const user = await newUser();
      expect((await put(user, { ...answers, birthDate: fifteenthBirthday(0) })).status).toBe(204);
    });

    it("refuses an athlete who turns 15 tomorrow, and writes nothing", async () => {
      const user = await newUser();
      const response = await put(user, {
        ...answers,
        birthDate: fifteenthBirthday(1),
      });

      expect(response.status).toBe(422);
      expect(((await response.json()) as ApiErrorResponse).error.details).toEqual([
        { field: "birthDate", message: expect.any(String) },
      ]);
      expect(await profileOf(user)).toBeUndefined();
    });
  });

  it.each([
    ["an empty last name", { lastName: "   " }, "lastName"],
    ["a missing first name", { firstName: undefined }, "firstName"],
    ["a malformed birth date", { birthDate: "12/04/1990" }, "birthDate"],
    ["no sport", { sportCodes: [] }, "sportCodes"],
    ["an unknown sport", { sportCodes: ["run", "curling"] }, "sportCodes"],
    ["an inactive sport", { sportCodes: [inactiveSport] }, "sportCodes"],
    ["a duplicate sport", { sportCodes: ["run", "run"] }, "sportCodes"],
    ["a duplicate goal", { goals: ["health", "health"] }, "goals"],
    ["an unknown goal", { goals: ["fame"] }, "goals.0"],
    ["an unknown gender", { gender: "robot" }, "gender"],
    ["an unknown level", { level: "legend" }, "level"],
  ])("answers 422 for %s and writes nothing", async (_case, override, field) => {
    const user = await newUser();

    const response = await put(user, { ...answers, ...override });

    expect(response.status).toBe(422);
    const body = (await response.json()) as ApiErrorResponse;
    expect(body.error.details?.map((detail) => detail.field)).toContain(field);
    expect(await profileOf(user)).toBeUndefined();
    expect(await sportsOf(user)).toEqual([]);
  });

  it("deletes the athlete's sports with the account (ADR-035 §9)", async () => {
    const user = await newUser();
    expect((await put(user, answers)).status).toBe(204);

    await sql('delete from "user" where id = $1', [user]);

    expect(await sportsOf(user)).toEqual([]);
  });

  it("writes nothing when the write fails halfway (one transaction)", async () => {
    const user = await newUser();
    // A real failure after the profile is written: a trigger that rejects this athlete's sports.
    const trigger = `fail_${user.replaceAll("-", "_")}`;
    await sql(`create function users.${trigger}() returns trigger language plpgsql as $$
      begin raise exception 'simulated failure'; end $$`);
    await sql(`create trigger ${trigger} before insert on users.user_sport
      for each row when (new.user_id = '${user}') execute function users.${trigger}()`);
    try {
      expect((await put(user, answers)).status).toBe(500);
    } finally {
      await sql(`drop trigger ${trigger} on users.user_sport`);
      await sql(`drop function users.${trigger}()`);
    }

    expect(await profileOf(user)).toBeUndefined();
    expect(await sportsOf(user)).toEqual([]);
  });

  it("answers 401 without a session", async () => {
    expect((await put(null, answers)).status).toBe(401);
  });
});
