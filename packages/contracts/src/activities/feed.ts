import { z } from "zod";
import { visibilitySchema } from "../common/enums.js";
import { sportTypeCodeSchema } from "../sports/sport-type.js";

/** `GET /v1/feed` query (ADR-029): opaque keyset cursor, no page numbers. */
export const feedQuerySchema = z.object({
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});
export type FeedQuery = z.infer<typeof feedQuerySchema>;

/** Stats shown on a feed card; null when not computed or not tracked by the sport. */
export const feedActivityStatsSchema = z.object({
  distanceM: z.number().nullable(),
  movingTimeS: z.number().int().nullable(),
  elapsedTimeS: z.number().int().nullable(),
  elevationGainM: z.number().nullable(),
  /** The card's Allure for `pace` sports (ADR-036 §5). */
  avgSpeedMs: z.number().nullable(),
});

/** Route drawn on the card's static map (ADR-029): Google encoded polyline. */
export const feedActivityMapSchema = z.object({
  polyline: z.string().min(1),
  precision: z.literal(5),
});

export const feedAuthorSchema = z.object({
  id: z.uuid(),
  displayName: z.string(),
  avatarUrl: z.string().nullable(),
});
/** An athlete as shown next to their content: Activity author, comment author, kudos giver. */
export type FeedAuthor = z.infer<typeof feedAuthorSchema>;

export const feedEngagementSchema = z.object({
  kudosCount: z.number().int().nonnegative(),
  commentCount: z.number().int().nonnegative(),
  viewerHasKudoed: z.boolean(),
});

/** One activity card of the feed (ADR-029). */
export const feedItemSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  sportTypeCode: sportTypeCodeSchema,
  startedAt: z.iso.datetime(),
  visibility: visibilitySchema,
  locationName: z.string().nullable(),
  stats: feedActivityStatsSchema,
  map: feedActivityMapSchema.nullable(),
  /** The privacy zone removed the start or end of the route: "Départ et arrivée masqués" (ADR-036 §5). */
  routeTrimmed: z.boolean(),
  author: feedAuthorSchema,
  engagement: feedEngagementSchema,
  /** The last 3 kudos givers, most recent first (ADR-036 §5). */
  recentKudos: z.array(feedAuthorSchema).max(3),
  viewerIsAuthor: z.boolean(),
});
export type FeedItem = z.infer<typeof feedItemSchema>;

/** `GET /v1/feed` response (ADR-029): `nextCursor` is null on the last page. */
export const feedResponseSchema = z.object({
  items: z.array(feedItemSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type FeedResponse = z.infer<typeof feedResponseSchema>;

/** `PUT`/`DELETE /v1/activities/:id/kudos` response (ADR-029). */
export const kudosResponseSchema = z.object({
  activityId: z.uuid(),
  kudosCount: z.number().int().nonnegative(),
  viewerHasKudoed: z.boolean(),
});
export type KudosResponse = z.infer<typeof kudosResponseSchema>;
