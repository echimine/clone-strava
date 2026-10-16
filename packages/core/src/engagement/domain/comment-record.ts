/** An `engagement.comment` row (ADR-017, ADR-034 §2). */
export interface CommentRecord {
  id: string;
  activityId: string;
  userId: string;
  body: string;
  createdAt: Date;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
