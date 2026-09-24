import { z } from "zod";

/** `sport_type.code` (ADR-017): stable identifier, e.g. `run`, `ride`, `swim`. */
export const sportTypeCodeSchema = z.string().min(1);
export type SportTypeCode = z.infer<typeof sportTypeCodeSchema>;
