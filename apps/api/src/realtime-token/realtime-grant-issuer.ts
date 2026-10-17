import { Inject, Injectable } from "@nestjs/common";
import jwt from "jsonwebtoken";
import type { RealtimeGrantResponse } from "@repo/contracts";
import { ActivitiesService, activityNotFound } from "@repo/core/activities";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_GRANT_TTL_SECONDS,
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_ISSUER,
  parseTopic,
  realtimeGrantClaimsSchema,
} from "@repo/realtime";
import { CONFIG, type ApiEnv } from "../config/env.js";

/**
 * Signs subscription grants (ADR-034 §5). The gateway may not read the database (ADR-010 §1),
 * so the API checks here that the user may receive the topic, and the gateway only verifies
 * the signature.
 */
@Injectable()
export class RealtimeGrantIssuer {
  constructor(
    @Inject(CONFIG) private readonly config: ApiEnv,
    private readonly activities: ActivitiesService,
  ) {}

  /** A 60 s grant for `topic`; `404 activity_not_found` when the Activity is not visible. */
  async grant(userId: string, topic: string): Promise<RealtimeGrantResponse> {
    const parsed = parseTopic(topic);
    const visible = parsed.kind === "activity" && (await this.activities.getVisible(userId, parsed.activityId));
    if (!visible) {
      throw activityNotFound();
    }

    const claims = realtimeGrantClaimsSchema.parse({ sub: userId, topic });
    const grant = jwt.sign(claims, this.config.REALTIME_TOKEN_SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
      expiresIn: REALTIME_GRANT_TTL_SECONDS,
    });
    return { grant, expiresInS: REALTIME_GRANT_TTL_SECONDS };
  }
}
